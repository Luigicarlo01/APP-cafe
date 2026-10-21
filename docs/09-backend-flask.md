# 09 — Backend Flask

O servidor em `App/`. Ele **não calcula nada agronômico** — isso já foi
feito pelos [scripts R](10-r-scripts.md). Ele localiza e serve arquivos.

---

## Entrypoint

`App/app.py`:

```python
import config
from flask import Flask
from Routes.geojson_map_route import geojson_bp
from Routes.analysis_route import analysis_bp
from Routes.colors_route import colors_bp
from waitress import serve

app = Flask(__name__)
app.register_blueprint(geojson_bp)
app.register_blueprint(analysis_bp)
app.register_blueprint(colors_bp)

if __name__ == "__main__":
    serve(app, host="0.0.0.0", port=5000)
```

Serve com **Waitress** (servidor WSGI de produção), não com o servidor de
desenvolvimento do Flask. Bom ponto de partida, mas ainda escuta em HTTP
puro, sem TLS, sem autenticação e sem limite de taxa — ver
[doc 12](12-producao-remover-hardcode.md).

**⚠** `flask-cors` e `flask-compress` estão no `requirements.txt` mas
**não são registrados** no `app.py`. A compressão importa muito aqui: o
GeoJSON de um município tem vários MB de texto e comprime muito bem.

`App/config.py` carrega `.env` via `python-dotenv` e expõe
`R_SERVICE_URL`, `PROJECT_ROOT`, `DATA_DIR` e `R_SCRIPTS_DIR`.

**⚠** Os caminhos de `config.py` usam `Path(__file__).parent`, que aponta
para `App/`, enquanto as rotas usam `parents[2]`, que aponta para a raiz
do repositório. Os dois não concordam — na prática as rotas ignoram o
`config`.

---

## `POST /api/analysis/municipio`

`App/Routes/analysis_route.py`. **O endpoint principal.**

Consumido por `AnalysisService._fetchMunicipioMeta`.

### Request

```json
{ "lat": -20.75, "lng": -42.87 }
```

### Response 200

```json
{
  "municipio":    "VICOSA_2026",
  "display_name": "Viçosa",
  "winners":      ["IPR100", "MG1177", "Catiguá MG2"],
  "bbox": {
    "min_lat": -20.85, "max_lat": -20.70,
    "min_lon": -42.95, "max_lon": -42.80
  }
}
```

| Campo | Papel no cliente |
|-------|------------------|
| `municipio` | chave ASCII; vira o path do próximo request, o nome da linha no cache e a chave de busca de produtividade por município |
| `display_name` | o que aparece no título da `AnalysisScreen` e no histórico |
| `winners` | guardado no `metadata` do cache; hoje sem consumidor na UI |
| `bbox` | **a chave espacial do cache** |

### Erros

| Status | Quando | O que o app faz |
|--------|--------|-----------------|
| 400 | falta `lat` ou `lng` | `Exception` genérica |
| 404 | ponto fora da cobertura, ou município sem GeoJSON | `NoDataException` → diálogo "Sem dados para esta região" |

### Fluxo interno

1. Valida com `if lat is None or lng is None` — e não `if not lat`,
   porque 0 é latitude válida (equador) mas é falsy em Python.
2. `resolver.find_with_bbox(lat, lng)` → `(stem, bbox, display_name)` ou
   `None`.
3. Abre `Data/geoJson/2026/<stem>.geojson`. Se o arquivo sumiu entre o
   boot e o request, devolve 404.
4. Extrai os vencedores únicos:

```python
winners = list({
    feat["properties"]["winner"]
    for feat in geojson["features"]
    if feat.get("properties", {}).get("type") == "grid"
    and feat["properties"].get("winner")
})
```

Set comprehension faz a deduplicação; `list()` porque JSON não serializa
`set`.

5. Responde com `Response(json.dumps(..., ensure_ascii=False))` em vez de
   `jsonify`, porque o `jsonify` do Flask escapa para ASCII por padrão e
   destruiria os acentos de `display_name`.

### ⚠ Problemas

**Ano hardcoded.**

```python
GEOJSON_DIR = Path(__file__).resolve().parents[2] / "Data" / "geoJson" / "2026"
```

