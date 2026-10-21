# 12 — Caminho para produção: remover o hardcode de rede

Este é o documento que responde à pergunta *"o que falta para o app
deixar de apontar para um IP de LAN e passar a falar com um servidor de
verdade?"*.

Está organizado em **fases**, na ordem em que faz sentido executar. Cada
fase entrega algo utilizável sozinha.

---

## O estado atual, em uma imagem

```
┌────────────────┐   http://192.168.3.4:5000    ┌──────────────────┐
│  app Flutter   │ ───────────────────────────► │ Flask + Waitress │
│                │      texto claro, LAN        │ na máquina do    │
│ chave Google   │                              │ desenvolvedor    │
│ literal no     │   https://places.google…     └──────────────────┘
│ código-fonte   │ ───────────────────────────► Google Maps Platform
└────────────────┘
```

Três coisas impedem que isso vire produção:

1. O endereço do backend é um literal no código, e muda a cada rede.
2. O tráfego é HTTP em texto claro — que o Android (`targetSdk 36`) e o
   iOS (ATS) bloqueiam **inclusive em debug**, não só em release. Ver
   [doc 11](11-plataformas-build.md#-cleartext-http--bloqueado-hoje-em-todos-os-build-types).
3. A chave da Google Maps Platform está no código-fonte e **versionada
   no git**.

Somam-se a isso os problemas de empacotamento do [doc 11](11-plataformas-build.md).

---

## Fase 0 — Contenção imediata (antes de qualquer outra coisa)

### 0.1 Rotacionar a chave da Google Maps Platform 🔴

A chave está em `front_end/lib/services/api_config.dart` e o arquivo está
**versionado**:

```
$ git ls-files front_end/lib/services/api_config.dart
front_end/lib/services/api_config.dart
```

Isso significa que ela está no histórico do repositório. Remover a linha
num commit novo **não resolve** — quem tiver o histórico continua tendo
a chave.

Ordem das ações:

1. No Google Cloud Console, **criar uma chave nova** e **excluir a
   atual**. Não basta restringir: a chave antiga precisa deixar de
   existir.
2. Na chave nova, aplicar restrições **antes** de usá-la:
   - **Restrição de aplicativo** → Android apps, com o `applicationId`
     definitivo e o fingerprint SHA-1 do certificado de release. Para
     iOS, o bundle id. (Restrição por aplicativo é o que impede alguém
     que extraia a chave do APK de usá-la em outro app.)
   - **Restrição de API** → apenas *Places API (New)* e, se
     `forwardGeocode` for reativado, *Geocoding API*.
3. Definir **cota diária** e **alerta de orçamento**. Uma chave sem cota
   e sem alerta é uma conta aberta.
4. Se o repositório for ou vier a ser público, considerar reescrever o
   histórico (`git filter-repo`) — sabendo que isso reescreve todos os
   hashes e exige coordenação com quem tiver clones.

> **Sobre esconder a chave no app**: uma chave de API embarcada num
> aplicativo móvel **nunca** é secreta — qualquer pessoa consegue
> extraí-la do binário. `--dart-define` melhora a higiene do repositório
> (a chave sai do git), mas não protege a chave. **A proteção real são
> as restrições de aplicativo e de API**, mais a cota. Se a proteção
> precisar ser total, a busca de cidades teria de passar por um endpoint
> do próprio backend, que guardaria a chave no servidor — ver
> [Fase 5](#fase-5--evoluções-opcionais).

### 0.2 Corrigir a permissão de INTERNET 🔴

Sem isso, nenhum build de release funciona. Em
`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

A segunda é exigida pelo `connectivity_plus` em algumas versões do
Android.

### 0.3 Corrigir a descrição de localização no iOS 🔴

Em `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>O PlantioAPP usa sua localização para centralizar o mapa na sua
lavoura e sugerir cultivares para o ponto onde você está.</string>
```

Sem isso o app **encerra** no primeiro toque no botão de GPS.

---

## Fase 1 — Tirar a configuração do código

Objetivo: nenhum endereço nem chave literal em arquivo `.dart`.

### 1.1 Reescrever `api_config.dart`

A ferramenta certa é `--dart-define`, que injeta valores em tempo de
compilação. `String.fromEnvironment` é `const`, então o compilador
consegue fazer tree shaking do que não for usado.

```dart
// lib/services/api_config.dart

/// URL base da API. Injetada em tempo de compilação:
///   flutter build apk --dart-define=API_BASE_URL=https://api.exemplo.br
///
/// O default aponta para o emulador Android, de forma que
/// `flutter run` sem argumento continue funcionando em desenvolvimento.
const String kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:5000',
);

/// Chave da Google Maps Platform. NÃO é segredo — ver docs/12.
/// A proteção vem das restrições de aplicativo e de API no Console.
const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: '',
);
```

Três mudanças de comportamento a observar:

- **`kBaseUrl` deixa de ser getter e vira `const`.** As chamadas
  existentes (`'$kBaseUrl/api/grid/$mun'`) continuam idênticas.
- **A ramificação por `Platform.isAndroid` some**, e com ela o
  `import 'dart:io'` — o que, de quebra, remove o obstáculo para o web.
  `10.0.2.2` é o alias do host no emulador Android; em dispositivo
  físico, passa-se o IP pelo `--dart-define`.
- **O default da chave é vazio.** Vale adicionar um guard-rail no
  `GooglePlacesService`:

```dart
if (googleMapsApiKey.isEmpty) {
  debugPrint('GOOGLE_MAPS_API_KEY não definida — busca de cidades desativada.');
  return [];
}
```

Remover também o alias `@Deprecated String get apiKey`.

### 1.2 Arquivos de configuração por ambiente

`--dart-define-from-file` (Flutter 3.7+) evita repetir argumentos:

```jsonc
// front_end/config/dev.json          ← versionado, sem segredos
{
  "API_BASE_URL": "http://10.0.2.2:5000",
  "GOOGLE_MAPS_API_KEY": ""
}
```

```jsonc
// front_end/config/prod.json         ← NO .gitignore
{
  "API_BASE_URL": "https://api.plantioapp.br",
  "GOOGLE_MAPS_API_KEY": "AIza..."
}
```

```bash
flutter run   --dart-define-from-file=config/dev.json
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

