import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import '../../models/bounding_box.dart';
import 'cache_paths.dart';
import 'region_database.dart';

/// Snapshot imutável de uma região cacheada — o "resultado do cache" que
/// o `AnalysisService` recebe e usa pra reidratar.
///
/// Note: **não** é a mesma coisa que `CachedRegionRow` (a data class do
/// Drift, gerada). `CachedRegion` é a "visão pública" — traz o
/// `BoundingBox` já materializado como objeto, e o `metadata` já
/// parseado como Map ao invés de string JSON.
class CachedRegion {
  final int id;
  final String municipio;
  final BoundingBox bbox;
  final String filePath;
  final int fileSizeBytes;

  /// Legado — sempre 0 hoje. Mantido pra compat com código antigo.
  final int tilesBytes;

  /// Legado — sempre null hoje. Mantido pra compat.
  final int? tilesMaxZoom;

  /// Já parseado. Ex: `{ "winners": ["G1", "G2"] }`.
  final Map<String, dynamic> metadata;

  const CachedRegion({
    required this.id,
    required this.municipio,
    required this.bbox,
    required this.filePath,
    required this.fileSizeBytes,
    required this.tilesBytes,
    required this.tilesMaxZoom,
    required this.metadata,
  });

  /// Total ocupado por essa região (GeoJSON + tiles legados = tudo).
  /// Usado por `_ensureSpace` pra calcular quanto liberar.
  int get totalBytes => fileSizeBytes + tilesBytes;
}

/// Cache regional — GeoJSON + metadados por município.
///
/// Regras (todas as constantes ficam no topo):
///
///   - Quota total: 600 MB, somando `fileSizeBytes + tilesBytes` de
///     todas as linhas. `_ensureSpace` roda antes de gravar, e
///     `enforceQuota` pode ser chamado externamente (não é hoje).
///
///   - TTL: 30 dias desde `lastAccessAt`. Renova a cada hit.
///     Verificado em dois lugares:
///       a) Em `get()`, on-demand: se a linha achada expirou, apaga
///          antes de responder null.
///       b) Em `pruneExpired()`, chamado no boot: apaga tudo que
///          está fora do prazo.
///
///   - Eviction (quando quota estoura): itera `evictionCandidates()`
///     (menos acessados primeiro) apagando até caber. Nunca toca no
///     mais acessado a menos que seja o único caminho.
class RegionCacheService {

  static final RegionCacheService _instance = RegionCacheService._();
  factory RegionCacheService() => _instance;
  RegionCacheService._();

  /// Getter pra a instância do banco. Encapsula o acesso — se um dia
  /// precisar mockar, muda aqui.
  RegionDatabase get _db => RegionDatabase.instance;


  /// 600 MB — orçamento total do cache em disco.
  /// Multiplicação em bytes: 600 * 1024 * 1024 = 629 145 600.
  ///
  /// Se quiser mudar, é uma linha. Efeito imediato — não precisa reboot.
  static const int maxBytes = 600 * 1024 * 1024;

  /// 30 dias — janela desde `lastAccessAt`. Cada hit reseta.
  static const Duration ttl = Duration(days: 30);


  /// "Existe alguma região cacheada que englobe (lat, lon)?"
  ///
  /// Retorna `null` se:
  ///   - Nenhuma linha bate no bbox (miss "normal").
  ///   - A linha achada expirou (é apagada antes de retornar).
  ///   - O arquivo em disco sumiu (limpa a linha "órfã").
  ///
  /// Em caso de hit válido: chama `touch()` (atualiza `lastAccessAt` +
  /// incrementa `accessCount`) e devolve o snapshot pronto.
  Future<CachedRegion?> get(double lat, double lon) async {
    // Consulta no Drift. Retorna null se nada bate.
    final row = await _db.findContaining(lat, lon);
    if (row == null) return null;

    // TTL: já passou o prazo? Descarta.
    if (DateTime.now().difference(row.lastAccessAt) > ttl) {
      debugPrint(
          '[cache] TTL expirado, removendo #${row.id} (${row.municipio})');
      await _deleteRow(row);
      return null;
    }

    // Consistência disco↔banco: se o arquivo GeoJSON não existe mais
    final file = File(row.filePath);
    if (!await file.exists()) {
      debugPrint('[cache] arquivo sumiu, removendo linha órfã #${row.id}');
      await _deleteRow(row);
      return null;
    }

    // Hit válido — marca acesso e devolve.
    await _db.touch(row.id);
    debugPrint('[cache] HIT #${row.id} ${row.municipio}');
    return _toModel(row);
  }


