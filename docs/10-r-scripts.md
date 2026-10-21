# 10 — Scripts R

**Papel no sistema**: os scripts em `r_scripts/` são a etapa de
**pré-processamento**. Eles transformam a saída do modelo agronômico
naquilo que o Python/Flask serve à aplicação.

```
modelo agronômico  →  .RData  →  [ r_scripts ]  →  GeoJSON por município
                                                          │
                                                   Flask serve
                                                          │
                                                   app Flutter consome
```

Rodam **offline, uma vez por safra** — não estão no caminho de nenhuma
requisição do app. Uma vez gerados os GeoJSON, os scripts R não precisam
existir na máquina de produção.

---

## A entrada: `pred.list`

Um arquivo `.RData` (ex.: `Data/plantios/Cafe/MG/dados_cafe.RData`) traz
um objeto `pred.list`: uma lista nomeada em que cada elemento é um
genótipo e cada valor é um data frame com as colunas `x` (longitude),
`y` (latitude) e `layer` (produtividade prevista naquele ponto).

Esse arquivo é **saída do modelo agronômico**, produzido fora deste
repositório.

`loader_predlist.R` apenas carrega o `.RData` num environment novo e
devolve o `pred.list`.

---

## `genotypes_region.R` — o script que importa

É aqui que os GeoJSON consumidos pelo app nascem.
`top_map_genotypes(pred.list, n_top = 5)` faz, em ordem:

### 1. Ranking por ponto

Monta uma matriz ponto × genótipo com as produtividades e, para cada
linha, ordena decrescente:

```r
ord <- order(v, decreasing = TRUE, na.last = NA)
gen <- colnames(layers_mat)[ord]
winner[i]      <- gen[1]
alts_list[[i]] <- gen[seq(2, min(n_top, length(gen)))]
```

O parâmetro `n_top` é o que define quantos cultivares o app mostra.
Mudar de top-5 para top-3 é trocar um argumento:

```r
top_map_genotypes(pred.list, n_top = 3)
```

O Flutter lê o array `alternatives` sem precisar de nenhuma alteração —
o `AnalysisController.selectedRanking` não tem tamanho fixo.

As alternativas são serializadas como array JSON **dentro de uma string**
por linha (`jsonlite::toJSON`), o que explica por que o parser Dart faz
um tratamento tolerante do campo.

Linhas sem vencedor ou sem coordenadas são descartadas.

### 2. Recorte por município

Carrega o shapefile IBGE `BR_Municipios_2021.shp`, filtra `SIGLA == "MG"`
e itera município por município:

- filtro rápido pelo bounding box;
- `st_intersects` para o recorte preciso;
- pula o município se não sobrar nenhum ponto.

### 3. A grade de 1 km

```r
crs_proj <- get_utm_crs(municipio_sf)      # zona UTM calculada pelo centroide
area_utm <- st_transform(municipio_sf, crs_proj)
grid_1ha <- st_make_grid(area_utm, cellsize = c(1000, 1000), square = TRUE)
grid_1ha <- st_intersection(grid_1ha, area_utm)
idx      <- st_nearest_feature(grid_1ha, df_utm)
grid_1ha$winner       <- df_utm$winner[idx]
grid_1ha$alternatives <- df_utm$alternatives[idx]
```

Três pontos importantes:

- A grade é construída numa **projeção UTM local**, calculada pelo
  centroide do município (`get_utm_crs`), e não em graus. É o que garante
  que a célula tenha 1 km de verdade, e não 1 km distorcido pela
  latitude.
- Cada célula recebe o resultado do **ponto de predição mais próximo**
  (`st_nearest_feature`), não uma interpolação.
- A grade é recortada pelo polígono do município (`st_intersection`), o
  que significa que **células de borda não são quadradas**. Isso importa
  para o `AnalysisService`: o índice espacial e o point-in-polygon lidam
  com polígonos irregulares, e é um dos motivos do fallback em
  `resolveCell`.

> A variável se chama `grid_1ha`, mas a célula é de 1 km² = 100 ha. É só
> um nome legado.

### 4. Exportação

Cada arquivo recebe **duas espécies de feature**:

```r
municipio_clean <- st_sf(type = "municipio", winner = NA, alternatives = "[]", ...)
grid_clean      <- st_sf(type = "grid",      winner = ...,  alternatives = ..., ...)
export_sf       <- rbind(municipio_clean, grid_clean)
```

É por isso que o parser Dart filtra:

```dart
if (properties['type'] != 'grid') continue;
```

Sem esse filtro, o contorno do município viraria uma "célula" gigante.

