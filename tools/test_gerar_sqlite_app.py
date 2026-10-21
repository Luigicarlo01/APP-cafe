import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from exportar_geojson_sql import export_sql
from gerar_sqlite_app import build, geometry_wkb, wkb_geometry, wkt_geometry


class SqliteAppTest(unittest.TestCase):
    def test_wkb_roundtrip_preserves_parts_holes_and_double_precision(self):
        geometry = wkt_geometry('MULTIPOLYGON(((-43.1234567890123 -20,-42 -20,-42 -19,-43.1234567890123 -20),(-42.8 -19.8,-42.7 -19.8,-42.7 -19.7,-42.8 -19.8)),((-41 -20,-40 -20,-40 -19,-41 -20)))')
        self.assertEqual(wkb_geometry(geometry_wkb(geometry)), geometry)
        self.assertEqual(geometry['coordinates'][0][0][0], [-43.1234567890123, -20])
        self.assertEqual(len(geometry['coordinates']), 2)
        self.assertEqual(len(geometry['coordinates'][0]), 2)

    def test_both_sql_dialects_become_equivalent_sqlite_without_geojson_sources(self):
        for dialect in ['mysql', 'mariadb']:
            with self.subTest(dialect=dialect), tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)
                ring = [[-43.0,-20.0],[-42.0,-20.0],[-42.0,-19.0],[-43.0,-20.0]]
                props = {'type':'grid','winner':'Topázio MG 1190','alternatives':['Catiguá MG2',"Olhos-d'Água"]}
                features = [
                    {'type':'Feature','properties':{'type':'municipio','winner':None,'alternatives':[]},'geometry':{'type':'Polygon','coordinates':[ring]}},
                    {'type':'Feature','properties':props,'geometry':{'type':'MultiPolygon','coordinates':[[ring]]}},
                ]
                geojson = base/'VICOSA_2026.geojson'
                geojson.write_text(json.dumps({'type':'FeatureCollection','features':features}))
                (base/'municipalities_2026.json').write_text(json.dumps({'year':2026,'municipalities':[{'code':'3171303','name':'Viçosa','asset':'assets/VICOSA_2026.geojson'}]}))
                sql = base/'input.sql.gz'
                export_sql(base, sql, dialect=dialect)
                # A fonte desta etapa é somente a exportação SQL, em outra pasta.
                mobile = base/'mobile'
                result = build(sql, mobile/'data.sqlite', mobile/'data.sqlite.gz')
                self.assertEqual((result['municipalities'],result['pixels'],result['boundaries']), (1,1,1))
                self.assertEqual(result['source_sql_sha256'], hashlib.sha256(sql.read_bytes()).hexdigest())
                self.assertEqual(gzip.decompress((mobile/'data.sqlite.gz').read_bytes()), (mobile/'data.sqlite').read_bytes())
                with sqlite3.connect(mobile/'data.sqlite') as db:
                    names = [r[0] for r in db.execute('SELECT cultivar FROM cultivar_ranking_itens WHERE ranking_id=2 ORDER BY posicao')]
                    self.assertEqual(names, [props['winner'],*props['alternatives']])
                    raw = db.execute("SELECT geometria FROM cultivar_feicoes WHERE tipo='grid'").fetchone()[0]
                    self.assertEqual(wkb_geometry(raw), features[1]['geometry'])
                    self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
                    self.assertEqual(db.execute('SELECT nome FROM cultivar_municipios').fetchone()[0], 'Viçosa')
                self.assertTrue(geojson.exists())
                with self.assertRaises(FileExistsError):
                    build(sql, mobile/'data.sqlite')

    def test_rejects_unrecognized_sql_commands(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'bad.sql'
            source.write_text('DROP TABLE cultivar_feicoes;\n')
            output=Path(tmp)/'output.sqlite'
            with self.assertRaisesRegex(ValueError,'não suportado'):
                build(source, output)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
