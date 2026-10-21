#!/usr/bin/env python3
"""Cria o banco offline do APK a partir da exportação SQL do Cultivar.

Aceita o formato de tools/exportar_geojson_sql.py (MySQL ou MariaDB), não
dumps SQL arbitrários. Não lê os GeoJSONs e não conecta ao servidor.
As tabelas e as posições dos rankings são preservadas; geometrias viram WKB.
"""

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import struct
import tempfile

from gerar_catalogo_municipios import interior_point


ROOT = Path(__file__).resolve().parents[1]
TABLES = {
    "cultivar_municipios", "cultivar_arquivos", "cultivar_rankings",
    "cultivar_ranking_itens", "cultivar_feicoes",
}
SCHEMA = """
PRAGMA user_version=1;
PRAGMA foreign_keys=ON;
CREATE TABLE cultivar_municipios (codigo TEXT PRIMARY KEY, nome TEXT NOT NULL, uf TEXT NOT NULL);
CREATE TABLE cultivar_arquivos (
 id INTEGER PRIMARY KEY, municipio_codigo TEXT NOT NULL REFERENCES cultivar_municipios(codigo),
 ano INTEGER NOT NULL, arquivo TEXT NOT NULL UNIQUE, cabecalho_json TEXT NOT NULL,
 sha256 TEXT NOT NULL, total_feicoes INTEGER NOT NULL,
 UNIQUE(municipio_codigo,ano));
CREATE TABLE cultivar_rankings (id INTEGER PRIMARY KEY, vencedor TEXT, propriedades_json TEXT NOT NULL);
CREATE TABLE cultivar_ranking_itens (
 ranking_id INTEGER NOT NULL REFERENCES cultivar_rankings(id), posicao INTEGER NOT NULL,
 cultivar TEXT NOT NULL, PRIMARY KEY(ranking_id,posicao));
CREATE TABLE cultivar_feicoes (
 id INTEGER PRIMARY KEY, arquivo_id INTEGER NOT NULL REFERENCES cultivar_arquivos(id),
 indice INTEGER NOT NULL, tipo TEXT NOT NULL,
 ranking_id INTEGER NOT NULL REFERENCES cultivar_rankings(id), geometria BLOB NOT NULL,
 atributos_json TEXT NOT NULL, UNIQUE(arquivo_id,indice));
CREATE TABLE cultivar_metadata (chave TEXT PRIMARY KEY, valor TEXT NOT NULL);
"""
HEX_TEXT = re.compile(r"CONVERT\(X'([0-9a-fA-F]*)' USING utf8mb4\)")
NUMBER = r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
POINT = re.compile(rf"({NUMBER})\s+({NUMBER})")


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def wkt_geometry(wkt):
    kind, separator, body = wkt.partition("(")
    if not separator or kind not in ("POLYGON", "MULTIPOLYGON"):
        raise ValueError("Esperado POLYGON ou MULTIPOLYGON WKT")
    text = POINT.sub(r"[\1,\2]", "(" + body).replace("(", "[").replace(")", "]")
    coordinates = json.loads(text)
    return {"type": "Polygon" if kind == "POLYGON" else "MultiPolygon", "coordinates": coordinates}


def geometry_wkb(geometry):
    def polygon(rings):
        if not rings:
            raise ValueError("Polígono vazio")
        result = [struct.pack("<BII", 1, 3, len(rings))]
        for ring in rings:
            if len(ring) < 4 or ring[0] != ring[-1]:
                raise ValueError("Anel não fechado")
            if any(len(point) != 2 or not -180 < point[0] <= 180 or not -90 <= point[1] <= 90 for point in ring):
                raise ValueError("Coordenadas WGS84 2D inválidas")
            result.append(struct.pack("<I", len(ring)))
            result.append(struct.pack("<" + "d" * (2 * len(ring)), *(n for point in ring for n in point)))
        return b"".join(result)
    if geometry["type"] == "Polygon":
        return polygon(geometry["coordinates"])
    polygons = geometry["coordinates"]
    return struct.pack("<BII", 1, 6, len(polygons)) + b"".join(polygon(p) for p in polygons)