Acrescentar ao `.gitignore`:

```
front_end/config/prod.json
front_end/config/*.local.json
```

E versionar um `config/prod.example.json` com as chaves vazias, para
documentar o formato.

### 1.3 Centralizar a URL dos tiles

Hoje o template do CARTO aparece em **três** arquivos ativos, com risco
de divergirem:

| Arquivo | Linha |
|---------|-------|
| `widgets/map_widget.dart` | `urlTemplate` do `TileLayer` |
| `widgets/genotype_plot.dart` | `urlTemplate` do `TileLayer` |
| `services/cache/base_map_service.dart` | `_urlTemplate` do download |

Mais o `tile_downloader.dart` deprecado, que usa **outra URL**
(`cartodb-basemaps-a.global.ssl.fastly.net`, sem `{s}`).

Além da URL, três constantes precisam concordar entre si e não
concordam por construção — estão duplicadas como literais:

| Constante | Onde aparece |
|-----------|--------------|
| zoom máximo do mapa base (`10`) | `base_map_service.dart` (`_maxZoom`), `map_screen.dart` (`maxZoom`/`maxNativeZoom` offline), `genotype_plot.dart` (`maxNativeZoom`) |
| zoom nativo online (`18`) | `map_widget.dart`, `genotype_plot.dart` |
| subdomínios | três arquivos |

Proposta — um arquivo novo `lib/services/tile_config.dart`:

