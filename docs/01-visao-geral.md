# 01 — Visão geral

## O que o app faz

O PlantioAPP (marca **Typica** na interface) responde a uma pergunta:

> "Neste ponto específico da minha lavoura em Minas Gerais, qual
> cultivar de café eu devo plantar?"

O usuário toca num ponto do mapa de MG, confirma, e recebe:

1. Os cultivares recomendados para a **célula de 1 km²** onde o ponto
   caiu — o vencedor mais as alternativas.
2. A ficha técnica de cada cultivar: produtividade medida em ensaios
   (preferencialmente no próprio município), resistência a ferrugem e a
   nematóide.
3. Um mapa da região inteira em que cada célula de 1 km² é tocável,
   permitindo comparar pedaços vizinhos do terreno.

E faz isso **funcionando sem internet** em regiões já consultadas — que
é a razão de existir metade da complexidade do código.

## Para quem

Produtor de café e técnico de campo em Minas Gerais. O contexto de uso
é a lavoura: tela pequena, sol forte, sinal ruim ou inexistente. Isso
explica três decisões que aparecem o tempo todo no código:

- **Mapa monocromático.** Todas as células no mesmo verde. Doze cores
  diferentes sob sol ficam indistinguíveis; a recomendação vem em texto.
- **Cache agressivo.** Região consultada uma vez fica no aparelho por
  30 dias.
- **Honestidade sobre o dado.** O card de cultivar nunca inventa: se a
  produtividade vem da média estadual e não do município, ele diz isso;
  se a amostra municipal é de um único registro, ele mostra a estadual
  ao lado como escala.

## Stack

| Camada | Tecnologia | Onde |
|--------|-----------|------|
| App | Flutter / Dart (SDK ^3.10.7) | `front_end/` |
| Mapa | `flutter_map` 8.2 + tiles CARTO Light (dados OSM) | `front_end/lib/widgets/` |
| Cache local | Drift 2.20 (SQLite) + arquivos em AppDocs | `front_end/lib/services/cache/` |
| Rede | pacote `http` + `connectivity_plus` | `front_end/lib/services/` |
| Busca de cidades | Google Places API (New) + Geocoding API | `front_end/lib/services/google_*` |
| API | Flask + Waitress, Python | `App/` |
| Geoprocessamento (servidor) | GeoPandas + Shapely | `App/Services/` |
| Pré-processamento | R (`sf`, `jsonlite`, `plumber`) | `r_scripts/` |

Dependências completas do app em `front_end/pubspec.yaml`; do backend em
`requirements.txt`; do R em `renv.lock`.

---

## O caminho completo do dado

Esta é a cadeia inteira, do modelo agronômico até o chip verde na tela.
Cada etapa tem um documento próprio.

### Etapa 1 — Offline, no R (uma vez por safra)

**Doc: [10 — Scripts R](10-r-scripts.md)**

Um arquivo `.RData` traz o `pred.list`: para cada genótipo, uma grade de
pontos `(x, y, layer)` onde `layer` é a produtividade prevista naquele
ponto. Isso é saída do modelo agronômico — não é produzido por este
repositório.

`r_scripts/genotypes_region.R` transforma isso em GeoJSON:

- Para cada ponto da grade, ordena os genótipos por produtividade →
  define `winner` e `alternatives` (top-N).
- Recorta por município (shapefile IBGE, só MG).
- Gera uma **grade regular de 1 km × 1 km** dentro do município, em
  projeção UTM local, e atribui a cada célula o resultado do ponto de
  predição mais próximo.
- Exporta `Data/geoJson/<ANO>/<MUNICIPIO>_<ANO>.geojson`.

Resultado: ~850 arquivos GeoJSON (um por município de MG), cada um com
milhares de polígonos.

### Etapa 2 — No servidor, sob demanda

**Doc: [09 — Backend Flask](09-backend-flask.md)**

O Flask não calcula nada agronômico. Ele faz duas coisas:

