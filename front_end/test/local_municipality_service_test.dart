import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_end/services/local_municipality_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryAssetBundle bundle;
  late LocalMunicipalityService service;

  setUp(() {
    bundle = _MemoryAssetBundle(_fixtureAssets());
    service = LocalMunicipalityService(bundle: bundle);
  });

  test('pesquisa nomes oficiais sem internet, acentos ou pontuação', () async {
    expect((await service.search('vicosa')).single.name, 'Viçosa');
    expect((await service.search('VIC\u0327OSA')).single.name, 'Viçosa');
    expect((await service.search('joao sao')).single.name, 'São João');
    final eyes = (await service.search('olhos d agua')).single;
    expect(eyes.name, "Olhos-d'Água");
    expect(eyes.assetPath, 'assets/OLHOS_D_AGUA_2026.geojson');
    expect(await service.search('   '), isEmpty);
    expect(await service.search('sao', limit: 0), isEmpty);
    expect(await service.findByName('Viçosa, Minas Gerais, Brasil'), isNotNull);
  });

  test('consulta catálogo e manifest sem abrir GeoJSONs de análise', () async {
    await service.search('a');
    await service.search('vicosa');
    expect(bundle.loaded.toSet(), {
      'AssetManifest.bin',
      'assets/municipalities_2026.json',
    });
    expect(
      bundle.loaded
          .where((key) => key.endsWith('municipalities_2026.json'))
          .length,
      1,
    );
    expect(await service.findByName('Ausente'), isNull);
  });

  test('filtra municípios sem asset disponível no manifest', () async {
    final catalog = await service.getMunicipalities();
    expect(catalog.map((municipality) => municipality.name), [
      "Olhos-d'Água",
      'São João',
      'Viçosa',
    ]);
    expect(await service.search('Ausente'), isEmpty);
  });

  test(
    'polígono inclui interior, aresta e vértice; ignora bbox falsa',
    () async {
      expect((await service.findByCoordinates(lat: 2, lng: 2))?.name, 'Viçosa');
      expect((await service.findByCoordinates(lat: 0, lng: 2))?.name, 'Viçosa');
      expect((await service.findByCoordinates(lat: 0, lng: 0))?.name, 'Viçosa');
      // A bbox de Olhos-d'Água inclui esse ponto, mas nenhum de seus polígonos.
      expect(await service.findByCoordinates(lat: 10, lng: 14), isNull);
    },
  );

  test('respeita buraco e resolve outro município dentro dele', () async {
    expect(await service.findByCoordinates(lat: 4.25, lng: 4.25), isNull);
    expect((await service.findByCoordinates(lat: 5, lng: 5))?.name, 'São João');
    expect((await service.findByCoordinates(lat: 4, lng: 5))?.name, isNotNull);
  });

  test(
    'resolve ilhas MultiPolygon e não reutiliza município anterior',
    () async {
      expect(
        (await service.findByCoordinates(lat: 0.5, lng: 11.5))?.name,
        "Olhos-d'Água",
      );
      expect(
        (await service.findByCoordinates(lat: 15.5, lng: 15.5))?.name,
        "Olhos-d'Água",
      );
      expect((await service.findByCoordinates(lat: 2, lng: 2))?.name, 'Viçosa');
      expect(await service.findByCoordinates(lat: -30, lng: -45), isNull);
    },
  );

  test(
    'carrega apenas candidatos e memoriza limites sem reler assets',
    () async {
      await service.findByCoordinates(lat: 2, lng: 2);
      await service.findByCoordinates(lat: 3, lng: 3);
      expect(bundle.loaded.where((key) => key.endsWith('.geojson')).toList(), [
        'assets/VICOSA_2026.geojson',
      ]);
    },
  );

  test('coordenadas inválidas não carregam catálogo nem limites', () async {
    expect(await service.findByCoordinates(lat: double.nan, lng: 0), isNull);
    expect(await service.findByCoordinates(lat: 91, lng: 0), isNull);
    expect(
      await service.findByCoordinates(lat: 0, lng: double.infinity),
      isNull,
    );
    expect(bundle.loaded, isEmpty);
  });

  test(
    'catálogo real cobre 853 assets e resolve pontos conhecidos de MG',
    () async {
      final assets = Directory(
        'assets',
      ).listSync().whereType<File>().map((file) => file.path).toList();
      final actual = LocalMunicipalityService(
        bundle: _FileAssetBundle(),
        assetPaths: assets,
      );
      final municipalities = await actual.getMunicipalities();
      expect(municipalities, hasLength(853));
      for (final name in [
        'Viçosa',
        'Belo Horizonte',
        'Uberlândia',
        "Olhos-d'Água",
      ]) {
        final municipality = await actual.findByName(name);
        expect(municipality, isNotNull, reason: name);
        expect(File(municipality!.assetPath).existsSync(), isTrue);
        final resolved = await actual.findByCoordinates(
          lat: municipality.latitude,
          lng: municipality.longitude,
        );
        expect(
          resolved?.code,
          municipality.code,
          reason: 'Ponto interior de $name',
        );
      }
      expect(
        (await actual.findByCoordinates(lat: -20.7549, lng: -42.8795))?.name,
        'Viçosa',
      );
      expect(
        (await actual.findByCoordinates(lat: -19.9167, lng: -43.9345))?.name,
        'Belo Horizonte',
      );
      expect(
        await actual.findByCoordinates(lat: -23.5505, lng: -46.6333),
        isNull,
      );
    },
  );
}

