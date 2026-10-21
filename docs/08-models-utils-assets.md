# 08 — Models, utils e assets

---

## `models/bounding_box.dart` — 90 linhas

Retângulo geográfico em graus decimais (WGS84). **O modelo central do
cache.**

```dart
class BoundingBox {
  final double minLat, maxLat, minLon, maxLon;
  const BoundingBox({required ...});
}
```

Todos os campos são `final` — o objeto é imutável, o que facilita
cachear, comparar e passar entre isolates sem risco de mutação por
debaixo. O construtor é `const`.

É um AABB (*axis-aligned bounding box*): os lados são paralelos aos eixos
lat/lon, sem representar curvatura da Terra. Para os tamanhos usados
(município ou estado), o erro é desprezível.

> No hemisfério sul as latitudes são negativas. MG fica aproximadamente
> entre -22,9 e -14,2 de latitude, e entre -51,0 e -39,8 de longitude.

### Usado em três lugares

1. **`RegionDatabase`** — cada linha guarda um bbox em quatro colunas.
2. **`RegionCacheService`** — a consulta por lat/lon vira "qual bbox
   contém este ponto?".
3. **`TileMath`** — calcula a grade de tiles que cobre um bbox.

### Membros

```dart
double get area => (maxLat - minLat) * (maxLon - minLon);
```

Em **graus²**, não km². Serve **exclusivamente** como desempate quando
dois bboxes contêm o mesmo ponto — o menor (mais específico) ganha. Como
é só desempate, tanto faz que 1° de latitude ≠ 1° de longitude em km: a
ordem relativa fica correta.

```dart
bool contains(double lat, double lon) =>
    lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
```

Bordas inclusivas. A query SQL do Drift faz o mesmo teste; este método
serve a validações locais.

```dart
factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
      minLat: (json['min_lat'] as num).toDouble(), ...
    );
```

O cast para `num` antes do `.toDouble()` é defensivo: alguns JSONs trazem
`int` (ex. `-20`) e queremos `double` sempre.

O formato `{min_lat, max_lat, min_lon, max_lon}` é definido pelo backend
em `analysis_route.py`.

`toJson()` existe para debug e testes; não é chamado em runtime.
`toString()` produz `BoundingBox(-20.85..-20.70, -42.95..-42.80)`.

---

## `models/genotype_point.dart` — 14 linhas — legado

```dart
class GenotypePoint {
  final Offset position;
  final String genotype;
  final List<String> alternatives;
  final Color? color;
}
```

Alimentava o `PointsPlot` — um marker por célula, colorido por genótipo.
Com o mapa monocromático, nem o plot nem a coloração são usados.

A classe **não está marcada `@Deprecated`**, mas seu único produtor
(`AnalysisService.buildPoints`) está, e seu único consumidor
(`PointsPlot`) também. Preservada porque a modelagem deve voltar quando a
camada de markers for retomada.

---

## `utils/app_colors.dart` — 31 linhas

A paleta única do app.

```dart
class AppColors {
  AppColors._();   // construtor privado: não instanciável

  static const Color green     = Color(0xFF02890A);
  static const Color greenDark = Color(0xFF013A03);
  static const Color bege      = Color(0xFFF5F0E8);
}
```

| Cor | Onde aparece |
|-----|--------------|
| `green` | AppBar, botões preenchidos, seed do `ColorScheme`, FAB, células do mapa da análise, chips de cultivar selecionados, trilho do slider |
| `greenDark` | ícone dentro do FAB, títulos, o número da produtividade, chips de "Resistente" |
| `bege` | fundo da splash e da tela "Sobre", empty state do mapa |

### Por que existe

Antes deste arquivo, os mesmos hex estavam espalhados em cerca de oito
arquivos — `0xFF02890A` aparecia em `main`, `map_screen`, `app_drawer`,
`opacity_slider`, `points_plot`… Qualquer ajuste de marca exigia caçar
string por string.

> **Regra registrada no código**: nenhum widget novo deve declarar hex de
> verde ou bege inline — importa daqui.

**⚠** A regra ainda é violada em três pontos com cores fora da paleta:
`app_drawer.dart` (deprecado) tem `Color(0xFF02890A)` literal, e
`genotype_detail_card.dart` declara o âmbar `0xFFB26A00` e o vermelho
`0xFFB3261E` inline. Os dois últimos são cores semânticas de resistência,
não da marca — mas seria coerente movê-los. Ver doc 12.

