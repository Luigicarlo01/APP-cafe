import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_end/services/analysis_service.dart';
import 'package:front_end/services/cultivar_database.dart';
import 'package:front_end/services/local_municipality_service.dart';
import 'package:front_end/utils/polygon_wkb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  late _SqlAssets bundle;
  late CultivarDatabase database;

  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('cultivar-db-integration-');
    bundle = _SqlAssets();
    database = CultivarDatabase(
      bundle: bundle,
      storageDirectory: () async => storage,
    );
    await Future.wait([database.ready(), database.ready(), database.ready()]);
  });

  tearDownAll(() async {
    await database.close();
    await storage.delete(recursive: true);
  });

  test(
    'catálogo e limites SQL cobrem municípios reais sem abrir GeoJSONs',
    () async {
      final service = LocalMunicipalityService(database: database);
      expect(await service.getMunicipalities(), hasLength(853));
      for (final name in [
        'Viçosa',
        'Belo Horizonte',
        'Uberlândia',
        "Olhos-d'Água",
      ]) {
        final municipality = (await service.findByName(name))!;
        expect(
          (await service.findByCoordinates(
            lat: municipality.latitude,
            lng: municipality.longitude,
          ))?.code,
          municipality.code,
        );
      }
      expect(
        (await service.findByCoordinates(lat: -20.7549, lng: -42.8795))?.name,
        'Viçosa',
      );
      expect(
        await service.findByCoordinates(lat: -23.5505, lng: -46.6333),
        isNull,
      );
      expect(bundle.loaded.where((key) => key.endsWith('.geojson')), isEmpty);
      expect(
        bundle.loaded.where((key) => key.endsWith('.sqlite.gz')),
        hasLength(1),
      );
    },
  );

  test(
    'geometrias e rankings recuperados do SQL coincidem com a origem',
    () async {
      for (final name in ['VICOSA', 'ESMERALDAS', 'OLHOS_D_AGUA']) {
        final expected =
            jsonDecode(await File('assets/${name}_2026.geojson').readAsString())
                as Map<String, dynamic>;
        final grids = (expected['features'] as List)
            .where((f) => f['properties']['type'] == 'grid')
            .toList();
        final region = await database.region('assets/${name}_2026.geojson');
        final rows = region['features'] as List<Map<String, Object?>>;
        final rankings = region['rankings'] as Map<int, Map<String, dynamic>>;
        expect(rows, hasLength(grids.length));
        for (final index in [0, rows.length ~/ 2, rows.length - 1]) {
          expect(
            polygonGeometryFromWkb(rows[index]['geometria'] as Uint8List),
            grids[index]['geometry'],
          );
          expect(
            rankings[rows[index]['ranking_id']],
            grids[index]['properties'],
          );
        }
        final boundary = (expected['features'] as List).firstWhere(
          (f) => f['properties']['type'] == 'municipio',
        );
        expect(
          polygonGeometryFromWkb(
            await database.boundary('assets/${name}_2026.geojson'),
          ),
          boundary['geometry'],
        );
      }
      expect(bundle.loaded.where((key) => key.endsWith('.geojson')), isEmpty);
    },
  );

  test(
    'pixel respeita buracos sem considerar área interna como recomendada',
    () {
      final cell = GridCell(
        points: const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
        ],
        holes: const [
          [Offset(4, 4), Offset(6, 4), Offset(6, 6), Offset(4, 6)],
        ],
        winner: 'A',
      );
      expect(cell.containsPoint(const Offset(2, 2)), isTrue);
      expect(cell.containsPoint(const Offset(5, 5)), isFalse);
      expect(cell.containsPoint(const Offset(12, 12)), isFalse);
    },
  );

  test('WKB inválido é rejeitado antes de alocar anéis ou pontos', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([1, 3, 0, 0, 0, 255, 255, 255, 255]),
    ]) {
      expect(() => polygonGeometryFromWkb(bytes), throwsFormatException);
    }
  });

  test(
    'pacote corrompido não vira banco definitivo e permite tentar outra vez',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cultivar-bad-package-',
      );
      final invalid = _InvalidAssets();
      final broken = CultivarDatabase(
        bundle: invalid,
        storageDirectory: () async => directory,
      );
      try {
        await expectLater(broken.ready(), throwsFormatException);
        await expectLater(broken.ready(), throwsFormatException);
        expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
        expect(invalid.manifestReads, 2);
      } finally {
        await broken.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'reabrir reutiliza banco instalado e consultas não alteram seu conteúdo',
    () async {
      await database.close();
      final reopened = CultivarDatabase(
        bundle: bundle,
        storageDirectory: () async => storage,
      );
      try {
        await reopened.ready();
        expect(await reopened.municipalities(2026), hasLength(853));
        expect(
          bundle.loaded.where((key) => key.endsWith('.sqlite.gz')),
          hasLength(1),
        );
        final installed = storage
            .listSync(recursive: true)
            .whereType<File>()
            .single;
        final expected = jsonDecode(
          await rootBundle.loadString(CultivarDatabase.manifestAsset),
        );
        expect(
          (await sha256.bind(installed.openRead()).first).toString(),
          expected['database_sha256'],
        );
      } finally {
        await reopened.close();
      }
    },
  );
}

class _SqlAssets extends CachingAssetBundle {
  final loaded = <String>[];
  @override
  Future<ByteData> load(String key) {
    loaded.add(key);
    if (key.endsWith('.geojson')) {
      throw StateError('O app SQL não deve abrir GeoJSONs.');
    }
    return rootBundle.load(key);
  }
}

class _InvalidAssets extends CachingAssetBundle {
  int manifestReads = 0;
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    manifestReads++;
    return jsonEncode({
      'schema_version': 1,
      'format': 'cultivar-sqlite-wkb-v1',
      'database_sha256': '0' * 64,
      'compressed_sha256': '0' * 64,
      'asset': 'data.sqlite.gz',
      'database_bytes': 10,
    });
  }

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
}