```dart
class TileConfig {
  TileConfig._();

  static const String urlTemplate =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
  static const List<String> subdomains = ['a', 'b', 'c', 'd'];

  static const String userAgentPackageName = 'br.<org>.plantioapp';

  /// Maior zoom presente no mapa base offline.
  /// Mudar aqui muda o download E os limites das duas telas.
  static const int offlineMaxZoom = 10;

  /// Maior zoom com tile real no CARTO Light.
  static const int onlineMaxNativeZoom = 18;

  static const int baseMapMinZoom = 6;
}
```

### 1.4 Centralizar timeouts

`analysis_service.dart` tem `15` e `180` segundos literais;
`base_map_service.dart` tem `6`. Merecem constantes nomeadas no mesmo
lugar da URL base, de preferência também ajustáveis por `--dart-define`
— um servidor remoto real tem latência diferente de um laptop na mesma
LAN.

---

## Fase 2 — Colocar o backend num servidor de verdade

### 2.1 A decisão que vem antes de tudo: o GeoJSON precisa do Flask?

Vale examinar antes de escolher hospedagem.

Os arquivos de `Data/geoJson/<ANO>/` são **estáticos**: gerados uma vez
por safra, idênticos para todos os usuários, e nunca modificados em
runtime. O endpoint `GET /api/grid/<mun>` não faz nada além de localizar
e devolver um arquivo.

Isso significa que o caminho mais pesado do sistema pode sair do
servidor de aplicação:

```
Object storage (S3 / R2 / Spaces) + CDN
   └── geojson/2026/VICOSA_2026.geojson.gz
```

O `POST /api/analysis/municipio` continuaria no Flask (precisa do
GeoPandas), mas passaria a devolver também a URL do arquivo:

```json
{
  "municipio": "VICOSA_2026",
  "display_name": "Viçosa",
  "winners": [...],
  "bbox": {...},
  "grid_url": "https://cdn.plantioapp.br/geojson/2026/VICOSA_2026.geojson"
}
```

E o `AnalysisService._downloadGeoJson` usaria `meta['grid_url']` quando
presente, caindo em `'$kBaseUrl/api/grid/$mun'` quando ausente — o que
mantém compatibilidade com o backend atual.

**Benefícios**: o download de vários MB deixa de ocupar o servidor de
aplicação; ganha-se cache de CDN, `ETag`, `Range` e compressão de graça;
e o servidor pode ser pequeno.

Se a opção for manter tudo no Flask, o restante desta fase continua
valendo — só o volume de tráfego muda.

### 2.2 Empacotar

`Dockerfile` (esboço):

```dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      gdal-bin libgdal-dev libgeos-dev proj-bin && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY App/ ./App/
COPY Data/shapefiles/ ./Data/shapefiles/
COPY Data/geoJson/    ./Data/geoJson/
WORKDIR /app/App
CMD ["python", "app.py"]
```

O shapefile e os GeoJSON não estão no git (`.gitignore` os exclui), então
a pipeline precisa buscá-los de outro lugar — object storage é o caminho
natural, e se alinha com a decisão 2.1.

### 2.3 Corrigir os problemas do código do backend

Estes são pré-requisitos, não melhorias:

**Registrar CORS e compressão.** Já estão no `requirements.txt` e não
são usados:

```python
from flask_compress import Compress
from flask_cors import CORS

app = Flask(__name__)
Compress(app)            # ~10× no GeoJSON
CORS(app, origins=[...]) # necessário se houver versão web
```

**Resolver o ano hardcoded.** `analysis_route.py` fixa `"2026"`;
`geojson_map_route.py` e `municipios_resolver.py` usam
`datetime.now().year`. **Em 1º de janeiro de 2027 isso quebra.** A
correção: uma variável de ambiente `SAFRA_ANO`, lida em `config.py` e
usada pelos três.

**Validar `mun_name`.** Hoje ele vai direto da URL para a construção de
`Path` e para um `glob`. Validar contra o índice que o resolver já
mantém:

```python
# o resolver já mantém o índice chave → stem; basta expô-lo
if mun_name.upper() not in resolver.stems_validos:
    return {"error": "Município desconhecido"}, 404
```

(`stems_validos` seria uma propriedade nova sobre o `_index` que o
`MunicipioResolver` já constrói no boot.)

