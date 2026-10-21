# 06 — Cache offline

O subsistema que permite ao app funcionar sem internet. Oito arquivos em
`front_end/lib/services/cache/`, ~2.900 linhas incluindo o código gerado
pelo Drift.

---

## Visão geral: dois caches independentes

Este é o ponto que mais confunde quem chega no código. São **duas coisas
separadas**, com regras diferentes:

| | Cache de regiões | Mapa base |
|---|---|---|
| **O que guarda** | GeoJSON de análise por município | tiles PNG do CARTO cobrindo MG |
| **Onde** | `<AppDocs>/region_cache/<id>.geojson` + SQLite | `<AppDocs>/base_map/z/x/y.png` |
| **Quem gerencia** | `RegionCacheService` | `BaseMapService` |
| **Como enche** | automático, a cada análise | manual, botão na AppBar |
| **Quota** | 600 MB | nenhuma |
| **TTL** | 30 dias sem acesso | nenhum |
| **Eviction** | sim, menos acessado primeiro | nunca |
| **Como esvazia** | prune no boot, eviction por quota | só `delete()` explícito |

A separação é deliberada: o mapa base é **infraestrutura curada**. Se
participasse da quota, uma eviction poderia apagá-lo num momento ruim e
quebrar o modo offline justamente quando ele importa.

```
                   AnalysisService.load(lat, lng)
                             │
                   RegionCacheService.get()
                             │
                      RegionDatabase
                     (Drift / SQLite)
                             │
                   region_cache/<id>.geojson


                   GenotypePlot / MapWidget
                             │
                 CachedRegionTileProvider.getImage()
                             │
                   base_map/z/x/y.png  →  rede (CARTO)
                             ▲
                      BaseMapService.download()
                             │
                          TileMath
```

---

## `cache_paths.dart` — 161 linhas

Sem lógica de negócio: só resolve "onde na pasta do app fica cada
coisa". Todos os métodos são `static`.

### `AppDocs`, não `Temporary`

```dart
final docs = await getApplicationDocumentsDirectory();
```

Duas pastas seriam possíveis:

- `getTemporaryDirectory()` — o SO pode limpar quando quiser (falta de
  espaço, limpador em background). **Não é seguro** para cache
  persistente.
- `getApplicationDocumentsDirectory()` — persiste até o usuário
  desinstalar o app.

O app usa documents, porque o cache precisa sobreviver a reboots.

### Layout em disco

```
<AppDocs>/
├── region_cache.db                 SQLite do Drift
├── region_cache/
│   └── <id>.geojson                nome = PK autoincremento da tabela
├── base_map/
│   ├── .complete                   sentinela (contém um timestamp ISO)
│   └── <z>/<x>/<y>.png
├── region_tiles/<id>/<z>/<x>/<y>.png    LEGADO, não é mais populado
├── .onboarding_done                sentinela do tutorial da tela inicial
└── .onboarding_analysis            sentinela do tutorial da análise
```

### Métodos

| Método | Devolve |
|--------|---------|
| `regionCacheDir()` | diretório dos GeoJSON, criando se preciso |
| `regionFile(int id)` | `region_cache/<id>.geojson` |
| `databaseFile()` | `region_cache.db` |
| `baseMapDir()` | diretório do mapa base |
| `baseMapTileFile(z, x, y)` | cria `<z>/<x>/` e devolve `<y>.png` |
| `onboardingFlagFile(String flowId)` | `.onboarding_<flowId>` |
| `regionTilesDir(id)` / `tileFile(...)` | legado, ver abaixo |

O nome do arquivo de região ser o **id autoincremento** garante
unicidade sem precisar sanitizar nomes de município.

A estrutura de pastas por zoom e por x do mapa base existe para não
estourar o limite de arquivos por diretório de sistemas de arquivos
antigos (alguns limitam em ~10 mil).

Os métodos de `region_tiles` são preservados só para que
`RegionCacheService._deleteRow` consiga apagar pastas órfãs de testes
anteriores.

---

## `region_database.dart` — 321 linhas

A camada Drift. Contém a definição da tabela, a classe de queries e a
abertura da conexão.

> `region_database.g.dart` (1.219 linhas) é **gerado** por
> `dart run build_runner build --delete-conflicting-outputs`.
> **Nunca edite à mão.**

### A tabela `CachedRegions`

```dart
@DataClassName('CachedRegionRow')
class CachedRegions extends Table { ... }
```

A anotação renomeia a data class gerada para `CachedRegionRow`, evitando
colisão com `CachedRegion`, o modelo público do service.

