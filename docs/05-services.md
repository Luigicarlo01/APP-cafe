# 05 — Services

Todos os services fora da pasta `cache/` (essa tem
[documento próprio](06-cache-offline.md)).

Todos são singletons via factory constructor.

---

## `AnalysisService` ⭐

`services/analysis_service.dart` — **684 linhas. O centro de gravidade
do app.**

Responde a uma pergunta: *"o usuário selecionou um lat/lon, quais dados
agronômicos mostrar?"*

O arquivo contém quatro coisas: a classe `GridCell`, a exceção
`NoDataException`, o serviço em si, e a função de parse que roda em
isolate.

---

### `GridCell`

Uma célula do grid — um quadrado de 1 km² com uma recomendação.

```dart
class GridCell {
  final List<Offset> points;      // polígono fechado, dx=lng dy=lat
  final String? winner;
  final List<String> alternatives;
}
```

#### `centroid` — lazy e cacheado

```dart
Offset? _centroidCache;
Offset get centroid {
  if (_centroidCache != null) return _centroidCache!;
  // média aritmética de todos os pontos
  _centroidCache = Offset(sumLng / points.length, sumLat / points.length);
  return _centroidCache!;
}
```

Várias camadas da UI pedem o centroide (índice espacial, realce,
`nearestCell`); recalcular a cada chamada seria O(n) vezes o número de
chamadas.

É a média dos vértices, não o centroide geométrico ponderado por área.
Para quadrados regulares de 1 km, é a mesma coisa.

#### `containsPoint(Offset)` — ray casting

Mesmo algoritmo de `MapControllerLogic._isPointInPolygon`, adaptado à
convenção `Offset`.

---

### `NoDataException`

```dart
class NoDataException implements Exception {
  final String message;
  NoDataException(this.message);
  @override String toString() => message;
}
```

Semanticamente distinta de erro de rede. A UI trata cada caso
separadamente — a `MapScreen` inclusive inspeciona a mensagem para
escolher o diálogo, ver [doc 03](03-telas.md).

---

### Estado público do serviço

| Campo | Conteúdo |
|-------|----------|
| `cells` | `List<GridCell>` — todas as células da região carregada |
| `municipio` | chave ASCII, ex. `"VICOSA_2026"` |
| `displayName` | nome IBGE com acentos, ex. `"Viçosa"`. Pode ser `null` (backend antigo ou cache gravado antes da feature) |
| `winners` | vencedores da região inteira (getter sobre `_winners`) |
| `points` | legado, populado só pelo `buildPoints` deprecado |

---

### `polygonsFor(double opacity)` — cache de repaint

O `PolygonLayer` do `flutter_map` espera uma `List<Polygon>`. Recomputar
essa lista a cada frame enquanto o usuário arrasta o slider de opacidade
seria caro — milhares de polígonos, alocação nova a cada vez.

```dart
List<Polygon> _cachedPolygons = [];
double _lastOpacity = -1;

List<Polygon> polygonsFor(double opacity) {
  if (_cachedPolygons.isNotEmpty && (_lastOpacity - opacity).abs() < 0.001) {
    return _cachedPolygons;   // mesma referência → Flutter reusa o render
  }
  const base = AppColors.green;
  _cachedPolygons = cells.map((cell) => Polygon(
        points: cell.points.map((o) => LatLng(o.dy, o.dx)).toList(),
        color: base.withOpacity(opacity),
        borderColor: base,
        borderStrokeWidth: 0.3,
      )).toList();
  _lastOpacity = opacity;
  return _cachedPolygons;
}
```

A comparação de `double` usa margem de 0.001 porque floats fazem drift.

Desde o mapa monocromático a cor deixou de ser input: **todas** as
células usam `AppColors.green`. Sobrou só a opacidade.

---

### O índice espacial

**Problema**: `cellContaining(point)` é chamado a cada toque do usuário
no mapa. Iterar 10 mil células testando `containsPoint` é O(n·m) e
trava a UI.