O nome do arquivo é normalizado para ASCII:

```r
mun_name <- toupper(municipio_sf$NM_MUN)
mun_name <- iconv(mun_name, to = "ASCII//TRANSLIT")
mun_name <- gsub("[^A-Z0-9]", "_", mun_name)
fname    <- sprintf("%s_%s.geojson", mun_name, ano)   # OLHOS_D_AGUA_2026.geojson
```

**Esta é a origem do formato `MUNICIPIO_ANO`** que atravessa o sistema
inteiro: é o `stem` do resolver Python, o campo `municipio` da resposta
da API, a coluna `municipio` da tabela Drift e a entrada de
`chaveMunicipio` no `CultivarInfoService`.

A normalização aqui (`iconv` + `gsub`) precisa produzir o mesmo resultado
que `MunicipioResolver._normalize` em Python — senão o resolver não acha
o arquivo.

Saída em `Data/geoJson/<ANO>/`, com `ENCODING=UTF-8` e CRS 4326.

---

## `color_generator.R`

Gera `Data/plantios/Cafe/MG/colors_<ano>.json`, um dicionário genótipo →
cor HCL.

```r
hues <- seq(0, 360, length.out = n + 1)[-1]
hues <- hues[!(hues >= 180 & hues <= 260)]   # remove a faixa azul
hcl(h = hues, c = 70, l = 65, alpha = 0.8)
```

Tons distribuídos uniformemente no círculo de matiz, **excluindo a faixa
azul** (180°–260°) — que se confundiria com água e com o próprio mapa
base.

**Não é mais consumido pelo app**: o mapa é monocromático. O JSON
continua sendo gerado, e o `GenotypeColorManager` deprecado continua no
repositório, prontos para o dia em que a coloração por genótipo voltar.

---

## `tester.R` — o orquestrador

O script que efetivamente se roda:

```r
library(sf)
source("r_scripts/loader_predlist.R", chdir = TRUE)
source("r_scripts/genotypes_region.R", chdir = TRUE)
source("r_scripts/color_generator.R", chdir = TRUE)

caminho   <- file.path("Data", "plantios", "Cafe/MG/dados_cafe.RData")
pred.list <- load_predlist(caminho)

res    <- top_map_genotypes(pred.list)   # gera os geojsons
colors <- save_colors(pred.list)         # gera o JSON de cores
```

Executado a partir da raiz do projeto (os caminhos são relativos ao
`getwd()`).

---

## `api.R` e `genotypes_ranking.R` — o caminho experimental

`api.R` expõe, via `plumber`, dois endpoints em `localhost:8000`:

| Endpoint | Função |
|----------|--------|
| `POST /load_predlist` | devolve o `pred.list` de um `.RData` |
| `POST /genotypes_ranking` | top-N genótipos no ponto de grade mais próximo de uma coordenada |

`genotypes_ranking.R` faz o ranking **em tempo real** para um único
ponto, por distância euclidiana ao quadrado.

Este é o caminho em que o Flask conversaria com o R durante a
requisição — e é o par dos arquivos Python listados como não usados no
[doc 09](09-backend-flask.md#código-python-não-usado-pelo-app)
(`r_client.py`, `select_region.py`, `Core/tester.py`).

**Nada disso está no caminho do app.** A arquitetura que venceu é
pré-computar tudo em GeoJSON.

---

## O que isso significa para quem opera o sistema

1. **Atualizar a safra** = rodar `tester.R`, o que regenera
   `Data/geoJson/<ANO>/` e o JSON de cores.
2. **Reiniciar o Flask depois disso** — o `MunicipioResolver` monta o
   índice de arquivos na inicialização e não vê arquivos novos.
3. **Limpar o cache dos clientes**: o app guarda as regiões por 30 dias
   desde o último acesso. Depois de uma nova safra, usuários continuarão
   vendo a análise antiga até o TTL expirar ou a região ser evicted.
   Hoje **não existe mecanismo de invalidação** — ver
   [doc 12](12-producao-remover-hardcode.md).
4. **Virada de ano**: os arquivos são gerados em `Data/geoJson/<ano
   corrente>/`. Como `analysis_route.py` tem `"2026"` hardcoded enquanto
   os outros módulos usam o ano corrente, é preciso alinhar isso antes de
   janeiro de 2027.
5. **`renv`**: as versões dos pacotes R estão travadas em `renv.lock`.
   Use `renv::restore()` para reproduzir o ambiente.

### Dependências R

`sf` (geoprocessamento), `jsonlite` (serialização), `plumber` (só para
`api.R`), `grDevices` (paleta HCL). Travadas em `renv.lock`.