| Coluna | Tipo | Papel |
|--------|------|-------|
| `id` | `integer().autoIncrement()` | PK, e nome do arquivo em disco |
| `municipio` | `text(min:1, max:200)` | chave ASCII, ex. `VICOSA_2026` |
| `minLat` `maxLat` `minLon` `maxLon` | `real()` | **a chave espacial** |
| `filePath` | `text()` | caminho absoluto do `.geojson` |
| `fileSizeBytes` | `integer()` | tamanho, para a quota |
| `createdAt` | `dateTime()` | primeira vez que baixou |
| `lastAccessAt` | `dateTime()` | atualizado a cada hit — **é a coluna do TTL** |
| `accessCount` | `integer().withDefault(0)` | ordena a eviction |
| `metadata` | `text().nullable()` | JSON livre |
| `tilesBytes` | `integer().withDefault(0)` | legado, sempre 0 |
| `tilesMaxZoom` | `integer().nullable()` | legado, sempre null |

Guardar `filePath` (e não só derivar do `id`) permite mover a pasta no
futuro sem quebrar linhas antigas — bastaria uma migration reescrevendo
o path.

O `metadata` como JSON livre, em vez de tabela filha, é escolha
consciente: torna o cache genérico. Se o backend adicionar campos, o
cliente não precisa de migração. Hoje guarda `winners` e `display_name`.

### Migrations

```dart
@override int get schemaVersion => 2;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) => m.createAll(),
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      await m.addColumn(cachedRegions, cachedRegions.tilesBytes);
      await m.addColumn(cachedRegions, cachedRegions.tilesMaxZoom);
    }
  },
);
```

Histórico: v1 = schema inicial; v2 = colunas de tiles (para o
`TileDownloader`, hoje deprecado). As colunas permanecem para evitar
uma nova migração.

**Checklist ao mexer no schema**: bumpar `schemaVersion`, escrever a
migration, rodar o `build_runner`.

### Singleton com construtor privado

```dart
RegionDatabase._() : super(_openConnection());
static final RegionDatabase instance = RegionDatabase._();
```

O construtor privado impede que outro arquivo abra uma segunda conexão
SQLite para o mesmo arquivo. SQLite tolera múltiplas conexões, mas gera
`SQLITE_BUSY` se ambas escreverem ao mesmo tempo.

`static final` é lazy e o Dart garante a inicialização thread-safe.

### `findContaining(lat, lon)` — a query central

```sql
SELECT * FROM cached_regions
WHERE min_lat <= ? AND max_lat >= ? AND min_lon <= ? AND max_lon >= ?
ORDER BY (max_lat - min_lat) * (max_lon - min_lon) ASC
LIMIT 1
```

"Qual região cacheada contém este ponto?" — e, se mais de uma contiver
(bounding boxes de municípios vizinhos se sobrepõem), a **menor** ganha,
por ser a mais específica.

### `touch(int id)` — SQL cru por atomicidade

```dart
await customStatement(
  'UPDATE cached_regions SET last_access_at = ?, access_count = access_count + 1 WHERE id = ?',
  [now.millisecondsSinceEpoch ~/ 1000, id],
);
```

Usa SQL cru de propósito: o `+ 1` precisa acontecer no SQLite. Se fosse
"ler → incrementar → gravar" em Dart, duas chamadas concorrentes
poderiam perder um incremento.

A conversão manual para unix seconds reproduz o que o Drift faz
internamente para `DateTimeColumn`.

### `totalBytes()` — por que `total()` e não `sum()`

```dart
final expr = (cachedRegions.fileSizeBytes + cachedRegions.tilesBytes).total();
```

Em SQLite, `SUM` sobre inteiros pode devolver `INTEGER` ou `REAL`
conforme os valores (overflow vira REAL), e o Drift traduz isso de forma
que varia entre versões, causando erro de compilação `int != double`.
`TOTAL()` sempre devolve REAL. Converte-se para `int` no fim — sem perda
real, já que a quota em bytes nunca chega perto de 2⁵³.

### Demais queries

| Método | Uso |
|--------|-----|
| `findById(id)` | lookup por PK |
| `evictionCandidates()` | todas as linhas, `accessCount ASC`, desempate por `lastAccessAt ASC` |
| `findExpired(cutoff)` | linhas com `lastAccessAt` anterior ao corte |
| `deleteById(id)` | delete puro |
| `updateTilesInfo(...)` | legado |

### Conexão

```dart
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await CachePaths.databaseFile();
    return NativeDatabase.createInBackground(file);
  });
}
```