**Solução**: grade de buckets de 0,01° (~1 km no equador).

```dart
static const double _gridStep = 0.01;
final Map<String, List<GridCell>> _spatialGrid = {};

String _spatialKey(double lng, double lat) {
  final col = (lng / _gridStep).floor();
  final row = (lat / _gridStep).floor();
  return '$col:$row';    // ex. "-4283:-1875"
}
```

`_buildSpatialIndex()` roda uma vez por carga, indexando cada célula
pelo bucket do seu **centroide**.

`cellContaining` consulta o bucket do ponto **mais os 8 vizinhos** (3×3
centrado no ponto), o que cobre células que atravessam a borda do
bucket. O custo vira praticamente constante.

**⚠** Como a indexação usa só o centroide, uma célula cujo polígono se
estenda por mais de um bucket pode não ser encontrada a partir de sua
borda. É exatamente um dos motivos pelos quais `resolveCell` existe.

---

### `nearestCell(Offset, {bool requireWinner})`

Varredura linear sobre todas as células comparando distância euclidiana
**ao quadrado** entre centroides — sem `sqrt`, que é caro e não muda a
ordem.

Ao contrário de `cellContaining`, não depende de point-in-polygon:
sempre devolve alguma célula, desde que o grid não esteja vazio. É a
rede de segurança.

`requireWinner: true` ignora células sem recomendação, garantindo que a
tela abra mostrando um cultivar de verdade.

---

### `resolveCell` — o ponto central

**A forma canônica de transformar um ponto geográfico em célula.**

```dart
GridCell? resolveCell(Offset point) {
  if (cells.isEmpty) return null;
  return cellContaining(point) ??
      nearestCell(point, requireWinner: true) ??
      nearestCell(point);
}
```

Três tentativas em cascata. Devolve `null` apenas se não houver célula
nenhuma carregada.

**Por que o fallback existe.** `cellContaining` falha em vários casos
legítimos:

- ponto numa fresta entre células;
- ponto dentro do município mas fora do grid analisado;
- célula maior que o bucket do índice espacial;
- ponto exatamente sobre uma aresta.

Quando falhava, a tela de análise abria sem nada selecionado e pedia ao
usuário que escolhesse um cultivar — ignorando o ponto que ele acabara
de confirmar no mapa.

Os dois consumidores (`AnalysisController` e `GenotypePlot`) usam
`resolveCell`, o que garante que o realce no mapa e a lista de
cultivares nunca discordem.

---

### `load({required double lat, required double lng})`

O método mais importante do app. Seis etapas:

```
_reset()                                  zera tudo da análise anterior
  │
  ├─ 1. RegionCacheService().get(lat, lon)
  │       hit? → _loadFromCache() → return       ZERO REDE
  │
  ├─ 1.5. AppMode().isOffline?
  │       sim → throw NoDataException('Sem sinal e sem dados salvos…')
  │
  ├─ 2. POST /api/analysis/municipio
  │       → municipio, display_name, winners, bbox
  │
  ├─ 3. GET /api/grid/<municipio>          streaming, timeout 180 s
  │
  ├─ 4. compute(_parseCellsIsolate, json)  ISOLATE
  │       cells vazio? → throw NoDataException
  │       _buildSpatialIndex()
  │
  └─ 5. RegionCacheService().put(...)      em try/catch
```

Pontos que valem destacar:

**O guard-rail offline (1.5)** economiza 15 segundos de espera. Sem ele,
o app tentaria o `http.post` e só descobriria a falta de rede no
timeout.

**O bbox tem duas fontes.** Prefere-se o do backend (envelope oficial do
polígono IBGE); o parser calcula um de graça no mesmo laço, como
fallback para backend antigo. O envelope das células não é igual ao do
município, então o do backend é mais preciso.

**Falha ao gravar no cache não quebra a análise.** É `try/catch` com
`debugPrint`; a UI já vai renderizar o que está em memória.

---