Este arquivo fixa `"2026"`, enquanto `geojson_map_route.py` e
`municipios_resolver.py` usam `str(datetime.now().year)`. **Em 1º de
janeiro de 2027 os três divergem** e a análise quebra.

**Lê o GeoJSON inteiro a cada request.** O arquivo tem vários MB e é
parseado só para extrair a lista de vencedores. O próprio comentário no
código sugere um cache LRU por stem.

**`print()` em vez de logging.** Há `print(winners[:5])` aqui e prints no
resolver.

---

## `GET /api/grid/<mun_name>`

`App/Routes/geojson_map_route.py`. Devolve o GeoJSON inteiro.

Consumido por `AnalysisService._downloadGeoJson`.

```python
def _get_geojson_path(mun_name: str) -> Path | None:
    exact = GEOJSON_DIR / f"{mun_name.upper()}.geojson"
    if exact.exists():
        return exact
    files = list(GEOJSON_DIR.glob(f"{mun_name.upper()}*.geojson"))
    return max(files, key=lambda f: f.stat().st_mtime) if files else None
```

Busca exata primeiro, depois um fallback por prefixo pegando o arquivo
mais recente — o que cobre sufixos legados e variações de nome.

Lê os bytes crus e decodifica como UTF-8, com fallback para latin-1 se
falhar. Devolve `Response(text, mimetype="application/json;
charset=utf-8")`.

404 se não encontrar; 500 com log em caso de exceção.

### ⚠ Problemas

- **`send_file` não é usado.** O arquivo é lido inteiro para memória,
  decodificado e re-encodado. Para arquivos de vários MB, com várias
  requisições simultâneas, isso é caro.
- **Sem compressão.** Aqui é onde o `flask-compress` faria a maior
  diferença.
- **Sem `Cache-Control` nem `ETag`.** O cliente tem cache próprio, mas um
  CDN na frente não teria como aproveitar.
- **⚠ Path traversal.** `mun_name` vem direto da URL para dentro de
  `Path(...) / f"{mun_name.upper()}.geojson"` e de um `glob`. O `.upper()`
  e o sufixo forçado limitam o estrago, mas a entrada não é validada
  contra um whitelist de municípios conhecidos. Ver doc 12.

---

## `GET /api/colors`

`App/Routes/colors_route.py`. Devolve
`Data/plantios/Cafe/MG/colors_2026.json`.

**Não é consumido pelo app.** A coloração por genótipo saiu com o mapa
monocromático; o app usa a cópia local `assets/colors_2026.json`, também
não lida.

Ano e cultura hardcoded no caminho.

---

## `MunicipioResolver`

`App/Services/municipios_resolver.py`. O coração espacial do backend.

Instanciado **uma vez** na importação de `analysis_route.py` — o
shapefile IBGE tem 5.500+ municípios e reler a cada request seria
absurdo.

### Construção

```python
self._gdf = gpd.read_file(SHAPEFILE_PATH, encoding="utf-8").to_crs(epsg=4326)
self._nome_col = "NM_MUN"
self._index = self._build_index()
self._index = self._build_index()   # ⚠ chamado duas vezes
```

`to_crs(epsg=4326)` força WGS84 mesmo se o arquivo vier em SIRGAS 2000 —
é a mesma projeção que o cliente usa.

A chamada duplicada de `_build_index()` é inofensiva (a segunda
sobrescreve com conteúdo idêntico) e já está anotada no próprio código.

Shapefile: `Data/shapefiles/municipality/BR_Municipios_2021.shp`. Não
está versionado — o `.gitignore` exclui `Data/shapefiles`,
`Data/plantios` e `Data/geoJson`.

### Normalização

```python
def _normalize(self, nome: str) -> str:
    sem_acento = unicodedata.normalize("NFKD", nome)
    sem_acento = "".join(c for c in sem_acento if not unicodedata.combining(c))
    return re.sub(r"[^A-Z0-9]", "_", sem_acento.upper())
```

`"Olhos D'Água"` → `"OLHOS_D_AGUA"`. Faz a ponte entre os nomes do
shapefile (com acento e apóstrofo) e os nomes de arquivo (ASCII com
underscore).

### O índice

