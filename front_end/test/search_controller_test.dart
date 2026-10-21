import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_end/controllers/search_controller.dart';
import 'package:front_end/services/local_municipality_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CatalogBundle bundle;
  late LocalMunicipalityService localService;

  setUp(() {
    bundle = _CatalogBundle();
    localService = LocalMunicipalityService(
      bundle: bundle,
      assetPaths: [
        'assets/VICOSA_2026.geojson',
        'assets/SAO_JOAO_2026.geojson',
      ],
    );
  });

  testWidgets('busca offline preserva acentos e resolve coordenadas locais', (
    tester,
  ) async {
    final controller = CitySearchController(searchService: localService);
    addTearDown(controller.dispose);

    controller.onSearchChanged('vicosa');
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.suggestions.single['name'], 'Viçosa, Minas Gerais');
    final resolved = await controller.resolveSuggestion(
      controller.suggestions.single,
    );
    expect(resolved?['lat'], -20.75);
    expect(resolved?['lon'], -42.88);

    controller.onSearchChanged('são');
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.suggestions.single['name'], 'São João, Minas Gerais');
    expect(bundle.loaded, ['assets/municipalities_2026.json']);
    expect(
      await controller.resolveSuggestion({'lat': double.nan, 'lon': 0}),
      isNull,
    );
    expect(controller.isResolving, isFalse);
  });

  testWidgets('mudança, query curta e limpeza cancelam sugestões anteriores', (
    tester,
  ) async {
    final controller = CitySearchController(searchService: localService);
    addTearDown(controller.dispose);

    controller.onSearchChanged('sao');
    controller.onSearchChanged('vicosa');
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.suggestions.single['name'], 'Viçosa, Minas Gerais');

    controller.onSearchChanged('vi');
    expect(controller.suggestions, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.suggestions, isEmpty);

    controller.onSearchChanged('sao');
    controller.clearSuggestions();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.suggestions, isEmpty);
  });

  testWidgets('resposta antiga não sobrescreve consulta nova nem lista limpa', (
    tester,
  ) async {
    final municipalities = await localService.getMunicipalities();
    final deferred = _DeferredMunicipalityService();
    final controller = CitySearchController(searchService: deferred);
    addTearDown(controller.dispose);

    controller.onSearchChanged('consulta antiga');
    await tester.pump(const Duration(milliseconds: 300));
    controller.onSearchChanged('consulta nova');
    await tester.pump(const Duration(milliseconds: 300));

    deferred.pending['consulta nova']!.complete([
      municipalities.firstWhere(
        (municipality) => municipality.name == 'Viçosa',
      ),
    ]);
    await tester.pump();
    expect(controller.suggestions.single['name'], 'Viçosa, Minas Gerais');
    deferred.pending['consulta antiga']!.complete([
      municipalities.firstWhere(
        (municipality) => municipality.name == 'São João',
      ),
    ]);
    await tester.pump();
    expect(controller.suggestions.single['name'], 'Viçosa, Minas Gerais');

    controller.onSearchChanged('consulta limpa');
    await tester.pump(const Duration(milliseconds: 300));
    controller.clearSuggestions();
    deferred.pending['consulta limpa']!.complete(municipalities);
    await tester.pump();
    expect(controller.suggestions, isEmpty);
  });

  testWidgets('dispose cancela timer e ignora resultado em andamento', (
    tester,
  ) async {
    final deferred = _DeferredMunicipalityService();
    final pendingController = CitySearchController(searchService: deferred);
    pendingController.onSearchChanged('pendente');
    await tester.pump(const Duration(milliseconds: 300));
    pendingController.dispose();
    deferred.pending['pendente']!.complete(
      await localService.getMunicipalities(),
    );
    await tester.pump();
    expect(pendingController.suggestions, isEmpty);
    expect(tester.takeException(), isNull);

    final timerController = CitySearchController(searchService: deferred);
    timerController.onSearchChanged('cancelada');
    timerController.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(deferred.pending.containsKey('cancelada'), isFalse);
  });
}

class _DeferredMunicipalityService extends LocalMunicipalityService {
  final Map<String, Completer<List<LocalMunicipality>>> pending = {};

  @override
  Future<List<LocalMunicipality>> search(String query, {int limit = 8}) {
    final completer = Completer<List<LocalMunicipality>>();
    pending[query] = completer;
    return completer.future;
  }
}

class _CatalogBundle extends CachingAssetBundle {
  final List<String> loaded = [];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    if (key != 'assets/municipalities_2026.json') {
      throw StateError('A pesquisa não deve abrir o asset: $key');
    }
    final catalog = jsonEncode({
      'municipalities': [
        {
          'code': '3171303',
          'name': 'Viçosa',
          'asset': 'assets/VICOSA_2026.geojson',
          'bbox': [-43, -21, -42, -20],
          'center': [-42.88, -20.75],
        },
        {
          'code': '2',
          'name': 'São João',
          'asset': 'assets/SAO_JOAO_2026.geojson',
          'bbox': [-45, -22, -44, -21],
          'center': [-44.5, -21.5],
        },
      ],
    });
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(catalog)));
  }
}