### `_loadFromCache(CachedRegion)`

Caminho do cache hit. Lê `municipio`, `winners` e `display_name` do
`metadata` já parseado, depois:

```dart
final jsonString = await File(cached.filePath).readAsString();
final parsed = await compute(_parseCellsIsolate, jsonString);
```

`readAsString` é async e o SDK faz o I/O em thread nativa — mas o parse
do JSON pesado ainda seria na thread principal, daí o `compute`
igualmente aqui.

---

### Os dois helpers HTTP

#### `_fetchMunicipioMeta(lat, lng)`

`POST` com timeout de 15 s. Trata `404` como `NoDataException` (mensagem
amigável) e qualquer outro status não-200 como `Exception` genérica.

```dart
return jsonDecode(utf8.decode(metaResp.bodyBytes)) as Map<String, dynamic>;
```

Usa `bodyBytes` + `utf8.decode` explicitamente porque `response.body` do
pacote `http` assume ISO-8859-1 na ausência de charset no header — o que
quebraria "São Paulo", "Viçosa" e afins.

#### `_downloadGeoJson(mun)`

`http.Request` + `client.send` (streaming) com timeout de **180 s**,
folgado porque alguns municípios geram arquivos de vários MB.

```dart
final client = http.Client();
try {
  ...
  final bytes = <int>[];
  await for (final chunk in streamed.stream) { bytes.addAll(chunk); }
  return utf8.decode(bytes);
} finally {
  client.close();
}
```

Client dedicado fechado no `finally` para não vazar conexão. Acumula os
bytes crus e decodifica de uma vez — decode incremental seria mais
eficiente em memória mas exigiria parser streaming.

---

### `_parseCellsIsolate(String)` — função top-level

Fora de qualquer classe, porque `compute` serializa a função para
enviá-la ao isolate e métodos de instância carregam o `this`.

Para cada feature, três guard-rails antes de aceitar:

```dart
if (geometry == null) continue;
if (properties['type'] != 'grid') continue;      // descarta a feature do município
if (geometry['type'] != 'Polygon') continue;
```

O terceiro filtro é essencial: o GeoJSON gerado pelo R contém uma
feature `type: "municipio"` (o contorno) além das milhares de
`type: "grid"`.

Lê `coordinates[0]` (o anel externo; grid não tem buracos), monta os
`Offset(lng, lat)` e, no mesmo laço, acumula min/max de lat e lon para o
bbox de fallback.

`alternatives` é lido de forma tolerante:

```dart
final alternatives = rawAlts is List
    ? rawAlts.map((e) => e?.toString() ?? 'N/A').toList()
    : <String>[];
```

Devolve `_ParseResult(cells, bbox)` — classe privada porque `compute`
passa um argumento e devolve um valor.

---

## `ApiConfig` ⚠

`services/api_config.dart` — 20 linhas. **O arquivo mais problemático do
repositório.**

```dart
String get kBaseUrl {
  if (Platform.isAndroid) {
    // porta IP atual é hotspot de pc da ufv, mudar sempre que for usar assim
    return 'http://192.168.3.4:5000';
  }
  return 'http://127.0.0.1:5000';
}

String get googleMapsApiKey {
  return 'AIza…';   // literal no código-fonte
}
```

Três problemas, todos tratados no [doc 12](12-producao-remover-hardcode.md):

1. IP de LAN fixo, que muda a cada rede.
2. HTTP em texto claro.
3. Chave da Google Maps Platform literal e **versionada no git**.

Também expõe `apiKey` como alias `@Deprecated` de `googleMapsApiKey`.

Consumidores: `analysis_service.dart` (2 usos de `kBaseUrl`),
`google_places_service.dart` (3 usos da chave),
`google_geocoding_service.dart` (1 uso, arquivo deprecado).

---

## `bootstrapApp()`

`services/app_bootstrap.dart` — 69 linhas. Função top-level, não classe.