def wkb_geometry(raw):
    offset = 0
    def read(fmt):
        nonlocal offset
        result = struct.unpack_from(fmt, raw, offset)
        offset += struct.calcsize(fmt)
        return result
    def geometry():
        endian = "<" if read("B")[0] == 1 else ">"
        kind = read(endian + "I")[0]
        count = read(endian + "I")[0]
        if kind == 6:
            return {"type": "MultiPolygon", "coordinates": [geometry()["coordinates"] for _ in range(count)]}
        if kind != 3:
            raise ValueError("WKB não poligonal")
        rings = []
        for _ in range(count):
            points = read(endian + "I")[0]
            rings.append([list(read(endian + "dd")) for _ in range(points)])
        return {"type": "Polygon", "coordinates": rings}
    result = geometry()
    if offset != len(raw):
        raise ValueError("Bytes adicionais no WKB")
    return result


def statements(path):
    opener = gzip.open if str(path).endswith(".gz") else open
    buffer = []
    with opener(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            if not buffer and (not line.strip() or line.startswith("--")):
                continue
            buffer.append(line)
            if line.rstrip().endswith(";"):
                yield "".join(buffer).strip()
                buffer = []
    if buffer:
        raise ValueError("SQL incompleto")


def import_sql(connection, source):
    def from_text(wkt, srid, *options):
        if srid != 4326 or (options and options != ("axis-order=long-lat",)):
            raise ValueError("Esperadas coordenadas WGS84 em longitude/latitude")
        return geometry_wkb(wkt_geometry(wkt))
    connection.create_function("ST_GeomFromText", -1, from_text)
    inserted_tables = set()
    for statement in statements(source):
        if statement in ("SET NAMES utf8mb4;", "START TRANSACTION;", "COMMIT;"):
            continue
        match = re.match(r"CREATE TABLE (\w+) \(", statement)
        if match:
            if match[1] not in TABLES:
                raise ValueError("Tabela não reconhecida no SQL")
            continue
        match = re.match(r"INSERT INTO (\w+)(?: |\()", statement)
        if not match or match[1] not in TABLES:
            raise ValueError(f"Comando SQL não suportado: {statement[:80]}")
        connection.execute(HEX_TEXT.sub(r"CAST(X'\1' AS TEXT)", statement))
        inserted_tables.add(match[1])
    if inserted_tables != TABLES:
        raise ValueError("A exportação não contém todas as tabelas do Cultivar")


def add_catalog(connection):
    fields = ("min_lon", "min_lat", "max_lon", "max_lat", "centro_lon", "centro_lat")
    for field in fields:
        connection.execute(f"ALTER TABLE cultivar_arquivos ADD COLUMN {field} REAL")
    count = 0
    for file_id, raw in connection.execute("SELECT arquivo_id,geometria FROM cultivar_feicoes WHERE tipo='municipio' ORDER BY arquivo_id"):
        geometry = wkb_geometry(raw)
        polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
        points = [p for polygon in polygons for ring in polygon for p in ring]
        bbox = [min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points)]
        center = interior_point(polygons)
        connection.execute("UPDATE cultivar_arquivos SET min_lon=?,min_lat=?,max_lon=?,max_lat=?,centro_lon=?,centro_lat=? WHERE id=?", [*bbox, *center, file_id])
        count += 1
    return count


def validate(connection, expected=None):
    result = {
        "municipalities": connection.execute("SELECT COUNT(*) FROM cultivar_municipios").fetchone()[0],
        "features": connection.execute("SELECT COUNT(*) FROM cultivar_feicoes").fetchone()[0],
        "pixels": connection.execute("SELECT COUNT(*) FROM cultivar_feicoes WHERE tipo='grid'").fetchone()[0],
        "boundaries": connection.execute("SELECT COUNT(*) FROM cultivar_feicoes WHERE tipo='municipio'").fetchone()[0],
        "property_sets": connection.execute("SELECT COUNT(*) FROM cultivar_rankings").fetchone()[0],
        "ranking_items": connection.execute("SELECT COUNT(*) FROM cultivar_ranking_itens").fetchone()[0],
    }
    if expected:
        for key, value in result.items():
            if expected[key] != value:
                raise ValueError(f"Contagem divergente em {key}: {value} != {expected[key]}")
    for ranking_id, raw in connection.execute("SELECT id,propriedades_json FROM cultivar_rankings"):
        props = json.loads(raw)
        names = ([props["winner"]] if props.get("winner") else []) + props["alternatives"]
        actual = [r[0] for r in connection.execute("SELECT cultivar FROM cultivar_ranking_itens WHERE ranking_id=? ORDER BY posicao", [ranking_id])]
        if actual != names:
            raise ValueError(f"Ordem do ranking {ranking_id} divergente")
    if connection.execute("PRAGMA foreign_key_check").fetchone() is not None:
        raise ValueError("Chaves estrangeiras inválidas")
    if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise ValueError("SQLite inválido")
    return result