**Usar `send_file`.** Em vez de ler, decodificar e re-encodar o arquivo
inteiro em memória:

```python
return send_file(path, mimetype="application/json")
```

**Índice espacial no resolver.** `gdf.geometry.contains(pt)` varre 5.500
polígonos. Com R-tree:

```python
candidatos = self._gdf.iloc[list(self._gdf.sindex.query(pt))]
matches = candidatos[candidatos.geometry.contains(pt)]
```

**Cache do GeoJSON no `analysis_route`.** Ele lê o arquivo inteiro só
para extrair os vencedores, a cada request:

```python
from functools import lru_cache

@lru_cache(maxsize=256)
def _winners_de(stem: str) -> tuple[str, ...]:
    ...
```

**Trocar `print` por `logging`.** Existem prints em `analysis_route.py`,
`geojson_map_route.py` e `municipios_resolver.py`.

**Healthcheck.** `GET /health` devolvendo `{"status": "ok", "safra":
2026, "municipios": 847}` — necessário para orquestração e monitoramento.

### 2.4 TLS

O app precisa falar HTTPS. Duas opções usuais:

- **Reverse proxy** (Caddy ou Nginx) na frente do Waitress, com
  certificado Let's Encrypt. O Caddy resolve o certificado sozinho.
- **Plataforma gerenciada** (Cloud Run, Fly.io, Render, Railway) que já
  termina TLS.

Depois disso, `API_BASE_URL=https://api.plantioapp.br` e o problema de
cleartext desaparece nas duas plataformas — **sem** precisar de
`usesCleartextTraffic` no Android ou exceção de ATS no iOS.

### 2.5 Ambiente de desenvolvimento continua funcionando

Não se deve perder o fluxo atual. Com os arquivos de config da Fase 1:

| Cenário | Comando |
|---------|---------|
| Emulador Android + backend local | `flutter run --dart-define-from-file=config/dev.json` (default `10.0.2.2`) |
| Aparelho físico + backend na LAN | `flutter run --dart-define=API_BASE_URL=http://192.168.x.y:5000` |
| Aparelho físico + backend em produção | `--dart-define-from-file=config/prod.json` |

Para o cenário do meio, o Android exige cleartext — e, como o doc 11
mostra, isso **já é necessário hoje**, não é uma consequência da
migração: com `targetSdk 36` e nenhuma configuração de rede no projeto, o
sistema recusa `http://` em qualquer build type. A forma limpa é um
`networkSecurityConfig` **apenas no build type de debug**, que nunca
chega ao release:

```xml
<!-- android/app/src/debug/res/xml/network_security_config.xml -->
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="true">10.0.2.2</domain>
    <domain includeSubdomains="true">192.168.0.0</domain>
  </domain-config>
</network-security-config>
```

Alternativa mais simples e sem configuração nativa: `adb reverse tcp:5000
tcp:5000`, que faz o `localhost` do aparelho apontar para a máquina de
desenvolvimento.

---

## Fase 3 — Empacotamento do app

Itens do [doc 11](11-plataformas-build.md), na ordem de bloqueio.

### 3.1 Identidade

```kotlin
android {
    namespace = "br.<organizacao>.plantioapp"
    defaultConfig {
        applicationId = "br.<organizacao>.plantioapp"
        minSdk = 24
        targetSdk = 35
    }
}
```

> O `applicationId` é **imutável após a primeira publicação**. Decida
> antes de subir qualquer coisa para o Play Console.

No manifesto, `android:label="PlantioAPP"` (ou "Typica", conforme a
marca). No iOS, `CFBundleDisplayName` e `CFBundleName` correspondentes, e
o `PRODUCT_BUNDLE_IDENTIFIER` no Xcode.

Alinhar `userAgentPackageName` dos dois `TileLayer` com o
`applicationId` — hoje é `com.LuisFelipe.PlantioAPP.dev`.

### 3.2 Assinatura