  /// Insere uma nova região no cache. Faz duas escritas coordenadas:
  ///
  ///   1) Uma linha no banco (com filePath temporariamente vazio, só
  ///      pra pegar o `id` autoincremento).
  ///   2) O arquivo `.geojson` em disco em `region_cache/<id>.geojson`.
  ///
  /// Depois faz um UPDATE pra pôr o `filePath` real na linha. Se algo
  /// falhar no meio (raro, mas possível), a linha fica "meio pronta" —
  /// próxima `get()` vai detectar (arquivo não existe) e limpar.
  ///
  /// Chama `_ensureSpace(size)` antes pra garantir que cabe.
  Future<CachedRegion> put({
    required String municipio,
    required BoundingBox bbox,
    required String geoJson,
    required Map<String, dynamic> metadata,
  }) async {
    // Codifica em UTF-8 uma vez só. `utf8.encode` retorna `List<int>`
    // (na verdade `Uint8List`). O `.length` dele é o tamanho em bytes.
    final bytes = utf8.encode(geoJson);
    final size = bytes.length;

    await _ensureSpace(size);

    final now = DateTime.now();

    // INSERT — pega id autoincremento de volta
    final id = await _db.into(_db.cachedRegions).insert(
          CachedRegionsCompanion.insert(
            municipio: municipio,
            minLat: bbox.minLat,
            maxLat: bbox.maxLat,
            minLon: bbox.minLon,
            maxLon: bbox.maxLon,
            filePath: '', // preenchido logo depois
            fileSizeBytes: size,
            createdAt: now,
            lastAccessAt: now,
            // `drift.Value(...)` pra opcionais que queremos explicitar.
            metadata: drift.Value(jsonEncode(metadata)),
          ),
        );

    final file = await CachePaths.regionFile(id);
    await file.writeAsBytes(bytes, flush: true);

    // UPDATE — corrige o filePath. Sem `Value(...)` os outros campos
    // ficam intocados.
    await (_db.update(_db.cachedRegions)..where((r) => r.id.equals(id))).write(
      CachedRegionsCompanion(filePath: drift.Value(file.path)),
    );

    debugPrint(
      '[cache] PUT #$id ($municipio, ${(size / 1024 / 1024).toStringAsFixed(2)} MB)',
    );

    // Devolve modelo pronto — quem chamou não precisa fazer outra query.
    return CachedRegion(
      id: id,
      municipio: municipio,
      bbox: bbox,
      filePath: file.path,
      fileSizeBytes: size,
      tilesBytes: 0,
      tilesMaxZoom: null,
      metadata: metadata,
    );
  }


  /// Apaga tudo que já passou do TTL. Chamado no `main.dart` no boot.
  ///
  /// Por que existir se `get()` já apaga expirados on-demand? Porque
  /// linhas que ninguém consulta ficariam ocupando disco pra sempre.
  /// Ex: usuário estudou 50 municípios, largou o app 40 dias. Todas
  /// expiraram, mas ninguém tentou acessar. O boot next dia limpa.
  Future<int> pruneExpired() async {
    final cutoff = DateTime.now().subtract(ttl);
    final expired = await _db.findExpired(cutoff);
    for (final row in expired) {
      await _deleteRow(row);
    }
    if (expired.isNotEmpty) {
      debugPrint('[cache] prune: ${expired.length} regiões expiradas');
    }
    return expired.length;
  }

