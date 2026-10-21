#!/usr/bin/env python3
"""Exporta os resultados GeoJSON para MySQL 8.0+ ou MariaDB 10.6+.

Usa somente a biblioteca padrão. Não conecta a servidores nem altera o app.
Importe o resultado em um banco vazio; consulte docs/14-importar-geojson-sql.md.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SUPPORTED_CRS = {
    "urn:ogc:def:crs:OGC:1.3:CRS84",
    "urn:ogc:def:crs:EPSG::4326",
    "EPSG:4326",
}


def compact_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def sql_text(value):
    """Hexadecimal UTF-8 evita depender de sql_mode e de escapes de strings."""
    if value is None:
        return "NULL"
    return "CONVERT(X'" + value.encode("utf-8").hex() + "' USING utf8mb4)"


def geometry_wkt(geometry):
    """Conserva todas as partes, buracos e precisão double; não simplifica."""
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if kind not in ("Polygon", "MultiPolygon") or not isinstance(coordinates, list):
        raise ValueError(f"Geometria não suportada: {kind}")
    if set(geometry) - {"type", "coordinates"}:
        raise ValueError("Geometria com atributos adicionais; conversão interrompida para não perdê-los")
    polygons = [coordinates] if kind == "Polygon" else coordinates
    if not polygons:
        raise ValueError("Geometria vazia")
    result = []
    vertices = 0
    for polygon in polygons:
        if not isinstance(polygon, list) or not polygon:
            raise ValueError("Polígono sem anéis")
        rings = []
        for ring in polygon:
            if not isinstance(ring, list) or len(ring) < 4 or ring[0] != ring[-1]:
                raise ValueError("Anel deve ser fechado e conter pelo menos quatro posições")
            points = []
            for point in ring:
                if not isinstance(point, list) or len(point) != 2:
                    raise ValueError("Esperadas coordenadas 2D [longitude, latitude]")
                if any(isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) for n in point):
                    raise ValueError("Coordenada não numérica ou não finita")
                lon, lat = point
                if not -180 < lon <= 180 or not -90 <= lat <= 90:
                    raise ValueError("Coordenada fora dos limites WGS84")
                points.append(f"{lon!r} {lat!r}")
                vertices += 1
            rings.append("(" + ",".join(points) + ")")
        result.append("(" + ",".join(rings) + ")")
    body = result[0] if kind == "Polygon" else "(" + ",".join(result) + ")"
    return kind.upper() + body, vertices


def geometry_expression(wkt, dialect):
    # EPSG:4326 no MySQL usa latitude/longitude por padrão. O GeoJSON usa lon/lat.
    options = ",'axis-order=long-lat'" if dialect == "mysql" else ""
    return f"ST_GeomFromText('{wkt}',4326{options})"


def schema(dialect):
    srid = " SRID 4326" if dialect == "mysql" else ""
    return f"""-- Cultivar: importar em um banco vazio; sem DROP, CREATE DATABASE ou USE.
