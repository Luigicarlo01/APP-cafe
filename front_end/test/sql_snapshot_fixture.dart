import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_end/services/cultivar_database.dart';

/// Instala os mesmos assets SQL compactados do APK, sem consultar GeoJSONs.
Future<CultivarDatabase> openSqlSnapshotForTest() async {
  final directory = await Directory.systemTemp.createTemp(
    'cultivar-sqlite-test-',
  );
  final database = CultivarDatabase(storageDirectory: () async => directory);
  addTearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });
  await database.ready();
  return database;
}