`LazyDatabase` permite código assíncrono na fábrica (o
`getApplicationDocumentsDirectory` é async) e só abre de verdade na
primeira query. `createInBackground` roda o SQLite em isolate separado.

---

## `region_cache_service.dart` — 451 linhas ⭐

A camada de negócio sobre o `RegionDatabase`.

> **Regra de ouro declarada no arquivo**: fora daqui, ninguém deveria
> mexer no `RegionDatabase` diretamente. (A `HistoryScreen` viola — ver
> doc 12.)

### `CachedRegion` — o modelo público

Diferente de `CachedRegionRow` (a data class do Drift): traz o
`BoundingBox` já materializado como objeto e o `metadata` já parseado
como `Map`.

```dart
int get totalBytes => fileSizeBytes + tilesBytes;
```

### As duas constantes

```dart
static const int maxBytes = 600 * 1024 * 1024;   // 600 MB
static const Duration ttl = Duration(days: 30);
```

Mudar qualquer uma é uma linha, com efeito imediato — sem reboot.

### `get(lat, lon)` — quatro saídas

```dart
final row = await _db.findContaining(lat, lon);
if (row == null) return null;                          // 1. miss normal

if (DateTime.now().difference(row.lastAccessAt) > ttl) {
  await _deleteRow(row);
  return null;                                          // 2. expirou
}

final file = File(row.filePath);
if (!await file.exists()) {
  await _deleteRow(row);
  return null;                                          // 3. linha órfã
}

await _db.touch(row.id);
return _toModel(row);                                   // 4. HIT
```

O caso 3 é a consistência disco ↔ banco: se o usuário limpou os dados do
app ou houve corrupção, a linha aponta para arquivo inexistente. Limpa e
trata como miss.

### `put({municipio, bbox, geoJson, metadata})`

Duas escritas coordenadas, porque o nome do arquivo depende do id:

```dart
final bytes = utf8.encode(geoJson);
await _ensureSpace(bytes.length);          // libera espaço ANTES

final id = await _db.into(_db.cachedRegions).insert(
  CachedRegionsCompanion.insert(..., filePath: '', ...),   // path vazio!
);

final file = await CachePaths.regionFile(id);
await file.writeAsBytes(bytes, flush: true);

await (_db.update(_db.cachedRegions)..where((r) => r.id.equals(id)))
    .write(CachedRegionsCompanion(filePath: drift.Value(file.path)));
```

`flush: true` força o SO a gravar antes de continuar — evita perder o
arquivo se o app morrer logo em seguida.

Se algo falhar no meio, a linha fica "meio pronta"; o próximo `get()`
detecta (arquivo não existe) e limpa. É a razão de o caso 3 acima
existir.

`_ensureSpace` roda **antes** de gravar, para não deixar estado
inconsistente se falhar.

### `_ensureSpace(int newSize)` — a eviction

```dart
var total = await _db.totalBytes();
if (total + newSize <= maxBytes) return;

final candidates = await _db.evictionCandidates();   // menos usados primeiro
for (final row in candidates) {
  if (total + newSize <= maxBytes) break;
  total -= (row.fileSizeBytes + row.tilesBytes);     // atualiza local
  await _deleteRow(row);
}
```

O `total` é decrementado localmente para não re-consultar o banco depois
de cada delete — O(n) queries viram O(1).

Se no fim ainda não couber (`newSize` maior que a quota inteira), o app
tenta gravar mesmo assim. A próxima gravação estoura e recai aqui.

A política é **LFU com desempate por LRU**: `accessCount ASC`, depois
`lastAccessAt ASC`. Uma região muito consultada nunca é sacrificada a
menos que seja o único caminho.

### `pruneExpired()`

Chamado no boot. Apaga tudo com `lastAccessAt` fora do TTL.

Existe apesar de `get()` já apagar expirados on-demand, porque linhas
que ninguém consulta ficariam ocupando disco para sempre: o usuário
estuda 50 municípios, larga o app 40 dias, todas expiram mas ninguém
tenta acessá-las.

### `_deleteRow(CachedRegionRow)` — a ordem importa

1. Apaga o `.geojson` (em `try/catch` — continua mesmo se falhar).
2. Apaga a pasta legada `region_tiles/<id>` recursivamente.
3. Apaga a linha do banco.

O banco por último significa que, se algo falhar no meio, a linha
**sempre** vai embora — não fica lixo apontando para arquivo morto.

### `debugDump()`