  /// Verifica se estamos dentro da quota após uma escrita EXTERNA
  /// (ex: quando ainda tínhamos o `TileDownloader` gravando fora do
  /// controle direto do service). Hoje não é chamado por ninguém
  /// (o downloader morreu), mas fica pronto pro caso de reativar.
  Future<void> enforceQuota() async {
    var total = await _db.totalBytes();
    if (total <= maxBytes) return;

    debugPrint('[cache] enforceQuota: '
        '${(total / 1024 / 1024).toStringAsFixed(1)} MB usados > '
        '${(maxBytes / 1024 / 1024).toStringAsFixed(0)} MB. Iniciando eviction.');

    final candidates = await _db.evictionCandidates();
    for (final row in candidates) {
      if (total <= maxBytes) break;
      total -= (row.fileSizeBytes + row.tilesBytes);
      await _deleteRow(row);
    }
  }

  /// Delegator direto — quem chama já sabe o que faz.
  Future<int> totalBytes() => _db.totalBytes();


  /// Dump completo no console + retorna a mesma coisa como Map (útil pra
  /// UI de debug ou testes automatizados).
  ///
  /// Uso comum: chamar no `main.dart` a cada boot pra ver o estado atual.
  Future<Map<String, dynamic>> debugDump() async {
    // `.get()` executa a query e retorna a List. Sem where — pega tudo.
    final rows = await (_db.select(_db.cachedRegions)).get();
    final totalUsed = await _db.totalBytes();

    debugPrint('╔═══ cache dump ══════════════════════════════════════════');
    debugPrint('║ linhas: ${rows.length}');
    debugPrint('║ ocupado: ${(totalUsed / 1024 / 1024).toStringAsFixed(2)} MB '
        '/ ${(maxBytes / 1024 / 1024).toStringAsFixed(0)} MB');
    debugPrint('║ TTL: ${ttl.inDays} dias desde lastAccessAt');
    debugPrint('╟────────────────────────────────────────────────────────');

    // Copia pra não mutar a lista original (é read-only mas por hábito).
    final sorted = [...rows]
      ..sort((a, b) => b.accessCount.compareTo(a.accessCount));

    // Top 10 por accessCount — os "vips" do cache.
    for (final r in sorted.take(10)) {
      final ageDays = DateTime.now().difference(r.lastAccessAt).inDays;
      final geoMB = (r.fileSizeBytes / 1024 / 1024).toStringAsFixed(2);
      final tileMB = (r.tilesBytes / 1024 / 1024).toStringAsFixed(2);
      final zoomStr =
          r.tilesMaxZoom != null ? 'z≤${r.tilesMaxZoom}' : 'sem tiles';
      debugPrint('║ #${r.id} ${r.municipio} '
          '| geo=${geoMB}MB tiles=${tileMB}MB $zoomStr '
          '| acessos=${r.accessCount} | há ${ageDays}d');
    }
    debugPrint('╚═════════════════════════════════════════════════════════');

    // Retorno estruturado — pra tela de debug ou testes.
    return {
      'entries': rows.length,
      'totalBytes': totalUsed,
      'maxBytes': maxBytes,
      'ttlDays': ttl.inDays,
      'rows': rows
          .map((r) => {
                'id': r.id,
                'municipio': r.municipio,
                'geoBytes': r.fileSizeBytes,
                'tilesBytes': r.tilesBytes,
                'tilesMaxZoom': r.tilesMaxZoom,
                'accessCount': r.accessCount,
                'lastAccessAt': r.lastAccessAt.toIso8601String(),
                'filePath': r.filePath,
              })
          .toList(),
    };
  }