Vive em arquivo próprio (e não no `main.dart`) para evitar o import
circular `main → splash → main`.

A ordem dos quatro passos é intencional:

```dart
await MgShapeService().load();        // 1. assets → a MapScreen desenha no 1º frame
await CultivarInfoService().load();   // 2. assets → o card da análise lê direto
await AppMode().init();               // 3. rede   → evita flicker do badge
try {                                 // 4. disco  → não pode travar o boot
  await RegionCacheService().pruneExpired();
  await RegionCacheService().debugDump();
} catch (e) {
  debugPrint('Falha ao inicializar cache: $e');
}
```

Os passos 1 e 2 são bloqueantes porque a primeira tela os consome
imediatamente. O 3 é bloqueante para que o primeiro build já tenha o
estado correto — senão a tela renderiza "online" e pisca para "offline"
um frame depois. O 4 está em `try/catch` porque corrupção de banco ou
permissão de disco não deveria impedir o app de abrir.

**⚠** O `debugDump()` roda em release também. O comentário no próprio
arquivo sugere envolvê-lo em `if (kDebugMode)` — ver doc 12.

---

## `AppMode`

`services/app_mode.dart` — 139 linhas. Singleton `ChangeNotifier`.

Fica no meio-campo entre o SO (que sabe o estado da rede) e a lógica de
negócio (que decide se chama o backend).

```dart
bool _isOnline = true;   // assume online até o SO dizer o contrário
bool get isOnline => _isOnline;
bool get isOffline => !_isOnline;   // açúcar: lê melhor em ifs
```

O default `true` é deliberado: se o plugin falhar, é melhor tentar a
rede e falhar naturalmente do que travar tudo em offline sem razão.

### `init()`

```dart
try {
  _apply(await _connectivity.checkConnectivity());   // leitura inicial
} catch (e) { debugPrint(...); }

_subscription?.cancel();    // evita duplo listener em hot restart
_subscription = _connectivity.onConnectivityChanged.listen(_apply);
```

### `_apply(List<ConnectivityResult>)`

Recebe **lista** porque versões recentes do plugin reportam múltiplos
tipos simultâneos (`[wifi, ethernet]`).

```dart
final online = results.any((r) => r != ConnectivityResult.none) &&
    results.isNotEmpty;
if (online == _isOnline) return;    // early return: não notifica à toa
_isOnline = online;
notifyListeners();
```

### `forceCheck()`

Releitura manual, útil se o app volta do background e o stream perdeu
evento. Não é chamado hoje.

### Consumidores

- `MapScreen`: badge, esconde a busca, mostra o atalho do histórico,
  limita o zoom.
- `GenotypePlot`: `maxNativeZoom` 10 vs 18.
- `AnalysisService`: guard-rail antes do HTTP.
- `HistoryScreen`: texto do cabeçalho e selo "disponível offline".

### ⚠ Limitação

`connectivity_plus` reporta interface de rede ativa, não internet real.
Wi-Fi conectado a roteador sem uplink é lido como online. O comentário
no arquivo sugere, se virar problema em campo, um ping ao `kBaseUrl`
como validação extra.

---

## `MgShapeService`

`services/mg_shape_service.dart` — 24 linhas. O mais simples do
projeto.

```dart
List<LatLng> shape = [];

Future<void> load() async {
  if (shape.isNotEmpty) return;                 // idempotente
  final data = await rootBundle.loadString('assets/mg.geojson');
  final coordinates = jsonDecode(data)['features'][0]['geometry']['coordinates'][0];
  shape = coordinates.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
}
```

Lê o **primeiro anel do primeiro feature** — assume que `mg.geojson` tem
um único polígono simples.

Consumidor: `MapControllerLogic.isValidPoint`.

**⚠** O `MapWidget` faz exatamente a mesma leitura por conta própria,
em `_loadMask()`, em vez de usar este serviço. Duplicação registrada no
doc 12.

---

## `LocationService`

`services/location_service.dart` — 23 linhas. Wrapper fino sobre o
`geolocator`.

