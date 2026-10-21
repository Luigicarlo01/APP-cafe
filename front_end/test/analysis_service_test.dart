import 'package:flutter_test/flutter_test.dart';
import 'package:front_end/services/analysis_service.dart';
import 'package:front_end/services/local_municipality_service.dart';

import 'sql_snapshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AnalysisService service;
  late LocalMunicipalityService municipalities;
  setUpAll(() async {
    final database = await openSqlSnapshotForTest();
    service = AnalysisService.forDatabase(database);
    municipalities = LocalMunicipalityService(database: database);
  });

  test(
    'GPS e cliques carregam o município atual sem pesquisa ou servidor',
    () async {
      for (final location in [
        (name: 'Viçosa', key: 'VICOSA_2026', lat: -20.754, lng: -42.881),
        (
          name: 'Esmeraldas',
          key: 'ESMERALDAS_2026',
          lat: -19.764,
          lng: -44.313,
        ),
        (
          name: 'São João del Rei',
          key: 'SAO_JOAO_DEL_REI_2026',
          lat: -21.135,
          lng: -44.261,
        ),
      ]) {
        await service.load(lat: location.lat, lng: location.lng);
        expect(service.municipio, location.key);
        expect(service.displayName, location.name);
        expect(service.cells, isNotEmpty);
        expect(service.winners, isNotEmpty);
        expect(
          service.cellContaining(Offset(location.lng, location.lat))?.winner,
          isNotEmpty,
          reason: location.name,
        );
      }
    },
  );

  test('cidade pesquisada abre dados locais pelo ponto da sugestão', () async {
    final city = (await municipalities.search('olhos d agua')).single;
    await service.load(lat: city.latitude, lng: city.longitude);
    expect(service.displayName, "Olhos-d'Água");
    expect(service.municipio, 'OLHOS_D_AGUA_2026');
    expect(service.cells, isNotEmpty);
    expect(service.winners, isNotEmpty);
  });

  test(
    'ponto fora de MG informa falta de cobertura e limpa dados anteriores',
    () async {
      await service.load(lat: -20.754, lng: -42.881);
      await expectLater(
        service.load(lat: -23.5505, lng: -46.6333),
        throwsA(
          isA<NoDataException>().having(
            (error) => error.message,
            'mensagem de cobertura',
            contains('Minas Gerais'),
          ),
        ),
      );
      expect(service.cells, isEmpty);
      expect(service.winners, isEmpty);
      expect(service.municipio, isNull);
    },
  );
}