- `POST /api/analysis/municipio` — recebe `{lat, lng}`, descobre por
  spatial join no shapefile IBGE qual município contém o ponto, e
  devolve o identificador do arquivo, o nome bonito, a lista de
  vencedores e o bounding box do município.
- `GET /api/grid/<municipio>` — devolve o arquivo GeoJSON inteiro.

### Etapa 3 — No aparelho

**Docs: [05 — Services](05-services.md) e [06 — Cache](06-cache-offline.md)**

`AnalysisService.load(lat, lng)` é o centro de gravidade do app:

1. Pergunta ao cache local se já existe região cujo bounding box
   contenha o ponto. Se sim, lê do disco e termina — zero rede.
2. Se não tem cache e está offline, aborta com erro específico (não
   espera timeout).
3. Chama os dois endpoints acima.
4. Faz o parse do GeoJSON **num isolate** (`compute`), porque o arquivo
   tem dezenas de milhares de linhas e o `jsonDecode` na thread
   principal congelaria a interface.
5. Grava tudo no cache.

### Etapa 4 — Na tela

**Docs: [03 — Telas](03-telas.md) e [07 — Widgets](07-widgets.md)**

A `AnalysisScreen` desenha o mapa com as células, e o
`AnalysisController` decide qual célula está selecionada. A ficha de
cada cultivar **não vem do backend** — vem de `assets/cultivares.json`,
um asset embarcado no app (ver [05](05-services.md#cultivarinfoservice)).

---

## Modos de operação

O app tem dois modos, decididos por `AppMode` (`connectivity_plus`):

### Online

Comportamento completo. A barra de busca de cidades aparece, o zoom vai
até 18, tiles caem para a rede quando não estão em disco.

### Offline

- Badge vermelho "Modo offline" no topo da tela inicial.
- A barra de busca **some** — o Google Places não responderia mesmo.
- Aparece a pílula "Regiões salvas no aparelho", que leva ao
  [histórico](03-telas.md). Offline esse é o único
  caminho para abrir uma análise.
- Zoom limitado a 10 na tela inicial, e `maxNativeZoom` = 10 em todos
  os mapas (o mapa base pré-baixado só tem tiles até esse zoom; acima
  disso o `flutter_map` estica o último tile em vez de pedir rede).
- `AnalysisService` recusa a análise de região não cacheada com
  mensagem clara, sem esperar timeout.

**⚠ Limitação conhecida**: `connectivity_plus` só reporta "existe
interface de rede ativa", não "existe internet". Wi-Fi conectado a um
roteador sem uplink é reportado como online. Está anotado no próprio
`app_mode.dart`.

---

## Glossário

| Termo | Significado |
|-------|-------------|
| **Célula / grid cell** | Quadrado de 1 km × 1 km com uma recomendação. É a unidade de granularidade do app. |
| **Winner** | Genótipo de maior produtividade prevista na célula. |
| **Alternatives** | Os demais do top-N, em ordem de produtividade prevista. Tamanho definido pelo R, não hardcoded no app. |
| **Genótipo / cultivar** | Usados como sinônimos no código. "Genótipo" é herança do vocabulário do R; "cultivar" é o que aparece na interface. |
| **`municipio`** | Chave ASCII com sufixo de ano: `VICOSA_2026`. É identificador de arquivo e de cache, nunca texto de interface. |
| **`display_name`** | Nome oficial IBGE com acentos: `Viçosa`. É o que aparece na tela. |
| **bbox** | Retângulo geográfico `{min_lat, max_lat, min_lon, max_lon}`. Chave espacial do cache. |
| **Mapa base** | Pirâmide de tiles do CARTO cobrindo MG nos zooms 6–10, baixada sob demanda pelo usuário (~2100 tiles, ~15 MB). |
| **Fase B / Fase C** | Referências históricas nos comentários. Fase B = mapa base offline; Fase C = detecção online/offline. |