```dart
Future<LatLng?> getCurrentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) return null;
  final position = await Geolocator.getCurrentPosition();
  return LatLng(position.latitude, position.longitude);
}
```

Devolve `null` em todos os caminhos de falha — não lança. O chamador
(`MapControllerLogic.goToCurrentLocation`) simplesmente não faz nada.

**⚠** Silêncio total: o usuário que negou a permissão toca no FAB e nada
acontece, sem explicação. Ver doc 12.

**⚠** O `Info.plist` do iOS não declara
`NSLocationWhenInUseUsageDescription`, o que faz o `geolocator` falhar
naquela plataforma. Ver [doc 11](11-plataformas-build.md).

---

## `CropCycleService`

`services/crop_cycle_service.dart` — 30 linhas. Singleton
`ChangeNotifier`.

```dart
enum CropCycle {
  curto, medio, longo;
  String get label { ... }   // 'Curto' | 'Médio' | 'Longo'
}

CropCycle _cycle = CropCycle.medio;   // default
void setCycle(CropCycle novo) {
  if (novo == _cycle) return;
  _cycle = novo;
  notifyListeners();
}
```

**⚠ O valor é lido por ninguém além do próprio seletor.** O
`CycleSelectionPicker` mostra e altera o ciclo, mas nem o
`AnalysisService` nem o backend recebem esse parâmetro — a recomendação
retornada é a mesma independentemente do ciclo escolhido. A interface
diz "A recomendação de cultivares leva essa preferência em conta" (texto
do tutorial), o que hoje não é verdade.

Isso é uma inconsistência entre interface e comportamento, não um bug de
código. Está no doc 12 como item de produto.

Note ainda que o valor não é persistido: volta para `medio` a cada boot.

---

## `CultivarInfoService`

`services/cultivar_info_service.dart` — 248 linhas.

Lê `assets/cultivares.json` (40 cultivares) e responde às duas perguntas
que o card da análise faz:

1. Este cultivar resiste a ferrugem e a nematóide?
2. Quanto ele produziu, de preferência **aqui**?

### Por que asset e não endpoint

É dado de referência: muda quando sai boletim novo, não a cada consulta.
Como asset funciona offline — que é metade do propósito do app — e não
depende do Flask. O preço é que atualizar exige republicar o app.

O arquivo é gerado por `tools/gerar_cultivares_json.py` a partir de
`Data/data_coffee_ciclo.xlsx`.

### Estrutura do JSON

```json
{
  "_fonte": "...", "_gerado_em": "...", "_gerado_por": "...",
  "cultivares": {
    "catigua mg2": {
      "nome": "Catiguá MG2",
      "maturacao": "Intermediário",
      "ferrugem": "Resistente",
      "nematoide": "Suscetível",
      "nematoideDetalhe": null,
      "produtividade": {
        "estado":     { "ano": 2025, "media": 35.5, "registros": 62 },
        "municipios": { "ARAGUARI": { "ano": 2019, "media": 47.7, "registros": 1 }, ... }
      }
    }
  }
}
```

### `ProdutividadeInfo`

```dart
final int ano;
final double media;        // sacas por hectare
final int registros;       // quantas medições entraram na média
final bool doMunicipio;    // true = ensaio local, false = média estadual
String get mediaFormatada => media.toStringAsFixed(1).replaceAll('.', ',');
```

`ano` e `registros` **não são decoração**: a mesma cultivar pode ter 58
medições de 2025 em MG e uma única de 2019 num município. Mostrar só o
número transformaria uma medição solta numa promessa.

### `CultivarInfo.produtividade({String? municipio})`

Ordem de preferência: ensaio naquele município → média estadual →
`null`. O `doMunicipio` do resultado diz qual dos dois saiu, para a UI
escrever "em Patrocínio" ou "em Minas Gerais" — dizer "na sua região"
quando o número é estadual seria mentira.