Gerar o keystore de release, guardá-lo **fora** do repositório e
referenciá-lo por `key.properties` (também fora do git):

```kotlin
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

signingConfigs {
    create("release") {
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
    }
}
buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
```

Perder esse keystore significa não conseguir mais atualizar o app —
guarde-o com o mesmo cuidado de uma credencial de produção.

### 3.3 Ícone e splash nativa

`flutter_launcher_icons` e `flutter_native_splash` resolvem os dois a
partir dos SVG/PNG já existentes em `assets/`.

### 3.4 Higiene de release

Envolver o dump de cache em `kDebugMode` (`app_bootstrap.dart`):

```dart
if (kDebugMode) {
  await RegionCacheService().debugDump();
}
```

Ele varre a tabela inteira e imprime dezenas de linhas em toda abertura.

Os `debugPrint` espalhados já são no-op em release, então não há
urgência com eles — mas convém revisar os que imprimem URL ou dado do
usuário.

### 3.5 Restrição de orientação

O app não foi projetado para paisagem. No `main()`:

```dart
SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
```

E ajustar `UISupportedInterfaceOrientations` no `Info.plist`.

---

## Fase 4 — Dívidas do código Flutter

Nenhuma bloqueia o lançamento; todas foram encontradas na leitura e estão
referenciadas nos docs 03 a 08.

### 4.1 Corretude

| # | Item | Onde | Impacto |
|---|------|------|---------|
| 1 | O **ciclo de maturação não é usado**. O `CropCycleService` é lido só pelo próprio seletor; nem o `AnalysisService` nem o backend recebem o parâmetro. O tutorial afirma que "a recomendação leva essa preferência em conta". | `crop_cycle_service.dart`, `analysis_service.dart` | A interface promete algo que não acontece |
| 2 | O ciclo também **não é persistido** — volta a `medio` a cada boot. | idem | Menor |
| 3 | `_showConnectionErrorDialog` decide o texto **casando substrings** da mensagem de erro. Mudar o texto de uma exceção muda o diálogo em silêncio. | `map_screen.dart` | Frágil |
| 4 | `resolveSuggestion` desliga `_isResolving` no `finally` **sem `notifyListeners()`**. Hoje inofensivo (ninguém consome), quebra quando a UI for plugada. | `search_controller.dart` | Latente |
| 5 | `LocationService` devolve `null` em silêncio para permissão negada, GPS desligado e erro. O usuário toca no FAB e nada acontece. | `location_service.dart` | UX |
| 6 | O índice espacial indexa a célula pelo **centroide**. Célula que se estenda por mais de um bucket pode não ser achada a partir da borda. Mitigado por `resolveCell`. | `analysis_service.dart` | Conhecido |
| 7 | **Não há invalidação de cache por safra.** Depois de gerar GeoJSON novo, o usuário continua vendo a análise antiga por até 30 dias. | `region_cache_service.dart` | Ver 4.4 |
| 7b | **5 chaves de município em `cultivares.json` não existem no GeoJSON** — 72 registros de produtividade nunca chegam à tela. Erro de digitação (`FRANCISCO_DRUMOND`), duas cidades numa célula (`IBIA_ARAXA`, `IBIA_SAO_GOTARDO`), município de SP (`SAO_SEBASTIAO_DA_GRAMA`) e uma localidade que não é município. | `Data/data_coffee_ciclo.xlsx` | Dado que existe e some. Ver 4.5 |

### 4.2 Duplicação