-- Dialeto: {dialect}; geometrias WGS84, coordenadas de origem longitude/latitude.
SET NAMES utf8mb4;
CREATE TABLE cultivar_municipios (
  codigo CHAR(7) PRIMARY KEY,
  nome VARCHAR(255) NOT NULL,
  uf CHAR(2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
CREATE TABLE cultivar_arquivos (
  id INT UNSIGNED PRIMARY KEY,
  municipio_codigo CHAR(7) NOT NULL,
  ano SMALLINT UNSIGNED NOT NULL,
  arquivo VARCHAR(255) NOT NULL UNIQUE,
  cabecalho_json JSON NOT NULL,
  sha256 CHAR(64) NOT NULL,
  total_feicoes INT UNSIGNED NOT NULL,
  UNIQUE KEY municipio_ano (municipio_codigo,ano),
  FOREIGN KEY (municipio_codigo) REFERENCES cultivar_municipios(codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
CREATE TABLE cultivar_rankings (
  id INT UNSIGNED PRIMARY KEY,
  vencedor VARCHAR(255) NULL,
  propriedades_json JSON NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
CREATE TABLE cultivar_ranking_itens (
  ranking_id INT UNSIGNED NOT NULL,
  posicao SMALLINT UNSIGNED NOT NULL,
  cultivar VARCHAR(255) NOT NULL,
  PRIMARY KEY (ranking_id,posicao),
  FOREIGN KEY (ranking_id) REFERENCES cultivar_rankings(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
CREATE TABLE cultivar_feicoes (
  id BIGINT UNSIGNED PRIMARY KEY,
  arquivo_id INT UNSIGNED NOT NULL,
  indice INT UNSIGNED NOT NULL,
  tipo VARCHAR(16) NOT NULL,
  ranking_id INT UNSIGNED NOT NULL,
  geometria GEOMETRY NOT NULL{srid},
  atributos_json JSON NOT NULL,
  UNIQUE KEY arquivo_indice (arquivo_id,indice),
  KEY arquivo_tipo (arquivo_id,tipo),
  SPATIAL KEY geometria_espacial (geometria),
  FOREIGN KEY (arquivo_id) REFERENCES cultivar_arquivos(id),
  FOREIGN KEY (ranking_id) REFERENCES cultivar_rankings(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
"""


class InsertBatch:
    """Limita INSERTs a cerca de 512 KiB, permitindo uma geometria maior isolada."""

    def __init__(self, stream, table, columns, limit=512 * 1024):
        self.stream = stream
        self.prefix = f"INSERT INTO {table} ({columns}) VALUES\n"
        self.limit = limit
        self.rows = []
        self.size = len(self.prefix)
        self.max_bytes = 0

    def add(self, row):
        if self.rows and self.size + len(row) + 3 > self.limit:
            self.flush()
        self.rows.append(row)
        self.size += len(row) + 2

    def flush(self):
        if self.rows:
            statement = self.prefix + ",\n".join(self.rows) + ";\n"
            self.stream.write(statement)
            self.max_bytes = max(self.max_bytes, len(statement.encode("utf-8")))
            self.rows = []
            self.size = len(self.prefix)


def validate_properties(properties):
    if not isinstance(properties, dict) or properties.get("type") not in ("grid", "municipio"):
        raise ValueError("Esperadas propriedades de feature 'grid' ou 'municipio'")
    winner = properties.get("winner")
    alternatives = properties.get("alternatives")
    if winner is not None and (not isinstance(winner, str) or not winner or len(winner) > 255):
        raise ValueError("Vencedor inválido")
    if not isinstance(alternatives, list) or any(not isinstance(s, str) or not s or len(s) > 255 for s in alternatives):
        raise ValueError("Lista de alternativas inválida")
    if properties["type"] == "grid" and winner is None:
        raise ValueError("Pixel sem cultivar vencedora")
    names = ([winner] if winner is not None else []) + alternatives
    if len(names) > 65535:
        raise ValueError("Ranking excede 65535 posições")
    return names


def write_dump(stream, paths, catalog, year, dialect):
    stream.write(schema(dialect))
    rankings = {}
    municipalities = set()
    counts = Counter()
    sources = []
    max_statement = 0
    feature_id = 0
    for file_id, path in enumerate(paths, 1):
        try:
            raw = path.read_bytes()
            data = json.loads(raw)
            if data.get("type") != "FeatureCollection" or not isinstance(data.get("features"), list):
                raise ValueError("Esperada uma FeatureCollection")
            crs = data.get("crs")
            if crs and crs.get("properties", {}).get("name") not in SUPPORTED_CRS:
                raise ValueError(f"CRS não suportado: {crs}")
            municipality = catalog[path.name]
            code = municipality["code"]
            if len(code) != 7 or not code.isdigit() or not code.startswith("31"):
                raise ValueError(f"Código de município mineiro inválido: {code}")
            if code in municipalities:
                raise ValueError(f"Município duplicado: {code}")
            municipalities.add(code)
            header = {key: value for key, value in data.items() if key != "features"}
            source = {"file": path.name, "sha256": hashlib.sha256(raw).hexdigest(), "features": len(data["features"])}
            sources.append(source)
            stream.write("START TRANSACTION;\n")
            stream.write(f"INSERT INTO cultivar_municipios VALUES ({sql_text(code)},{sql_text(municipality['name'])},'MG');\n")
            stream.write(f"INSERT INTO cultivar_arquivos VALUES ({file_id},{sql_text(code)},{year},{sql_text(path.name)},{sql_text(compact_json(header))},'{source['sha256']}',{source['features']});\n")
            batch = InsertBatch(stream, "cultivar_feicoes", "id,arquivo_id,indice,tipo,ranking_id,geometria,atributos_json")
            boundaries = 0
            for index, feature in enumerate(data["features"]):
                if feature.get("type") != "Feature":
                    raise ValueError(f"Feature {index}: tipo inválido")
                properties = feature.get("properties")
                names = validate_properties(properties)
                key = json.dumps(properties, sort_keys=True, ensure_ascii=False, allow_nan=False)
                if key not in rankings:
                    ranking_id = len(rankings) + 1
                    rankings[key] = ranking_id
                    stream.write(f"INSERT INTO cultivar_rankings VALUES ({ranking_id},{sql_text(properties.get('winner'))},{sql_text(compact_json(properties))});\n")
                    if names:
                        rows = [f"({ranking_id},{pos},{sql_text(name)})" for pos, name in enumerate(names, 1)]
                        stream.write("INSERT INTO cultivar_ranking_itens VALUES " + ",".join(rows) + ";\n")
                        counts["ranking_items"] += len(names)
                feature_id += 1
                wkt, vertices = geometry_wkt(feature["geometry"])
                counts["vertices"] += vertices
                kind = properties["type"]
                counts[kind] += 1
                boundaries += kind == "municipio"
                extra = {k: v for k, v in feature.items() if k not in ("type", "properties", "geometry")}
                batch.add(f"({feature_id},{file_id},{index},'{kind}',{rankings[key]},{geometry_expression(wkt, dialect)},{sql_text(compact_json(extra))})")
            if boundaries != 1:
                raise ValueError(f"Esperado um limite municipal; encontrados {boundaries}")
            batch.flush()
            max_statement = max(max_statement, batch.max_bytes)
            stream.write("COMMIT;\n")
        except (ValueError, KeyError, TypeError) as exc:
            raise ValueError(f"{path.name}: {exc}") from exc
    stream.write(f"-- Fim: {len(paths)} arquivos, {feature_id} feições, {len(rankings)} conjuntos de propriedades.\n")
    return {
        "municipalities": len(municipalities), "features": feature_id,
        "pixels": counts["grid"], "boundaries": counts["municipio"],
        "vertices": counts["vertices"], "property_sets": len(rankings),
        "ranking_items": counts["ranking_items"],
        "max_feature_insert_bytes": max_statement, "sources": sources,
    }


def export_sql(assets_dir, output, year=2026, dialect="mysql", municipalities=None):
    assets_dir, output = Path(assets_dir), Path(output)
    if dialect not in ("mysql", "mariadb"):
        raise ValueError("Dialeto deve ser mysql ou mariadb")
    if not 1 <= year <= 65535:
        raise ValueError("Ano inválido")
    if not (output.name.endswith(".sql") or output.name.endswith(".sql.gz")):
        raise ValueError("O arquivo de saída deve terminar em .sql ou .sql.gz")
    manifest_path = output.with_name(output.name + ".manifest.json")
    if output.exists() or manifest_path.exists():
        raise FileExistsError(f"A saída já existe: {output}; escolha outro nome")
    catalog_data = json.loads((assets_dir / f"municipalities_{year}.json").read_text(encoding="utf-8"))
    if catalog_data["year"] != year:
        raise ValueError("Ano do catálogo diferente do ano solicitado")
    catalog = {Path(m["asset"]).name: m for m in catalog_data["municipalities"]}
    paths = sorted(assets_dir.glob(f"*_{year}.geojson"))
    if municipalities:
        selected = {f"{name}_{year}.geojson" for name in municipalities}
        available = {path.name for path in paths}
        if selected - available:
            raise ValueError("Municípios não encontrados: " + ", ".join(sorted(selected - available)))
        paths = [path for path in paths if path.name in selected]
    if not paths:
        raise ValueError("Nenhum GeoJSON municipal encontrado")
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".cultivar-sql-", dir=output.parent)
    os.close(fd)
    temporary = Path(temp_name)
    try:
        opener = gzip.open if output.name.endswith(".gz") else open
        with opener(temporary, "wt", encoding="utf-8", newline="\n") as stream:
            report = write_dump(stream, paths, catalog, year, dialect)
        digest = hashlib.sha256()
        with temporary.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        report.update({
            "schema_version": 1, "dialect": dialect, "year": year,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "file": output.name, "bytes": temporary.stat().st_size,
            "sha256": digest.hexdigest(), "srid": 4326,
        })
        os.replace(temporary, output)
        manifest_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return report
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-dir", type=Path, default=ROOT / "front_end/assets")
    parser.add_argument("--year", type=int, default=2026)
    parser.add_argument("--dialect", choices=("mysql", "mariadb"), default="mysql")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--municipios", nargs="+", help="Chaves dos arquivos, por exemplo VICOSA ESMERALDAS")
    args = parser.parse_args()
    output = args.output or ROOT / f"exports/sql/cultivar_{args.year}_{args.dialect}.sql.gz"
    try:
        report = export_sql(args.assets_dir, output, args.year, args.dialect, args.municipios)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        parser.exit(1, f"Erro: {exc}\n")
    print(f"Arquivo: {output}")
    print(f"Municípios: {report['municipalities']}; pixels: {report['pixels']}; limites: {report['boundaries']}")
    print(f"Tamanho: {report['bytes'] / 1_000_000:.2f} MB; SHA-256: {report['sha256']}")
    print(f"Relatório: {output.name}.manifest.json")


if __name__ == "__main__":
    main()