`produtividadeEstadual()` devolve a estadual independentemente, e o card
a usa como linha de comparação quando a amostra municipal é mínima.

### Normalização de nomes — a parte delicada

O backend chama a cultivar de `"Bourbon Ama. IAC J10"`; a planilha, de
`"Bourbon Amarelo IAC J10"`. Em vez de uma tabela de-para que alguém
teria de manter, os dois lados passam pela mesma normalização:

```dart
static String chaveCultivar(String nome) {
  var s = _semAcento(nome).toLowerCase();
  s = s.replaceAll('ama.', 'amarelo')       // abreviações ANTES
       .replaceAll('verm.', 'vermelho')     // de tirar a pontuação
       .replaceAll('v.', 'vermelho');
  return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

static String chaveMunicipio(String municipio) {
  final semAno = municipio.replaceAll(RegExp(r'_\d{4}$'), '');
  return _semAcento(semAno).toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
```

`_semAcento` é uma tabela manual de 50 caracteres — Dart não tem
`unicodedata`.

> **A regra vive em dois lugares**: aqui e em
> `tools/gerar_cultivares_json.py`. Se mudar de um lado e não do outro,
> as buscas passam a falhar **em silêncio** e o card fica vazio sem erro
> nenhum. Está anotado nos cabeçalhos dos dois arquivos.

#### Verificação: as duas implementações batem hoje ✅

As duas foram executadas lado a lado sobre os **40 nomes reais** de
`cultivares.json`: **zero divergências**. Também conferem nas
abreviações (`"Bourbon Ama. IAC J10"` → `bourbon amarelo iac j10` nos
dois) e na ordem em que as substituições são aplicadas — Python usa um
`dict` (ordem de inserção: `ama.`, `verm.`, `v.`) e o Dart encadeia
`replaceAll` na mesma sequência.

Onde elas **divergiriam**, se um nome assim aparecesse: o Python usa
`unicodedata.normalize("NFKD")` + `encode("ascii","ignore")`, que faz
decomposição **de compatibilidade** e expande caracteres que a tabela
manual do Dart não conhece. O Dart deixa passar o caractere, e o regex
`[^a-z0-9]+` depois o transforma em espaço:

| Entrada | Python | Dart |
|---------|--------|------|
| `Café ½ Bourbon` | `cafe 12 bourbon` | `cafe bourbon` |
| `Arara º2` | `arara o2` | `arara 2` |

Ou seja: frações, ordinais, ligaduras e símbolos fora do alfabeto
latino acentuado. Nenhum aparece nos nomes atuais, e é improvável que
apareçam — mas é exatamente aí que a falha silenciosa nasceria.

#### ⚠ Achado real: 5 municípios da planilha não existem no GeoJSON

A comparação empírica encontrou um problema **diferente** do previsto.
Das **47** chaves de município presentes em `cultivares.json`, **5 não
correspondem a nenhum dos 853 arquivos** de `Data/geoJson/2026/`:

| Chave no JSON | Causa provável |
|---------------|----------------|
| `FRANCISCO_DRUMOND` | erro de digitação na planilha — o município é **Francisco Dumont** |
| `IBIA_ARAXA` | duas cidades numa célula só (`Ibiá/Araxá`) |
| `IBIA_SAO_GOTARDO` | idem (`Ibiá/São Gotardo`) |
| `SAO_SEBASTIAO_DA_GRAMA` | município de **São Paulo**, fora da cobertura de MG |
| `SEBASTIAO_GOMES_DO_PRADO` | não é município — provavelmente distrito ou localidade |

**Efeito**: como o `municipio` que chega ao card vem sempre do backend
(e o backend só devolve stems de municípios de MG que têm GeoJSON),
essas chaves **nunca são consultadas**. São **72 registros de
produtividade** que existem no asset e jamais aparecem na tela — o card
cai silenciosamente na média estadual.

Não é bug de código: é higiene da planilha. A correção é em
`Data/data_coffee_ciclo.xlsx`, e o script poderia avisar — ver
[doc 12](12-producao-remover-hardcode.md).