def build(source, output, asset_output=None):
    source, output = Path(source), Path(output)
    asset_output = Path(asset_output) if asset_output else None
    targets = [output, Path(str(output) + ".manifest.json")]
    if asset_output:
        targets += [asset_output, asset_output.with_name("manifest.json")]
    if any(path.exists() for path in targets):
        raise FileExistsError("Uma saída já existe; escolha novos caminhos para preservar a anterior")
    source_sha = file_sha256(source)
    source_manifest = Path(str(source) + ".manifest.json")
    expected = json.loads(source_manifest.read_text()) if source_manifest.exists() else None
    if expected and expected["sha256"] != source_sha:
        raise ValueError("SHA-256 da exportação SQL divergente")
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=".cultivar-", suffix=".sqlite", dir=output.parent)
    os.close(fd)
    temporary = Path(temporary_name)
    connection = sqlite3.connect(temporary)
    try:
        connection.executescript(SCHEMA)
        connection.execute("BEGIN")
        import_sql(connection, source)
        connection.execute("CREATE INDEX feicoes_arquivo_tipo ON cultivar_feicoes(arquivo_id,tipo,indice)")
        count = add_catalog(connection)
        if count != connection.execute("SELECT COUNT(*) FROM cultivar_arquivos").fetchone()[0]:
            raise ValueError("Cada arquivo deve ter exatamente um limite municipal")
        metadata = {"schema_version": "1", "format": "cultivar-sqlite-wkb-v1", "source_sql_sha256": source_sha}
        connection.executemany("INSERT INTO cultivar_metadata VALUES (?,?)", metadata.items())
        connection.commit()
        report = validate(connection, expected)
        connection.execute("VACUUM")
        connection.close()
        report.update({"schema_version": 1, "format": metadata["format"], "source_sql": source.name,
                       "source_sql_sha256": source_sha, "database_sha256": file_sha256(temporary),
                       "database_bytes": temporary.stat().st_size, "created_at": datetime.now(timezone.utc).isoformat()})
        os.replace(temporary, output)
        if asset_output:
            asset_output.parent.mkdir(parents=True, exist_ok=True)
            with output.open("rb") as source_stream, gzip.open(asset_output, "wb", compresslevel=9) as dest:
                for block in iter(lambda: source_stream.read(1024 * 1024), b""):
                    dest.write(block)
            try:
                report["asset"] = asset_output.resolve().relative_to((ROOT / "front_end").resolve()).as_posix()
            except ValueError:
                # Saída fora do app (ex.: testes); o chamador escolhe onde copiar.
                report["asset"] = "assets/data/" + asset_output.name
            report["compressed_bytes"] = asset_output.stat().st_size
            report["compressed_sha256"] = file_sha256(asset_output)
            asset_output.with_name("manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        Path(str(output) + ".manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return report
    finally:
        connection.close()
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "exports/sql/cultivar_2026_mysql.sql.gz")
    parser.add_argument("--output", type=Path, default=ROOT / "exports/sqlite/cultivar_2026.sqlite")
    parser.add_argument("--asset-output", type=Path, default=ROOT / "front_end/assets/data/cultivar_2026.sqlite.gz")
    args = parser.parse_args()
    try:
        report = build(args.input, args.output, args.asset_output)
    except (OSError, ValueError, sqlite3.Error) as exc:
        parser.exit(1, f"Erro: {exc}\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