Escaneia `Data/geoJson/<ANO>/*.geojson` e mapeia chave → stem:

```
OLHOS_D_AGUA_2026.geojson  →  index["OLHOS_D_AGUA"] = "OLHOS_D_AGUA_2026"
```

**⚠** Construído na inicialização. Um GeoJSON novo não é visto até o
processo reiniciar.

### `find_with_bbox(lat, lng)`

```python
pt = Point(lng, lat)                              # ordem (X, Y) = (lng, lat)
matches = self._gdf[self._gdf.geometry.contains(pt)]
if matches.empty: return None

row      = matches.iloc[0]
nome_raw = str(row[self._nome_col])               # "Viçosa"
chave    = self._normalize(nome_raw)              # "VICOSA"

stem = self._index.get(chave)
if not stem: return None                          # município sem análise

minx, miny, maxx, maxy = row.geometry.bounds      # (minLon, minLat, maxLon, maxLat)
bbox = {"min_lat": miny, "max_lat": maxy, "min_lon": minx, "max_lon": maxx}
return stem, bbox, nome_raw
```

Devolve `None` em dois casos distintos que o endpoint colapsa no mesmo
404: ponto fora do Brasil, e município existente mas sem GeoJSON.

O `display_name` é `nome_raw` sem transformação — o IBGE já entrega as
preposições em minúscula ("Nossa Senhora da Glória"), então não há
pós-processamento.

### ⚠ Desempenho

Varredura linear de todos os polígonos (`geometry.contains`). O
comentário estima menos de 100 ms para 5.500 municípios. Com carga real,
o caminho é o índice espacial R-tree do GeoPandas
(`gdf.sindex.query(pt)`), que transforma isso em consulta logarítmica.

---

## O outro Python do repositório

Nem todo `.py` fora de `App/Routes` é código morto. São dois grupos
distintos.

### Usado — só que offline

**`tools/gerar_cultivares_json.py`** (225 linhas) não faz parte do
servidor, mas **é parte do sistema**: lê `Data/data_coffee_ciclo.xlsx` e
gera `front_end/assets/cultivares.json`, o asset de onde sai toda a ficha
técnica que o card da análise mostra.

Roda quando a planilha muda, e a saída é republicada junto com o app.
Documentado em detalhe em
[08 — Como `cultivares.json` é gerado](08-models-utils-assets.md).

### Não usado — o caminho experimental

| Arquivo | O que é |
|---------|---------|
| `App/Infraestructure/r_client.py` | POST para uma API R em `localhost:8000` (`plumber`), carregando `pred.list` |
| `App/Infraestructure/select_region.py` | descobre o `.RData` por cultura/estado e envia ao R |
| `App/Core/build_index.py` | varre `Data/plantios` mapeando cultura → estado → arquivos `.RData` |
| `App/Core/tester.py` | script solto que consulta `/genotypes_ranking` do R para Trigo/MG |

Todos pertencem a um caminho **experimental** em que o Flask conversaria
com o R em tempo real via `plumber` (`r_scripts/api.R`). O caminho em
produção é outro: o R roda offline e gera os GeoJSON, e o Flask só os
serve. Nada disso é acionado pelas rotas que o app consome.

> Note que `App/Core/tester.py` referencia `Trigo/MG/trigoBlups.RData` —
> vestígio de quando o projeto mirava mais de uma cultura, do mesmo modo
> que o `CropSelectionSheet` deprecado no Flutter.

---

## Resumo dos contratos

```
Flutter                                   Flask
───────────────────────────────────────────────────────────────────
AnalysisService._fetchMunicipioMeta
  POST /api/analysis/municipio      →     analysis_route.get_municipio
  {lat, lng}                                MunicipioResolver.find_with_bbox
                                            lê o .geojson, extrai winners
  ← {municipio, display_name,               Response(json, ensure_ascii=False)
     winners, bbox}

AnalysisService._downloadGeoJson
  GET /api/grid/<municipio>         →     geojson_map_route.get_grid
  (streaming, timeout 180 s)                _get_geojson_path (exato → glob)
  ← GeoJSON completo                        Response(text, charset=utf-8)
```

Nenhum dos dois endpoints exige autenticação ou envia cabeçalho de cache.
