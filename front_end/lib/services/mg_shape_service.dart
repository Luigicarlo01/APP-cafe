// lib/services/mg_shape_service.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class MgShapeService {
  static final MgShapeService _instance = MgShapeService._internal();
  factory MgShapeService() => _instance;
  MgShapeService._internal();

  List<LatLng> shape = [];

  Future<void> load() async {
    if (shape.isNotEmpty) return; // já carregado

    final String data = await rootBundle.loadString('assets/mg.geojson');
    final geojson = jsonDecode(data);
    final feature = geojson['features'][0];
    final coordinates = feature['geometry']['coordinates'][0] as List;

    shape = coordinates.map((c) {
      return LatLng(c[1].toDouble(), c[0].toDouble());
    }).toList();
  }
}