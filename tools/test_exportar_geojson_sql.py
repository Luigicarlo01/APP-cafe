"""Execute: python3 -m unittest discover -s tools -p 'test_*.py' -v."""

import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from exportar_geojson_sql import export_sql, geometry_expression, geometry_wkt, sql_text


RING = [[-43.0, -20.0], [-42.0, -20.0], [-42.0, -19.0], [-43.0, -20.0]]


class GeometryTest(unittest.TestCase):
    def test_polygon_preserves_holes_and_precision(self):
        outer = [[-43.1234567890123, -20], [-42, -20], [-42, -19], [-43.1234567890123, -20]]
        hole = [[-42.5, -19.9], [-42.3, -19.9], [-42.3, -19.8], [-42.5, -19.9]]
        wkt, count = geometry_wkt({"type": "Polygon", "coordinates": [outer, hole]})
        self.assertEqual(wkt, "POLYGON((-43.1234567890123 -20,-42 -20,-42 -19,-43.1234567890123 -20),(-42.5 -19.9,-42.3 -19.9,-42.3 -19.8,-42.5 -19.9))")
        self.assertEqual(count, 8)

    def test_multipolygon_preserves_parts(self):
        wkt, count = geometry_wkt({"type": "MultiPolygon", "coordinates": [[RING], [RING]]})
        self.assertEqual(wkt, "MULTIPOLYGON(((-43.0 -20.0,-42.0 -20.0,-42.0 -19.0,-43.0 -20.0)),((-43.0 -20.0,-42.0 -20.0,-42.0 -19.0,-43.0 -20.0)))")
        self.assertEqual(count, 8)

    def test_rejects_open_rings_3d_and_nonfinite_coordinates(self):
        for ring in [RING[:-1], [[1, 2, 3]] * 4, [[float("inf"), 0]] * 4, [[1, 91]] * 4]:
            with self.subTest(ring=ring), self.assertRaises(ValueError):
                geometry_wkt({"type": "Polygon", "coordinates": [ring]})

    def test_dialect_handles_geographic_axis_order(self):
        self.assertEqual(geometry_expression("POINT(-42 -20)", "mysql"), "ST_GeomFromText('POINT(-42 -20)',4326,'axis-order=long-lat')")
        self.assertEqual(geometry_expression("POINT(-42 -20)", "mariadb"), "ST_GeomFromText('POINT(-42 -20)',4326)")

    def test_strings_are_safe_under_any_backslash_mode(self):
        value = "Olhos-d'Água\\teste\n'); DROP TABLE x; --"
        expression = sql_text(value)
        self.assertEqual(expression, "CONVERT(X'" + value.encode().hex() + "' USING utf8mb4)")
        self.assertNotIn("DROP", expression)


class ExportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "VICOSA_2026.geojson"
        (self.root / "municipalities_2026.json").write_text(json.dumps({"year": 2026, "municipalities": [{"code": "3171303", "name": "Viçosa", "asset": "assets/VICOSA_2026.geojson"}]}))
        self.props = {"type": "grid", "winner": "Topázio", "alternatives": ["Catiguá MG2", "MGS Epamig 1194"]}
        self.data = {"type": "FeatureCollection", "name": "VICOSA_2026", "features": [
            {"type": "Feature", "properties": {"type": "municipio", "winner": None, "alternatives": []}, "geometry": {"type": "MultiPolygon", "coordinates": [[RING]]}},
            {"type": "Feature", "id": "pixel original", "properties": self.props, "geometry": {"type": "Polygon", "coordinates": [RING]}},
            {"type": "Feature", "properties": self.props, "geometry": {"type": "Polygon", "coordinates": [RING]}},
        ]}
        self.save()

    def save(self):
        self.source.write_text(json.dumps(self.data, ensure_ascii=False))

    def test_gzip_counts_checksums_deduplication_and_ranking_order(self):
        output = self.root / "output.sql.gz"
        report = export_sql(self.root, output)
        sql = gzip.decompress(output.read_bytes()).decode()
        self.assertEqual((report["municipalities"], report["pixels"], report["boundaries"], report["property_sets"], report["ranking_items"]), (1, 2, 1, 2, 3))
        self.assertEqual(report["sha256"], hashlib.sha256(output.read_bytes()).hexdigest())
        self.assertEqual(report["sources"][0]["sha256"], hashlib.sha256(self.source.read_bytes()).hexdigest())
        items = "INSERT INTO cultivar_ranking_itens VALUES " + ",".join(f"(2,{i},{sql_text(name)})" for i, name in enumerate(["Topázio", "Catiguá MG2", "MGS Epamig 1194"], 1))
        self.assertIn(items, sql)
        self.assertIn(sql_text('{"id":"pixel original"}'), sql)
        self.assertIn("geometria GEOMETRY NOT NULL SRID 4326", sql)
        self.assertNotIn("DROP TABLE", sql)
        self.assertNotIn("USE ", sql)
        self.assertIn("COMMIT;", sql)
        self.assertEqual(json.loads(Path(str(output) + ".manifest.json").read_text()), report)

    def test_mariadb_output_and_selection(self):
        output = self.root / "maria.sql"
        export_sql(self.root, output, dialect="mariadb", municipalities=["VICOSA"])
        sql = output.read_text()
        self.assertNotIn("axis-order", sql)
        self.assertNotIn("NOT NULL SRID", sql)
        self.assertIn("SPATIAL KEY", sql)

    def test_rejects_unknown_crs_without_publishing_partial_dump(self):
        self.data["crs"] = {"properties": {"name": "EPSG:3857"}}
        self.save()
        output = self.root / "bad.sql.gz"
        with self.assertRaisesRegex(ValueError, "CRS"):
            export_sql(self.root, output)
        self.assertFalse(output.exists())
        self.assertFalse(list(self.root.glob(".cultivar-sql-*")))

    def test_refuses_overwrite_and_missing_selection(self):
        output = self.root / "existing.sql"
        output.write_text("preservar")
        with self.assertRaises(FileExistsError):
            export_sql(self.root, output)
        self.assertEqual(output.read_text(), "preservar")
        with self.assertRaisesRegex(ValueError, "não encontrados"):
            export_sql(self.root, self.root / "missing.sql", municipalities=["INEXISTENTE"])


if __name__ == "__main__":
    unittest.main()