---

## `utils/genotype_color_manager.dart` — 49 linhas — @Deprecated

Dicionário "genótipo → cor" lido de `assets/colors_2026.json`.

Fora de uso: o mapa virou monocromático e a legenda por cor foi removida,
então ninguém consulta mais a paleta. O `bootstrapApp` deixou de chamar
`load()`.

Preservado porque o JSON de cores continua sendo gerado pelo R
(`color_generator.R`) e a coloração por genótipo pode voltar como camada
opcional.

Detalhe de implementação: o hex do JSON é `RRGGBBAA` (alfa no fim), não
`AARRGGBB` como o Flutter espera — `_hexToColor` faz a conversão.

---

## `utils/geojson_cache_manager.dart` — 242 linhas — órfão

Uma implementação **anterior e completa** de cache de GeoJSON: índice em
memória `municipio → CacheEntry`, TTL de 7 dias, conceito de `pinned`
(entrada que nunca expira), serialização do índice em JSON.

Foi substituída pelo `RegionCacheService` + Drift, que tem consulta
espacial por bbox (esta era chaveada por nome de município), quota em
bytes e eviction por uso.

**⚠ Não está marcado `@Deprecated` e não é importado por nenhum arquivo.**
É o único caso de código morto sem sinalização no projeto. Ver
[doc 13](13-codigo-desativado.md) e doc 12.

---

## Assets

Declarados em `pubspec.yaml` como a pasta inteira:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/
```

| Arquivo | Tamanho | Quem lê | Para quê |
|---------|---------|---------|----------|
| `esmeraldas.geojson` | **812 KB** | **ninguém** | resíduo de teste inicial — ver abaixo |
| `mg.geojson` | 129 KB | `MgShapeService.load()` **e** `MapWidget._loadMask()` | polígono de MG: validação de ponto e contorno no mapa |
| `cultivares.json` | 85 KB | `CultivarInfoService.load()` | ficha técnica de 40 cultivares |
| `logo_ufv.png` | 32 KB | **ninguém** | extração do PNG embutido na primeira versão do "SVG" da UFV. O `partner_logos.dart` anota: "pode ser apagado" |
| `logo_ufv.svg` | 21 KB | `PartnerLogos` | marca institucional |
| `logo_epamig.svg` | 13 KB | `PartnerLogos` | marca institucional (ver doc 07 sobre as correções) |
| `typica_logo.svg` | 7,2 KB | **ninguém** | versão com borda da marca |
| `typica_logo_sem_borda.svg` | 7,2 KB | splash, login, about, AppBar da `MapScreen` | a marca em uso |
| `colors_2026.json` | 424 B | ninguém (`GenotypeColorManager` deprecado) | paleta genótipo → cor |

**Total: ~1,1 MB**, dos quais **~852 KB não são lidos por nada**
(`esmeraldas.geojson` + `logo_ufv.png` + `typica_logo.svg`) — 77% do peso
de assets do APK. Ver [doc 12](12-producao-remover-hardcode.md).

### `mg.geojson` — o que tem dentro

129 KB, **1 feature**, geometria `Polygon`, **um único anel de 3.803
pontos**, com a propriedade `codarea` (código IBGE).

Isso confirma a suposição do `MgShapeService`, que lê direto
`features[0].geometry.coordinates[0]` sem tratar `MultiPolygon` nem anéis
internos: o arquivo de fato é um polígono simples. **Se ele for trocado
por uma versão `MultiPolygon` — comum em exportações que separam ilhas
fluviais — o serviço lê só a primeira parte e a validação de ponto passa
a recusar pedaços legítimos do estado.**

Os 3.803 vértices são percorridos pelo ray casting a cada toque no mapa
(`MapControllerLogic.isValidPoint`). É barato o bastante para um gesto
isolado.

### `esmeraldas.geojson` — não é um contorno, é uma análise

812 KB, **1.021 features**, geometria `MultiPolygon`, com as propriedades
`type` e `winner`.

Ou seja: é um **GeoJSON de análise** no mesmo formato que o backend
serve hoje, do município de Esmeraldas — sobra de quando os dados vinham
embarcados no app, antes do backend e do cache existirem. É o maior
arquivo de `assets/` e nenhuma linha de código o menciona.

### `colors_2026.json`

424 bytes, **12 genótipos**, no formato `#RRGGBBAA` (alfa no fim):

