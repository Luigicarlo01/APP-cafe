from pathlib import Path
import geopandas as gpd
from shapely.geometry import Point
import re
import unicodedata
from datetime import datetime

SHAPEFILE_PATH = Path(__file__).resolve().parents[2] / "Data" / "shapefiles" / "municipality" / "BR_Municipios_2021.shp"
GEOJSON_DIR    = Path(__file__).resolve().parents[2] / "Data" / "geoJson" / str(datetime.now().year)


class MunicipioResolver:
    """Resolve (lat, lng) para município IBGE e devolve stem, bbox e nome.

    Instância única: carrega o shapefile em memória no __init__ e mantém
    um índice `chave_normalizada -> stem_do_arquivo` para os GeoJSONs
    disponíveis no ano corrente.
    """

    def __init__(self):
        # to_crs(4326): força WGS84 (algumas versões IBGE vêm em SIRGAS 2000).
        self._gdf = gpd.read_file(SHAPEFILE_PATH, encoding="utf-8").to_crs(epsg=4326)
        self._nome_col = "NM_MUN"
        self._index = self._build_index()
        self._index = self._build_index()

    def _normalize(self, nome: str) -> str:
        """'Olhos D'Água' -> 'OLHOS_D_AGUA' (bate com o nome de arquivo)."""
        sem_acento = unicodedata.normalize("NFKD", nome)
        sem_acento = "".join(c for c in sem_acento if not unicodedata.combining(c))
        return re.sub(r"[^A-Z0-9]", "_", sem_acento.upper())

    def _build_index(self) -> dict:
        """Mapeia chave_normalizada -> stem completo dos GeoJSONs do ano."""
        ano = str(datetime.now().year)
        index = {}

        for f in GEOJSON_DIR.glob("*.geojson"):
            stem = f.stem
            if stem.endswith(f"_{ano}"):
                chave = stem[: -(len(ano) + 1)]
            else:
                chave = stem
            index[chave] = stem

        return index

    def find(self, lat: float, lng: float) -> str | None:
        """Compat legado: retorna só o stem (sem bbox/display_name)."""
        result = self.find_with_bbox(lat, lng)
        return result[0] if result else None

    def find_with_bbox(
        self, lat: float, lng: float
    ) -> tuple[str, dict, str] | None:
        """Retorna (stem, bbox, display_name) ou None se fora de cobertura."""
        # Ordem intencional: Point(lng, lat) — GeoPandas usa (X, Y).
        pt = Point(lng, lat)
        matches = self._gdf[self._gdf.geometry.contains(pt)]

        if matches.empty:
            print(f"Nenhum município encontrado para ({lat}, {lng})")
            return None

        row = matches.iloc[0]
        nome_raw = str(row[self._nome_col])
        chave    = self._normalize(nome_raw)

        print(f"Município encontrado: '{nome_raw}' → chave: '{chave}'")
        print(f"Chave existe no índice: {chave in self._index}")

        stem = self._index.get(chave)
        if not stem:
            return None

        minx, miny, maxx, maxy = row.geometry.bounds
        bbox = {
            "min_lat": miny,
            "max_lat": maxy,
            "min_lon": minx,
            "max_lon": maxx,
        }
        return stem, bbox, nome_raw
