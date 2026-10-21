import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'cache_paths.dart';

// Necessário pra herança `_$RegionDatabase` funcionar
part 'region_database.g.dart';

/// A tabela que guarda o cache regional. Cada linha representa uma
/// região cacheada (município) com seu GeoJSON em disco.
///
/// **Anotação `@DataClassName`**: instrui o Drift a gerar a data class
/// com o nome `CachedRegionRow` (senão viraria `CachedRegion`, que já
/// usamos no service — evita colisão de nomes).
@DataClassName('CachedRegionRow')
class CachedRegions extends Table {

  /// Auto-incremento. Cada linha nova recebe um id único.
  /// Usado como nome do arquivo em disco também: `region_cache/<id>.geojson`.
  ///
  /// Padrão do Drift: chamar `integer().autoIncrement()()` (duplo
  /// parênteses — o primeiro obtém o `ColumnBuilder`, o segundo o
  /// finaliza pra virar coluna).
  IntColumn get id => integer().autoIncrement()();


  /// Nome do município no formato normalizado do backend
  /// (ex: "VICOSA_2026", "OLHOS_D_AGUA_2026").
  /// Restrição de tamanho vira `TEXT` com CHECK no SQLite.
  TextColumn get municipio => text().withLength(min: 1, max: 200)();

  // Esses 4 valores permitem a consulta "qual região contém este ponto?".

  RealColumn get minLat => real()();
  RealColumn get maxLat => real()();
  RealColumn get minLon => real()();
  RealColumn get maxLon => real()();


  /// Caminho absoluto do `.geojson`. Guardar o caminho (em vez de só o
  /// id) permite mover a pasta no futuro sem quebrar linhas antigas
  /// (bastaria uma migration reescrevendo o path).
  TextColumn get filePath => text()();

  /// Tamanho do arquivo em bytes. Somado com `tilesBytes` (legado) pra
  /// calcular ocupação total e decidir eviction.
  IntColumn get fileSizeBytes => integer()();


  /// Quando a linha foi criada (primeira vez que o município foi
  /// baixado). O Drift converte automaticamente pra `INTEGER` (unix
  /// seconds) no SQLite.
  DateTimeColumn get createdAt => dateTime()();

  /// Quando a linha foi usada por último. Atualizado por `touch()` a
  /// cada hit no cache. É a coluna que o TTL usa (30 dias).
  DateTimeColumn get lastAccessAt => dateTime()();

  /// Quantas vezes essa região já foi hit no cache. Ordena a eviction:
  /// linhas com `accessCount` baixo saem primeiro.
  ///
  /// `withDefault(const Constant(0))` faz o SQLite usar 0 quando o INSERT
  /// não passa esse campo — útil pra código que só se preocupa com o
  /// básico.
  IntColumn get accessCount => integer().withDefault(const Constant(0))();


  /// JSON serializado com dados que o backend devolveu junto: hoje só
  /// `winners: [...]`. Nullable pra permitir linhas legadas de v1.
  ///
  /// Usar text/JSON aqui (em vez de tabela filha) é uma escolha
  /// consciente: torna o cache "genérico" — se o backend adicionar
  /// campos novos, o cliente não precisa migração.
  TextColumn get metadata => text().nullable()();

  // Estes campos existiam pro TileDownloader adaptativo por região

  IntColumn get tilesBytes => integer().withDefault(const Constant(0))();
  IntColumn get tilesMaxZoom => integer().nullable()();
}

/// A "database" do Drift — expõe as queries pra fora.
///
/// A anotação `@DriftDatabase(tables: [CachedRegions])` avisa o build_runner
/// pra gerar `_$RegionDatabase` com getters pra cada tabela
/// (`db.cachedRegions`), classes de suporte, etc.
@DriftDatabase(tables: [CachedRegions])
class RegionDatabase extends _$RegionDatabase {

  /// Construtor **privado** — impede que outros arquivos façam
  /// `RegionDatabase()` e abram uma segunda conexão SQLite pro mesmo
  /// arquivo. SQLite tolera múltiplas conexões, mas gera `SQLITE_BUSY`
  /// se ambas tentarem escrever ao mesmo tempo. Uma só conexão evita.
  RegionDatabase._() : super(_openConnection());

  /// Instância única. `static final` é lazy — só cria de verdade no
  /// primeiro acesso, e o Dart garante que isso é thread-safe.
  static final RegionDatabase instance = RegionDatabase._();


  /// Toda vez que você mudar a estrutura da tabela, bumpe esse número
  /// e adicione a lógica em `migration.onUpgrade`.
  ///
  /// Histórico:
  ///   v1: schema inicial (sem tilesBytes/tilesMaxZoom).
  ///   v2: adicionou tilesBytes + tilesMaxZoom (originalmente pro
  ///       TileDownloader — hoje sempre 0/null).
  @override
  int get schemaVersion => 2;

