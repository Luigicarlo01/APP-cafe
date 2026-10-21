import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CacheEntry {
  final String municipio;
  final DateTime lastAccessed;
  final DateTime downloadedAt;
  final bool pinned;

  CacheEntry({
    required this.municipio,
    required this.lastAccessed,
    required this.downloadedAt,
    this.pinned = false,
  });

  bool get isExpired {
    if (pinned) return false;
    return DateTime.now().difference(lastAccessed).inDays >= 7;
  }

  Map<String, dynamic> toJson() => {
    'municipio': municipio,
    'lastAccessed': lastAccessed.toIso8601String(),
    'downloadedAt': downloadedAt.toIso8601String(),
    'pinned': pinned,
  };

  factory CacheEntry.fromJson(Map<String, dynamic> j) => CacheEntry(
    municipio: j['municipio'] as String,
    lastAccessed: DateTime.parse(j['lastAccessed'] as String),
    downloadedAt: DateTime.parse(j['downloadedAt'] as String),
    pinned: j['pinned'] as bool? ?? false,
  );

  CacheEntry copyWith({DateTime? lastAccessed, bool? pinned}) => CacheEntry(
    municipio: municipio,
    lastAccessed: lastAccessed ?? this.lastAccessed,
    downloadedAt: downloadedAt,
    pinned: pinned ?? this.pinned,
  );
}

class GeoJsonCacheManager {
  static final GeoJsonCacheManager _instance = GeoJsonCacheManager._internal();
  factory GeoJsonCacheManager() => _instance;
  GeoJsonCacheManager._internal();

  // Índice em memória: municipio → CacheEntry
  final Map<String, CacheEntry> _index = {};
  bool _initialized = false;


  /// Deve ser chamado uma vez na inicialização do app (ex: em main() ou no
  /// initState da tela raiz). Carrega o índice e roda a limpeza automática.
  Future<void> init() async {
    if (_initialized) return;
    await _loadIndex();
    await runCleanup();
    _initialized = true;
  }


  /// Retorna o conteúdo do GeoJSON cacheado, ou null se não existir / expirado.
  Future<String?> read(String municipio) async {
    await _ensureInit();
    final entry = _index[municipio];
    if (entry == null) return null;

    final file = await _geojsonFile(municipio);
    if (!file.existsSync()) {
      _index.remove(municipio);
      await _saveIndex();
      return null;
    }

    if (entry.isExpired) {
      await _deleteEntry(municipio);
      return null;
    }

    // Atualiza lastAccessed
    _index[municipio] = entry.copyWith(lastAccessed: DateTime.now());
    await _saveIndex();

    return file.readAsString();
  }

  /// Salva um GeoJSON em disco e registra no índice.
  Future<void> write(String municipio, String jsonString) async {
    await _ensureInit();
    final file = await _geojsonFile(municipio);
    await file.writeAsString(jsonString);

    _index[municipio] = CacheEntry(
      municipio: municipio,
      lastAccessed: DateTime.now(),
      downloadedAt: DateTime.now(),
    );
    await _saveIndex();
    debugPrint('💾 Cache salvo: $municipio');
  }

  /// Fixa um município — nunca será apagado automaticamente.
  Future<void> pin(String municipio) async {
    await _ensureInit();
    final entry = _index[municipio];
    if (entry == null) return;
    _index[municipio] = entry.copyWith(pinned: true);
    await _saveIndex();
    debugPrint('📌 Fixado: $municipio');
  }

  /// Remove o pin — volta a expirar normalmente.
  Future<void> unpin(String municipio) async {
    await _ensureInit();
    final entry = _index[municipio];
    if (entry == null) return;
    _index[municipio] = entry.copyWith(pinned: false);
    await _saveIndex();
    debugPrint('📌 Desafixado: $municipio');
  }

  /// Apaga manualmente um município do cache.
  Future<void> delete(String municipio) async {
    await _ensureInit();
    await _deleteEntry(municipio);
    debugPrint('🗑️ Cache removido manualmente: $municipio');
  }

  /// Apaga todos os municípios não fixados.
  Future<void> clearAll({bool includePinned = false}) async {
    await _ensureInit();
    final toDelete = _index.keys.where((k) {
      if (includePinned) return true;
      return !(_index[k]?.pinned ?? false);
    }).toList();

    for (final mun in toDelete) {
      await _deleteEntry(mun);
    }
    debugPrint('🗑️ Cache limpo (${toDelete.length} municípios removidos)');
  }

  /// Remove todos os municípios expirados (TTL 7 dias sem acesso).
  /// Chamado automaticamente no init(), mas pode ser chamado manualmente.
  Future<int> runCleanup() async {
    await _ensureInit();
    final expired = _index.values.where((e) => e.isExpired).toList();
    for (final e in expired) {
      await _deleteEntry(e.municipio);
    }
    if (expired.isNotEmpty) {
      debugPrint('🧹 Cleanup: ${expired.length} municípios expirados removidos');
    }
    return expired.length;
  }

  /// Lista de entradas no cache — útil para exibir na UI.
  Future<List<CacheEntry>> entries() async {
    await _ensureInit();
    return _index.values.toList()
      ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
  }

  /// Tamanho total em bytes dos arquivos cacheados.
  Future<int> totalSizeBytes() async {
    await _ensureInit();
    int total = 0;
    for (final mun in _index.keys) {
      final f = await _geojsonFile(mun);
      if (f.existsSync()) total += f.lengthSync();
    }
    return total;
  }


  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  Future<Directory> _cacheDir() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/geojson_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _geojsonFile(String municipio) async {
    final dir = await _cacheDir();
    return File('${dir.path}/$municipio.geojson');
  }

  Future<File> _indexFile() async {
    final dir = await _cacheDir();
    return File('${dir.path}/_index.json');
  }

  Future<void> _loadIndex() async {
    try {
      final file = await _indexFile();
      if (!file.existsSync()) return;
      final raw = jsonDecode(file.readAsStringSync()) as List;
      for (final item in raw) {
        final entry = CacheEntry.fromJson(item as Map<String, dynamic>);
        _index[entry.municipio] = entry;
      }
      debugPrint('📂 Índice de cache carregado: ${_index.length} municípios');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar índice de cache: $e');
    }
  }

  Future<void> _saveIndex() async {
    try {
      final file = await _indexFile();
      final raw = jsonEncode(_index.values.map((e) => e.toJson()).toList());
      await file.writeAsString(raw);
    } catch (e) {
      debugPrint('⚠️ Erro ao salvar índice de cache: $e');
    }
  }

  Future<void> _deleteEntry(String municipio) async {
    _index.remove(municipio);
    final file = await _geojsonFile(municipio);
    if (file.existsSync()) await file.delete();
    await _saveIndex();
  }
}