### `load()` — degradação graciosa

```dart
try {
  ...
} catch (e) {
  debugPrint('CultivarInfo: falha ao ler assets/cultivares.json ($e)');
  _porChave = {};
}
_carregado = true;
```

Asset corrompido não derruba o app: o card degrada para "sem dados de
referência" e o resto da análise continua funcionando.

`infoFor(nome)` devolve `null` se o cultivar não está na planilha, e
aceita o nome em qualquer das duas grafias.

---

## `GooglePlacesService`

`services/google_places_service.dart` — 209 linhas.

Usa a **Places API (New)**, que tem contrato bem diferente da API
clássica:

| Operação | Método | URL |
|----------|--------|-----|
| Autocomplete | POST | `https://places.googleapis.com/v1/places:autocomplete` |
| Place Details | GET | `https://places.googleapis.com/v1/places/{placeId}` |
| Forward Geocode | GET | `https://maps.googleapis.com/maps/api/geocode/json` |

Requer, no Google Cloud Console: **Places API (New)** habilitada, e
**Geocoding API** se `forwardGeocode` for usado.

### Session token

```dart
String? _sessionToken;
void startNewSession() { _sessionToken = DateTime.now().microsecondsSinceEpoch.toString(); }
void endSession() { _sessionToken = null; }
```

O Google cobra Autocomplete + Details como **uma** sessão quando o mesmo
token acompanha as várias digitações e a seleção final. Sem token, cada
digitação é cobrada separadamente.

O token é criado preguiçosamente em `searchCity` (`_sessionToken ??=
...`) e encerrado em `getPlaceDetails` após sucesso, e também quando o
usuário limpa o campo (`CitySearchController`).

**⚠** `startNewSession()` não é chamado por ninguém — a criação lazy
cobre o caso. O método fica como API pública ociosa.

### `searchCity(String query)`

Body do POST:

```dart
{
  'input': query,
  'languageCode': 'pt-BR',
  'regionCode': 'br',
  'includedRegionCodes': ['br'],
  'sessionToken': _sessionToken,
}
```

Autenticação por header `X-Goog-Api-Key` (não por query param, como na
API clássica).

O parse navega uma estrutura aninhada e monta o rótulo:

```dart
final label = (main != null && secondary != null)
    ? '$main, $secondary'          // "Viçosa, Minas Gerais, Brasil"
    : (text ?? main ?? '');
```

Devolve no máximo 5 itens `{name, place_id}`. Em erro HTTP ou exceção,
faz `debugPrint` e devolve lista vazia — nunca lança.

### `getPlaceDetails(String placeId)`

```dart
headers: {
  'X-Goog-Api-Key': googleMapsApiKey,
  'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
}
```

O **FieldMask é obrigatório** na Places API (New) — sem ele a requisição
falha. Ele também controla o custo: quanto menos campos, mais barata a
chamada.

Devolve `{name, lat, lon}`, compatível com o formato que
`MapControllerLogic.onCitySelected` espera, preferindo
`formattedAddress` a `displayName`.

### `forwardGeocode(String address)`

Endereço em texto → coordenadas, via Geocoding API (endpoint separado,
autenticação por query param `key`). Filtra `components: 'country:BR'`.

**⚠** Não é chamado por ninguém. Existe como fallback documentado.

---

## Services desativados

Detalhes em [doc 13](13-codigo-desativado.md).

| Arquivo | Estado |
|---------|--------|
| `google_geocoding_service.dart` | `@Deprecated` — reverse geocoding (coordenada → endereço) não é mais consumido |
| `location_search_service.dart` | `@Deprecated` — busca via Nominatim, substituída pelo Google Places |

---

## `OnboardingService`

`services/onboarding_service.dart` — 152 linhas. Documentado junto com o
overlay em [07 — widgets](07-widgets.md), porque
os dois só fazem sentido juntos.