  /// Diz ao Drift como migrar de uma versão pra outra.
  ///
  /// - `onCreate`: banco novo. Cria tudo do zero.
  /// - `onUpgrade`: banco existente, mas versão antiga. Adapta.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Adiciona as duas colunas legadas de v1 → v2.
            await m.addColumn(cachedRegions, cachedRegions.tilesBytes);
            await m.addColumn(cachedRegions, cachedRegions.tilesMaxZoom);
          }
        },
      );


  /// A query espacial central: "existe alguma linha cujo bbox contenha
  /// (lat, lon)?"
  ///
  /// Se sim, retorna a de **menor bbox** (mais específica). Se dois
  /// municípios têm bboxes que se sobrepõem no ponto, o menor
  /// (provavelmente o correto) ganha.
  ///
  /// O `..` (cascade operator) permite encadear chamadas na mesma
  /// referência sem repetir o alvo. Aqui `..where`, `..orderBy`,
  /// `..limit` são todos aplicados à mesma `SelectStatement`.
  Future<CachedRegionRow?> findContaining(double lat, double lon) async {
    final query = select(cachedRegions)
      // WHERE minLat <= lat AND maxLat >= lat AND minLon <= lon AND maxLon >= lon
      ..where((r) =>
          r.minLat.isSmallerOrEqualValue(lat) &
          r.maxLat.isBiggerOrEqualValue(lat) &
          r.minLon.isSmallerOrEqualValue(lon) &
          r.maxLon.isBiggerOrEqualValue(lon))
      // ORDER BY (maxLat - minLat) * (maxLon - minLon) ASC
      ..orderBy([
        (r) => OrderingTerm(
              expression:
                  (r.maxLat - r.minLat) * (r.maxLon - r.minLon),
              mode: OrderingMode.asc,
            ),
      ])
      ..limit(1);
    // `getSingleOrNull` executa a query e retorna null se vazio (em vez
    // de exceção). É o que queremos aqui — "nada bate" é resultado válido.
    return query.getSingleOrNull();
  }

  /// Lookup por chave primária. Usado quando já sabemos o `id` (ex: no
  /// TileDownloader legado, ou pra ler estado atualizado depois de um
  /// update em outra parte do código).
  Future<CachedRegionRow?> findById(int id) {
    return (select(cachedRegions)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  /// Marca um hit no cache — atualiza `lastAccessAt` e incrementa
  /// `accessCount`.
  ///
  /// Uso `customStatement` (SQL cru) porque quero **atomicidade**:
  /// o `+ 1` precisa acontecer no SQLite, não em Dart. Se fizesse
  /// "read → increment → write" em Dart, duas chamadas concorrentes
  /// poderiam perder um incremento. `UPDATE ... SET count = count + 1`
  /// é sempre atômico.
  Future<void> touch(int id) async {
    final now = DateTime.now();
    await customStatement(
      'UPDATE cached_regions '
      'SET last_access_at = ?, access_count = access_count + 1 '
      'WHERE id = ?',
      // Drift convert DateTime pra unix seconds no SQLite. Reproduzimos
      // essa conversão aqui pra manter consistência.
      [now.millisecondsSinceEpoch ~/ 1000, id],
    );
  }

  /// Atualiza os campos de tiles depois de um download. Legado hoje
  /// (não é mais chamado), mantido pra compat.
  Future<void> updateTilesInfo(int id,
      {required int tilesBytes, required int maxZoom}) {
    return (update(cachedRegions)..where((r) => r.id.equals(id))).write(
      CachedRegionsCompanion(
        // `Value` marca "quero que esse campo seja escrito"
        tilesBytes: Value(tilesBytes),
        tilesMaxZoom: Value(maxZoom),
      ),
    );
  }

  /// Soma total de bytes ocupados por todas as linhas: GeoJSON + tiles.
  ///
  /// **Sobre `total()` vs `sum()`**: em SQLite, `SUM` numa coluna de
  /// inteiros pode devolver `INTEGER` ou `REAL` dependendo dos valores
  /// (overflow → REAL). O Drift traduz isso de forma que varia entre
  /// versões, causando erros de compilação `int != double`. `total()`
  /// (mapeia pro `TOTAL()` do SQLite) sempre devolve REAL. Convertemos
  /// pra int no fim — não perdemos precisão real porque a quota está
  /// em bytes e nunca chega perto de 2^53.
  Future<int> totalBytes() async {
    final expr =
        (cachedRegions.fileSizeBytes + cachedRegions.tilesBytes).total();
    final row =
        await (selectOnly(cachedRegions)..addColumns([expr])).getSingleOrNull();
    final value = row?.read(expr) ?? 0.0;
    return value.toInt();
  }

  /// Lista de "candidatos a serem eliminados", em ordem de "fracos"
  /// primeiro:
  ///   1º critério: `accessCount ASC` — o menos usado sai primeiro.
  ///   2º critério: `lastAccessAt ASC` — em empate, o mais antigo sai.
  ///
  /// Retorna TODOS. Quem chama itera até liberar espaço suficiente.
  Future<List<CachedRegionRow>> evictionCandidates() {
    return (select(cachedRegions)
          ..orderBy([
            (r) => OrderingTerm(
                expression: r.accessCount, mode: OrderingMode.asc),
            (r) => OrderingTerm(
                expression: r.lastAccessAt, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Linhas com `lastAccessAt` mais antigo que [cutoff]. Usado no prune
  /// de expirados chamado no boot do app.
  Future<List<CachedRegionRow>> findExpired(DateTime cutoff) {
    return (select(cachedRegions)
          ..where((r) => r.lastAccessAt.isSmallerThanValue(cutoff)))
        .get();
  }

  /// Delete puro por PK. Retorna nº de linhas afetadas (0 ou 1).
  Future<int> deleteById(int id) {
    return (delete(cachedRegions)..where((r) => r.id.equals(id))).go();
  }
}

/// Abre o arquivo SQLite. É `LazyDatabase` porque:
///
///   - Ela permite código assíncrono na fábrica (o `getApplicationDocumentsDirectory`
///     de dentro de `databaseFile()` é async).
///   - Só abre de verdade no primeiro `select`/`insert`. Se o app boota e
///     nunca usa o cache (improvável, mas possível), zero I/O.
///
/// `NativeDatabase.createInBackground` roda o SQLite num isolate separado,
/// evitando bloquear a UI durante queries pesadas.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await CachePaths.databaseFile();
    return NativeDatabase.createInBackground(file);
  });
}