| # | Item |
|---|------|
| 8 | `MapWidget._loadMask()` relê e reparseia `assets/mg.geojson`, que o `MgShapeService` já carregou no boot. Duas cópias em memória. |
| 9 | URL dos tiles, subdomínios e limites de zoom repetidos em três arquivos (ver [1.3](#13-centralizar-a-url-dos-tiles)). |
| 10 | `_toTitleCase` implementado duas vezes, idêntico, em `analysis_screen.dart` e `history_screen.dart`. Candidato a `utils/`. |
| 11 | A normalização de nomes de cultivar vive **em Dart e em Python**. Divergir faz o card ficar vazio **sem erro**. Um teste que compare as duas implementações sobre a lista de 40 cultivares resolveria. |
| 12 | Cores fora de `AppColors` em quatro arquivos: `0xFF02890A` literal em `app_drawer.dart` e em `points_plot.dart`; `Color.fromARGB(255, 2, 141, 6)` em `crop_selection_sheet.dart` — que é `#028D06`, **um verde diferente** do `#02890A` da marca; e `0xFFB26A00` / `0xFFB3261E` em `genotype_detail_card.dart` (estes dois são semânticos, de resistência, mas seriam melhores como constantes nomeadas). |
| 12b | **~852 KB de assets mortos** no APK: `esmeraldas.geojson` (812 KB, análise antiga de um município), `logo_ufv.png` (32 KB) e `typica_logo.svg` (7 KB). Nenhum é referenciado por código. É 77% do peso de `assets/`. |

### 4.3 Arquitetura

| # | Item |
|---|------|
| 13 | `HistoryScreen` consulta o Drift diretamente, violando a regra declarada em `region_cache_service.dart`. Um método `RegionCacheService.listRecent(limit)` resolveria. |
| 14 | **Sem testes.** `test/widget_test.dart` é o template do `flutter create` e falharia. Os candidatos de maior retorno: `TileMath` (matemática pura), `BoundingBox`, `CultivarInfoService.chaveCultivar` (contra o Python), `RegionCacheService` (quota e TTL), `_parseCellsIsolate` sobre um GeoJSON pequeno. |
| 15 | Services não são mockáveis — singletons acessados diretamente. Bloqueia o item 14 em parte. |
| 16 | `MapWidget` **não** usa o `CachedRegionTileProvider`; só o mapa da análise lê do mapa base offline. A tela inicial offline depende do cache HTTP do sistema. |

### 4.4 Invalidação de cache por safra — o desenho

O item 7 merece detalhe, porque vira problema no primeiro ciclo de
atualização de dados.

**Proposta**: o backend passa a devolver uma versão dos dados, e o cache
a guarda.

```json
{ "municipio": "VICOSA_2026", "data_version": "2026.1", ... }
```

1. Nova coluna `dataVersion` em `CachedRegions` (schema v3 + migration).
2. `RegionCacheService.get()` compara a versão guardada com a atual; se
   divergir, trata como miss e apaga a linha.
3. A versão corrente chega ao app pela própria resposta do
   `/api/analysis/municipio` — não exige endpoint novo.

**Efeito colateral a considerar**: um usuário offline com dados da safra
anterior perde o acesso assim que voltar a ter sinal. Pode ser melhor
manter a entrada antiga e apenas **marcá-la como desatualizada** na
interface, deixando a decisão para o usuário.

### 4.5 Higiene da planilha de cultivares

O item 7b não é bug de código — é dado. Mas some em silêncio, que é a
pior forma de sumir.

**Correção imediata**, em `Data/data_coffee_ciclo.xlsx`:

| Corrigir | Para |
|----------|------|
| `Francisco Drumond` | `Francisco Dumont` |
| `Ibiá/Araxá` | duas linhas: `Ibiá` e `Araxá` |
| `Ibiá/São Gotardo` | duas linhas: `Ibiá` e `São Gotardo` |
| `São Sebastião da Grama` | é SP — decidir se sai ou se a cobertura passa a incluir |
| `Sebastião Gomes do Prado` | mapear para o município que contém essa localidade |

**Correção estrutural**, em `tools/gerar_cultivares_json.py`: fazer o
script validar as chaves contra os stems de `Data/geoJson/<ANO>/` e
**avisar no final**, junto com o `sem ficha descritiva` que ele já
imprime:

```python
stems = {re.sub(r'_\d{4}$', '', p.stem)
         for p in (RAIZ / "Data" / "geoJson" / ANO).glob("*.geojson")}
orfas = {m for c in cultivares.values()
           for m in c["produtividade"]["municipios"] if m not in stems}
if orfas:
    print(f"  ⚠ municípios sem GeoJSON (dado inalcançável): {', '.join(sorted(orfas))}")
```

Dez linhas que transformam perda silenciosa em aviso na hora de gerar.

---

## Fase 5 — Evoluções opcionais

Não são necessárias para produção; ficam registradas porque o código já
as antecipa.

| Ideia | Estado atual |
|-------|--------------|
| **Proxy da busca de cidades pelo backend.** Um `GET /api/places?q=` no Flask guardaria a chave do Google no servidor. Elimina de vez a exposição da chave e permite cache de buscas repetidas. | `GooglePlacesService` teria que apontar para `kBaseUrl` |
| **Autenticação e conta de usuário.** `LoginScreen` e `AppDrawer` estão prontos e deprecados, aguardando backend. | ver doc 13 |
| **Favoritos persistentes.** `AnalysisController` mantém a interface pública (`isSelectedFavorited` / `toggleFavoriteSelected`); falta a tabela Drift. | ver doc 13 |
| **Ponto exato no histórico.** Hoje o histórico reabre no centro do bbox. Uma coluna com o lat/lng do acesso, ou uma tabela `access_log`, daria precisão. | sugerido em `history_screen.dart` |
| **Ping real de conectividade.** `connectivity_plus` não distingue "tem Wi-Fi" de "tem internet". | sugerido em `app_mode.dart` |
| **Coloração por genótipo como camada opcional.** O JSON de cores continua sendo gerado pelo R e o `GenotypeColorManager` continua no repo. | ver doc 13 |
| **Cache passivo de tiles.** Hoje o que o usuário navega não é gravado. O comentário em `cached_region_tile_provider._loadBytes` marca onde uma linha bastaria. | — |
| **Botão "limpar cache".** `RegionCacheService.clear()` existe e não tem chamador. | — |

---

## Checklist consolidado

### Bloqueia o release

- [ ] Rotacionar a chave do Google e aplicar restrições de aplicativo, de API e cota
- [ ] Adicionar `INTERNET` e `ACCESS_NETWORK_STATE` ao manifesto `main`
- [ ] Criar o `networkSecurityConfig` de debug (desbloqueia o desenvolvimento contra o Flask local em Android 9+)
- [ ] Adicionar `NSLocationWhenInUseUsageDescription` ao `Info.plist`
- [ ] Trocar `kBaseUrl` e `googleMapsApiKey` por `String.fromEnvironment`
- [ ] Publicar o backend com HTTPS
- [ ] Definir `applicationId` / bundle id definitivos
- [ ] Criar e guardar o keystore de release
- [ ] Nome do app e ícone próprios
- [ ] Bundle id do iOS (hoje `com.example.frontEnd`)

### Antes do primeiro ciclo de atualização de dados

- [ ] Resolver o ano hardcoded em `analysis_route.py`
- [ ] Registrar `Compress` e `CORS` no Flask
- [ ] Validar `mun_name` contra o índice do resolver
- [ ] Definir a estratégia de invalidação de cache por safra
- [ ] Corrigir os 5 municípios órfãos da planilha e fazer o script avisar (4.5)
- [ ] Endpoint `/health` e logging estruturado

### Higiene

- [ ] Centralizar URL de tiles, subdomínios, limites de zoom e timeouts
- [ ] `debugDump()` sob `kDebugMode`
- [ ] Apagar os ~852 KB de assets não referenciados
- [ ] Splash nativa bege, para eliminar o flash branco na abertura
- [ ] Rodar `flutter analyze` e tratar as 42 ocorrências de `withOpacity`
- [ ] Testes de `TileMath`, `BoundingBox` e das duas normalizações
- [ ] `MapWidget` usando o `MgShapeService` em vez de reler o asset
- [ ] `HistoryScreen` acessando o cache pelo service
- [ ] Ligar o ciclo de maturação à análise, **ou** remover a promessa do tutorial