Map<String, String> _fixtureAssets() {
  Map<String, Object> entry(
    String name,
    String key,
    String code,
    List<num> bbox,
    List<num> center,
  ) => {
    'code': code,
    'name': name,
    'asset': 'assets/${key}_2026.geojson',
    'bbox': bbox,
    'center': center,
  };
  String geometry(String type, List coordinates) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      // Células de análise não devem ser interpretadas como limite municipal.
      {
        'properties': {'type': 'cell'},
        'geometry': null,
      },
      {
        'properties': {'type': 'municipio'},
        'geometry': {'type': type, 'coordinates': coordinates},
      },
    ],
  });
  return {
    'assets/municipalities_2026.json': jsonEncode({
      'version': 1,
      'year': 2026,
      'municipalities': [
        entry('Viçosa', 'VICOSA', '1', [0, 0, 10, 10], [2, 2]),
        entry('São João', 'SAO_JOAO', '2', [4.5, 4.5, 5.5, 5.5], [5, 5]),
        entry(
          "Olhos-d'Água",
          'OLHOS_D_AGUA',
          '3',
          [11, 0, 16, 16],
          [11.5, 0.5],
        ),
        entry('Ausente', 'AUSENTE', '4', [0, 0, 1, 1], [0.5, 0.5]),
      ],
    }),
    'assets/VICOSA_2026.geojson': geometry('Polygon', [
      [
        [0, 0],
        [10, 0],
        [10, 10],
        [0, 10],
        [0, 0],
      ],
      [
        [4, 4],
        [6, 4],
        [6, 6],
        [4, 6],
        [4, 4],
      ],
    ]),
    'assets/SAO_JOAO_2026.geojson': geometry('Polygon', [
      [
        [4.5, 4.5],
        [5.5, 4.5],
        [5.5, 5.5],
        [4.5, 5.5],
      ], // anel não explicitamente fechado
    ]),
    'assets/OLHOS_D_AGUA_2026.geojson': geometry('MultiPolygon', [
      [
        [
          [11, 0],
          [13, 0],
          [11, 2],
          [11, 0],
        ],
      ],
      [
        [
          [15, 15],
          [16, 15],
          [16, 16],
          [15, 16],
          [15, 15],
        ],
      ],
    ]),
  };
}

class _MemoryAssetBundle extends CachingAssetBundle {
  final Map<String, String> assets;
  final List<String> loaded = [];

  _MemoryAssetBundle(this.assets);

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final asset in assets.keys)
          asset: [
            <String, Object>{'asset': asset},
          ],
      })!;
    }
    final text = assets[key];
    if (text == null) throw StateError('Asset não encontrado: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}
