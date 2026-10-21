import 'package:flutter_test/flutter_test.dart';
import 'package:front_end/controllers/map_controller_logic.dart';
import 'package:front_end/services/local_municipality_service.dart';
import 'package:front_end/services/mg_shape_service.dart';
import 'package:latlong2/latlong.dart';

import 'sql_snapshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalMunicipalityService municipalities;
  setUpAll(() async {
    municipalities = LocalMunicipalityService(
      database: await openSqlSnapshotForTest(),
    );
  });

  test(
    'divisa estadual simplificada não bloqueia dados municipais válidos',
    () async {
      await MgShapeService().load();
      final logic = MapControllerLogic();
      addTearDown(logic.dispose);
      addTearDown(logic.mapController.dispose);

      const point = LatLng(-17.262498894244, -47.41773967518301);
      final municipality = await municipalities.findByCoordinates(
        lat: point.latitude,
        lng: point.longitude,
      );
      expect(municipality?.name, 'Paracatu');
      expect(logic.isValidPoint(point), isTrue);
    },
  );

  test(
    'área de seleção cobre o extremo sul e deixa cobertura para análise exata',
    () async {
      final logic = MapControllerLogic();
      addTearDown(logic.dispose);
      addTearDown(logic.mapController.dispose);

      expect(logic.isValidPoint(const LatLng(-22.9227, -46.0)), isTrue);
      expect(logic.isValidPoint(const LatLng(-23.5505, -46.6333)), isFalse);
      const outsideState = LatLng(-15, -50);
      expect(logic.isValidPoint(outsideState), isTrue);
      expect(
        await municipalities.findByCoordinates(
          lat: outsideState.latitude,
          lng: outsideState.longitude,
        ),
        isNull,
      );
    },
  );
}
