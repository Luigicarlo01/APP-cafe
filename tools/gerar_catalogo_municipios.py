#!/usr/bin/env python3
"""Gera o catálogo offline sem duplicar as geometrias dos assets de análise.

Usa apenas a biblioteca padrão. Execute na raiz do projeto:
    python3 tools/gerar_catalogo_municipios.py

Os nomes oficiais vêm do DBF IBGE já usado pelo backend. Os limites e o ponto
interior vêm da feature `municipio` de cada GeoJSON distribuído com o app.
"""

import argparse
import json
from pathlib import Path
import re
import struct
import unicodedata


ROOT = Path(__file__).resolve().parents[1]


def normalize_name(name):
    ascii_name = "".join(
        char
        for char in unicodedata.normalize("NFKD", name)
        if not unicodedata.combining(char)
    )
    return re.sub(r"[^A-Z0-9]", "_", ascii_name.upper())


def read_dbf(path):
    data = path.read_bytes()
    count, header_length, record_length = struct.unpack_from("<IHH", data, 4)
    fields = []
    for offset in range(32, header_length - 1, 32):
        descriptor = data[offset : offset + 32]
        if descriptor[0] == 13:
            break
        name = descriptor[:11].split(b"\0")[0].decode("ascii")
        fields.append((name, descriptor[16]))
    for index in range(count):
        offset = header_length + index * record_length
        record = data[offset : offset + record_length]
        if record[0:1] == b"*":
            continue
        row = {}
        offset = 1
        for name, length in fields:
            row[name] = record[offset : offset + length].decode("utf-8").strip()
            offset += length
        yield row


def geometry_polygons(geometry):
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    raise ValueError(f"Geometria municipal não suportada: {geometry['type']}")


def interior_point(polygons):
    """Ponto estritamente interior, respeitando também buracos do polígono.

    A maior seção horizontal entre segmentos dos anéis oferece uma posição
    útil para centralizar a pesquisa, mesmo quando o centro da bbox fica fora.
    """
    best = None
    for polygon in polygons:
        outer = polygon[0]
        ys = sorted({point[1] for point in outer})
        candidates = [(ys[0] + ys[-1]) / 2]
        # Intercalar alturas evita uma seção degenerada em geometrias côncavas.
        for fraction in (0.25, 0.75):
            candidates.append(ys[0] + (ys[-1] - ys[0]) * fraction)
        for y in candidates:
            intersections = []
            for ring in polygon:
                previous = ring[-1]
                for current in ring:
                    x1, y1 = previous[:2]
                    x2, y2 = current[:2]
                    if (y1 > y) != (y2 > y):
                        intersections.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
                    previous = current
            intersections.sort()
            for left, right in zip(intersections[::2], intersections[1::2]):
                if right > left and (best is None or right - left > best[0]):
                    best = (right - left, (left + right) / 2, y)
    if best is None:
        raise ValueError("Não foi possível encontrar ponto interior municipal")
    return [best[1], best[2]]


def generate(year):
    dbf = ROOT / "Data/shapefiles/municipality/BR_Municipios_2021.dbf"
    names = {
        normalize_name(row["NM_MUN"]): row
        for row in read_dbf(dbf)
        if row["SIGLA_UF"] == "MG"
    }
    municipalities = []
    for path in sorted((ROOT / "front_end/assets").glob(f"*_{year}.geojson")):
        key = path.stem[: -len(f"_{year}")]
        row = names[key]
        data = json.loads(path.read_text(encoding="utf-8"))
        boundaries = [
            feature["geometry"]
            for feature in data["features"]
            if feature.get("properties", {}).get("type") == "municipio"
        ]
        if len(boundaries) != 1:
            raise ValueError(f"{path.name}: esperado exatamente um limite municipal")
        polygons = geometry_polygons(boundaries[0])
        positions = [point for polygon in polygons for ring in polygon for point in ring]
        bbox = [
            min(point[0] for point in positions),
            min(point[1] for point in positions),
            max(point[0] for point in positions),
            max(point[1] for point in positions),
        ]
        municipalities.append(
            {
                "code": row["CD_MUN"],
                "name": row["NM_MUN"],
                "asset": f"assets/{path.name}",
                "bbox": bbox,
                "center": interior_point(polygons),
            }
        )
    if not municipalities:
        raise ValueError(f"Nenhum asset de análise encontrado para {year}")
    result = {
        "version": 1,
        "year": year,
        "source": "IBGE BR_Municipios_2021; limites dos GeoJSONs municipais de análise",
        "municipalities": municipalities,
    }
    output = ROOT / f"front_end/assets/municipalities_{year}.json"
    output.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(f"{output.relative_to(ROOT)}: {len(municipalities)} municípios, {output.stat().st_size} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, default=2026)
    generate(parser.parse_args().year)
