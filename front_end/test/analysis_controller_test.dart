import 'package:flutter_test/flutter_test.dart';
import 'package:front_end/controllers/analysis_controller.dart';
import 'package:front_end/services/analysis_service.dart';
import 'package:front_end/services/crop_cycle_service.dart';
import 'package:front_end/services/cultivar_info_service.dart';
import 'package:latlong2/latlong.dart';

import 'sql_snapshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AnalysisService service;
  final cycle = CropCycleService();
  late AnalysisController controller;

  setUpAll(() async {
    service = AnalysisService.forDatabase(await openSqlSnapshotForTest());
    await CultivarInfoService().load();
    await service.load(lat: -20.754, lng: -42.881);
  });

  setUp(() {
    cycle.setCycle(CropCycle.medio);
    controller = AnalysisController(analysisService: service);
  });

  tearDown(() {
    controller.dispose();
    cycle.setCycle(CropCycle.medio);
  });

  GridCell cellForWinner(String winner) => service.cells.firstWhere(
    (cell) => cell.winner == winner && cell.containsPoint(cell.centroid),
  );

  List<String> names() =>
      controller.selectedRanking.map((cultivar) => cultivar.nome).toList();

  test(
    'carregamento inicial preserva ranking do pixel com produtividade menor',
    () async {
      final cell = cellForWinner('MGS Epamig 1194');
      await controller.load(
        position: LatLng(cell.centroid.dy, cell.centroid.dx),
      );

      expect(controller.errorMessage, isNull);
      expect(names(), [
        'MGS Epamig 1194',
        'Topázio MG 1190',
        'MGS Catiguá 3',
        'Catiguá MG2',
        'Catuaí Vermelho IAC 144',
      ]);
      final ranking = controller.selectedRanking;
      expect(ranking[0].produtividade, isNotNull);
      expect(ranking[1].produtividade, isNotNull);
      expect(
        ranking[0].produtividade!.media,
        lessThan(ranking[1].produtividade!.media),
        reason:
            'Uma produtividade de referência maior não deve substituir o ranking local.',
      );
    },
  );

  test(
    'trocar pixel no mesmo município atualiza ordem das mesmas cultivares',
    () {
      controller.updateSelectedGenotypeFromPosition(
        cellForWinner('MGS Epamig 1194').centroid,
      );
      final first = names();
      controller.selectGenotype(first.first);

      controller.updateSelectedGenotypeFromPosition(
        cellForWinner('Topázio MG 1190').centroid,
      );
      expect(service.municipio, 'VICOSA_2026');
      expect(controller.selectedGenotype, isNull);
      expect(first, [
        'MGS Epamig 1194',
        'Topázio MG 1190',
        'MGS Catiguá 3',
        'Catiguá MG2',
        'Catuaí Vermelho IAC 144',
      ]);
      expect(names(), [
        'Topázio MG 1190',
        'MGS Epamig 1194',
        'MGS Catiguá 3',
        'Catiguá MG2',
        'Catuaí Vermelho IAC 144',
      ]);
      expect(names().toSet(), first.toSet());
    },
  );

  test('filtros removem cultivares sem reordenar as alternativas do pixel', () {
    controller.updateSelectedGenotypeFromPosition(
      cellForWinner('MGS Epamig 1194').centroid,
    );
    controller.setFerrugemFilter(ResistanceFilter.resistente);
    expect(names(), [
      'MGS Catiguá 3',
      'Catiguá MG2',
      'Pau Brasil MG1',
      'Sarchimor MG 8840',
    ]);

    controller.setNematoideFilter(ResistanceFilter.resistente);
    expect(names(), ['MGS Catiguá 3']);

    controller.setFerrugemFilter(ResistanceFilter.todos);
    controller.setNematoideFilter(ResistanceFilter.todos);
    expect(names().first, 'MGS Epamig 1194');
    expect(names(), hasLength(5));
  });
}