Imprime no console um quadro com linhas, ocupação, TTL e o top-10 por
`accessCount`; devolve a mesma informação como `Map`, o que serviria a
uma tela de debug ou a testes.

**⚠** Chamado no boot em release também.

### Métodos prontos mas sem chamador

- `enforceQuota()` — verificação de quota após escrita externa. Existia
  para o `TileDownloader`.
- `clear()` — reset total. Seria o "limpar cache" de uma tela de
  configurações.
- `totalBytes()` — delegator.

---

## `tile_math.dart` — 187 linhas

Matemática pura da projeção "slippy map" (OSM, CARTO, Google). Sem
estado, sem dependências além de `dart:math` e `BoundingBox`.

Cada zoom `z` divide o mundo em 2^z × 2^z tiles, numerados a partir do
canto superior esquerdo.

### Conversões

```dart
static int lonToTileX(double lon, int z) {
  final n = math.pow(2, z).toDouble();
  return ((lon + 180.0) / 360.0 * n).floor();
}

static int latToTileY(double lat, int z) {
  final n = math.pow(2, z).toDouble();
  final latRad = lat * math.pi / 180.0;
  return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi)
          / 2.0 * n).floor();
}
```

A longitude é linear; a latitude não, porque o Web Mercator distorce
latitudes altas. `1 / cos(x)` é a secante — Dart não tem `sec()`.

### `rangeFor(BoundingBox, int z)`

```dart
final yMin = latToTileY(bbox.maxLat, z);   // note a inversão
final yMax = latToTileY(bbox.minLat, z);
```

**Sutileza**: no eixo Y, o tile de menor número é o **mais ao norte**.
Então `yMin` corresponde a `maxLat`, invertido em relação à intuição.

### `TileRange`

```dart
int get count => (xMax - xMin + 1) * (yMax - yMin + 1);   // +1: limites inclusivos

Iterable<({int z, int x, int y})> iterate() sync* {
  for (var x = xMin; x <= xMax; x++)
    for (var y = yMin; y <= yMax; y++)
      yield (z: z, x: x, y: y);
}
```

`sync*` faz um generator lazy — não aloca uma lista com todos os tiles
de uma vez. O record com labels é sintaxe Dart 3.

### `estimateBytes(...)`

Estimativa grosseira somando `count × avgBytesPerTile` por zoom. Os
palpites documentados: CARTO Light ~7–8 KB por tile; OSM padrão colorido
~15–20 KB.

Usada no diálogo de confirmação ("~15 MB") e pelo `pickMaxZoom` legado.

### `pickMaxZoom(...)` — legado

Escolhe o maior `zMax` cuja pirâmide `[minZoom, zMax]` caiba numa quota,
percorrendo de cima para baixo. Não é mais chamado — fica porque é
matemática pura e não custa nada.

---

## `base_map_service.dart` — 329 linhas

Download do mapa base de MG. Singleton `ChangeNotifier`.

### Configuração

```dart
static const String _urlTemplate =
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
static const List<String> _subdomains = ['a', 'b', 'c', 'd'];
static const int _minZoom = 6;     // MG cabe em ~10 tiles
static const int _maxZoom = 10;    // dá pra distinguir municípios
static const int _maxConcurrent = 6;
static const Duration _perTileTimeout = Duration(seconds: 6);
static const String _sentinelFileName = '.complete';
```

O zoom 10 como teto é o equilíbrio declarado: acima disso são muitos
tiles para pouco ganho. É o mesmo 10 que aparece como `maxNativeZoom`
offline em `MapWidget` e `GenotypePlot` — **se mudar aqui, mude lá**.

Os quatro subdomínios distribuem carga e evitam rate-limit; o subdomínio
é escolhido de forma determinística por tile (`(x + y) % 4`), o que
ajuda o cache HTTP do CDN.

### Estado observável

`isDownloading`, `isDownloaded`, `progress` (0..1), `sizeBytes`,
`tileCount`.

### `refreshStatus()`

Confere o disco: existência da sentinela define `isDownloaded`; varredura
recursiva soma tamanho e conta `.png`. Chamado no `initState` da
`MapScreen`.

A sentinela é o que impede considerar completo um download interrompido.

### `download()` — idempotente e retomável