  /// "Reset" total — apaga arquivos + linhas. Útil pra dev,
  /// testes E2E, ou botão "limpar cache" numa futura tela de settings.
  Future<void> clear() async {
    final rows = await (_db.select(_db.cachedRegions)).get();
    for (final row in rows) {
      await _deleteRow(row);
    }
    debugPrint('[cache] cache limpo (${rows.length} registros)');
  }

  /// Garante que `total + newSize <= maxBytes`. Se não, itera candidatos
  /// de eviction (menos usados primeiro) apagando um por um até caber.
  ///
  /// Se, no fim, ainda não coube (raro — significa que `newSize` é
  /// maior que a quota inteira), o app tenta gravar mesmo assim.
  /// Próxima gravação vai estourar e recair aqui de novo.
  Future<void> _ensureSpace(int newSize) async {
    var total = await _db.totalBytes();
    if (total + newSize <= maxBytes) return;

    debugPrint('[cache] ensureSpace: '
        '${(total / 1024 / 1024).toStringAsFixed(1)} MB usados, '
        'precisa liberar para ${(newSize / 1024 / 1024).toStringAsFixed(1)} MB');

    final candidates = await _db.evictionCandidates();
    for (final row in candidates) {
      if (total + newSize <= maxBytes) break;
      // Vai atualizando `total` localmente pra não ter que re-query
      // depois de cada delete (O(n) queries vira O(1)).
      total -= (row.fileSizeBytes + row.tilesBytes);
      await _deleteRow(row);
    }
  }

  /// Apaga UMA linha e TODOS os arquivos dela em disco.
  ///
  /// Ordem: arquivo GeoJSON, depois pasta legada de tiles, depois linha
  /// do banco. Isso significa que se algo falhar no meio, a linha
  /// SEMPRE vai embora — não deixa lixo no banco apontando pra arquivo
  /// morto.
  Future<void> _deleteRow(CachedRegionRow row) async {
    // 1) Arquivo GeoJSON principal.
    if (row.filePath.isNotEmpty) {
      final file = File(row.filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint('[cache] falha ao remover ${row.filePath}: $e');
          // Continua mesmo assim — mais vale limpar o banco.
        }
      }
    }

    // 2) Pasta legada de tiles (se sobrou de testes anteriores).
    //    Recursivo pra apagar todos os z/x/y.png de uma vez.
    try {
      final tilesDir = await CachePaths.regionTilesDir(row.id);
      if (await tilesDir.exists()) {
        await tilesDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[cache] falha ao remover pasta de tiles de #${row.id}: $e');
    }

    // 3) Linha do banco. Se der erro aqui é problema sério; deixa
    //    propagar via `_db.deleteById` (que retorna Future<int>).
    await _db.deleteById(row.id);
  }

  /// Converte a data class do Drift (`CachedRegionRow`) no modelo público
  /// (`CachedRegion`). Materializa o bbox como objeto e parseia o
  /// metadata JSON.
  CachedRegion _toModel(CachedRegionRow row) {
    // Metadata pode ser null (linhas antigas) ou string vazia. Trata
    // ambos como "sem metadados" pra o cliente não precisar checar.
    Map<String, dynamic> meta = const {};
    final raw = row.metadata;
    if (raw != null && raw.isNotEmpty) {
      try {
        meta = jsonDecode(raw) as Map<String, dynamic>;
      } catch (e) {
        // JSON malformado (raro — só se corromper). Loga e ignora.
        debugPrint('[cache] metadata inválido em #${row.id}: $e');
      }
    }
    return CachedRegion(
      id: row.id,
      municipio: row.municipio,
      bbox: BoundingBox(
        minLat: row.minLat,
        maxLat: row.maxLat,
        minLon: row.minLon,
        maxLon: row.maxLon,
      ),
      filePath: row.filePath,
      fileSizeBytes: row.fileSizeBytes,
      tilesBytes: row.tilesBytes,
      tilesMaxZoom: row.tilesMaxZoom,
      metadata: meta,
    );
  }
}