```json
{ "Bourbon Ama. IAC J10": "#DB8A65CC", "Catiguá MG2": "#C29830CC" }
```

Confirma o comentário do `GenotypeColorManager` sobre a ordem dos canais,
e mostra a escala do problema que motivou o mapa monocromático: 12 tons
HCL de matiz próxima, para distinguir a olho num celular sob sol.

### `cultivares.json` — estrutura

```json
{
  "_fonte": "...",
  "_gerado_em": "...",
  "_gerado_por": "tools/gerar_cultivares_json.py",
  "cultivares": {
    "<chave normalizada>": {
      "nome": "Catiguá MG2",
      "maturacao": "Intermediário",
      "ferrugem": "Resistente",
      "nematoide": "Suscetível",
      "nematoideDetalhe": null,
      "produtividade": {
        "estado": { "ano": 2025, "media": 35.5, "registros": 62 },
        "municipios": {
          "ARAGUARI": { "ano": 2019, "media": 47.7, "registros": 1 },
          "CAMPESTRE": { "ano": 2025, "media": 71.6, "registros": 4 }
        }
      }
    }
  }
}
```

A chave de cultivar é minúscula, sem acento e sem pontuação
(`"catigua mg2"`); a de município é maiúscula com underscores
(`"BONFINOPOLIS_DE_MINAS"`). As duas normalizações estão espelhadas em
`CultivarInfoService` e no script Python — ver
[05](05-services.md#cultivarinfoservice).

### Como `cultivares.json` é gerado

`tools/gerar_cultivares_json.py` (225 linhas) lê
`Data/data_coffee_ciclo.xlsx`, que tem duas abas:

| Aba | Colunas | Granularidade |
|-----|---------|---------------|
| `Informação Cultivares` | Cultivar, Maturação, Ferrugem, Nematóide | uma linha por cultivar |
| `Dados prod` | municipio, produtor, lat, lon, cultivar, maturacao, ano, bloco, prod | uma linha por medição de ensaio (sc/ha) |

Três regras que explicam o formato do JSON:

**1. "Ano mais recente", não média histórica.** Para cada escopo (o
estado e cada município), o script pega o ano mais recente em que aquela
cultivar tem medição e faz a média só daquele ano:

```python
ano = int(df["ano"].max())
do_ano = df[df["ano"] == ano]
return {"ano": ano, "media": round(float(do_ano["prod"].mean()), 1),
        "registros": int(len(do_ano))}
```

O raciocínio está no cabeçalho do script: safra velha não representa o
que o produtor vai colher. A consequência é que o ano varia entre
cultivares e entre municípios — e é por isso que o JSON carrega `ano` e
`registros`, e o card mostra os dois.

**2. O rótulo curto de resistência é extraído por prefixo.**
`resumo_resistencia()` reduz `"Suscetível a M. paranaensis, M. incognita.
Resistente (M. exigua)"` a `"Suscetível"`, guardando o texto inteiro em
`nematoideDetalhe` — e gravando `null` ali quando o detalhe apenas
repetiria o rótulo. A ordem dos testes (`moderadamente resistente` antes
de `resistente`) espelha a ordem do `_LinhaResistencia` no card.

**3. Cultivar que só aparece nos ensaios entra assim mesmo**, com a ficha
descritiva vazia — "produtividade sem ficha é melhor que cultivar
invisível". É o caso que o `_SemDados` do card atende.

O script aceita `--entrada` e `--saida`, e imprime ao final quantos
cultivares gerou, quantos têm produtividade e quais ficaram sem ficha
descritiva.

Atualizar a planilha exige rodar o script e **republicar o app**, já que
é asset embarcado.

> **⚠** A comparação empírica entre este script e o `CultivarInfoService`
> está em [05 — Verificação](05-services.md#cultivarinfoservice): as
> normalizações batem, mas **5 chaves de município do JSON não existem no
> GeoJSON**, deixando 72 registros de produtividade inalcançáveis.

---

## `test/widget_test.dart` — 26 linhas

**⚠** É o template gerado pelo `flutter create`. Testa um contador que
nunca existiu neste app:

```dart
await tester.pumpWidget(const MyApp());
expect(find.text('0'), findsOneWidget);
await tester.tap(find.byIcon(Icons.add));
```

Falharia se executado. O projeto **não tem testes**. Ver doc 12.