```dart
if (_isDownloading) return;    // evita dois downloads paralelos
if (_isDownloaded) return;     // já completo

for (var z = _minZoom; z <= _maxZoom; z++) {
  final coords = TileMath.rangeFor(bbox, z).iterate().toList();
  for (var i = 0; i < coords.length; i += _maxConcurrent) {
    final chunk = coords.sublist(i, math.min(i + _maxConcurrent, coords.length));
    final results = await Future.wait(
      chunk.map((c) => _fetchAndSave(client, c.z, c.x, c.y)),
      eagerError: false,        // um falhar não cancela os outros
    );
    ...
    _progress = processedTiles / expectedTotal;
    notifyListeners();          // por CHUNK, não por tile
  }
}
```

Itera do zoom baixo para o alto, de modo que o usuário vê primeiro uma
versão pobre mas navegável.

`notifyListeners()` por chunk, não por tile, para não disparar seis
rebuilds por milissegundo — a barra de progresso não precisa dessa
granularidade.

No fim, grava a sentinela `.complete` com um timestamp ISO dentro (só
para debug).

O `finally` garante três coisas mesmo em exceção: fecha o `http.Client`
(senão vaza sockets), limpa `_isDownloading` (senão a UI trava em
spinner) e leva `progress` a 1.0.

### `_fetchAndSave(client, z, x, y)`

```dart
final file = await CachePaths.baseMapTileFile(z, x, y);
if (await file.exists()) return 0;   // já baixado — a retomada acontece aqui
...
await file.writeAsBytes(resp.bodyBytes, flush: false);
```

A checagem de existência é o que torna o download retomável: um download
interrompido pula tudo que já está em disco.

`flush: false` (ao contrário do cache de região) deixa o SO agrupar o
I/O. Se o app crashar, o tile pode se perder — aceitável, porque o
downloader é idempotente.

Qualquer falha devolve 0 e o download continua: melhor terminar com
alguns buracos do que travar. É por isso que o diálogo de info oferece
"Baixar novamente".

### `delete()`

Apaga o diretório inteiro recursivamente, incluindo a sentinela. Não há
botão dedicado na UI; é acionado pelo "Baixar novamente".

---

## `cached_region_tile_provider.dart` — 226 linhas

`TileProvider` customizado do `flutter_map`. Substitui o
`NetworkTileProvider` padrão por uma estratégia cache-first.

Para cada tile visível, o `flutter_map` pergunta ao provider pela
imagem. A cascata é:

```
1. existe <AppDocs>/base_map/z/x/y.png?  → lê do disco
2. não? → baixa da rede (CARTO)          → NÃO salva
3. falha? → lança                        → flutter_map estica o tile do zoom anterior
```

**Não há cache passivo de runtime**: o que o usuário navega não é
gravado. O único cache de tiles é o mapa base pré-baixado. O comentário
no código marca onde uma linha bastaria para mudar isso (`_loadBytes`).

O nome tem "Region" por herança histórica — antes ele conhecia
`regionId` e lia pastas por região. Hoje é agnóstico.

### Duas classes

**`CachedRegionTileProvider`** mantém um `http.Client` vivo entre
chamadas (reuso de conexão TCP é essencial com centenas de tiles) e o
fecha no `dispose`. Aceita um client injetado, o que o tornaria testável.

**`_CachedTileImage extends ImageProvider<_CachedTileImage>`** — o
provider de imagem propriamente dito:

- `obtainKey` devolve `SynchronousFuture(this)`: a chave é o próprio
  objeto, e `==` / `hashCode` são customizados sobre `(z, x, y,
  urlTemplate)`. É o que permite ao Flutter deduplicar decodificações do
  mesmo tile.
- `loadImage` devolve `MultiFrameImageStreamCompleter` com `debugLabel`
  útil em profiling.
- `_loadCodec` converte bytes em `ui.Codec` via
  `ui.ImmutableBuffer.fromUint8List` (buffer read-only sem cópia).
- `_loadBytes` é a cascata disco → rede → `null`.
- `_buildUrl` substitui `{z}` `{x}` `{y}` e, se houver, `{s}` pela
  fórmula `(x + y) % subdomains.length`.

**⚠ Detalhe**: o comentário de `_buildUrl` menciona "CartoDB tem 3
subdomínios" e `% 3`, mas o código usa `subdomains.length`, que é 4 nas
chamadas reais. O comentário está desatualizado; o código está certo.

---

## `tile_downloader.dart` — 196 linhas — @Deprecated

Baixava tiles adaptativos **por região**, escolhendo o zoom máximo que
coubesse numa quota de 30 MB por região.

Desativado porque o `flutter_map` escala o tile de zoom 10 quando o
usuário passa disso — então o mapa base pré-baixado basta, e um
downloader por região seria redundância cara.

Ver [doc 13](13-codigo-desativado.md).
