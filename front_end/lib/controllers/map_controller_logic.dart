import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';

class MapControllerLogic extends ChangeNotifier {
  final LocationService _locationService = LocationService();
  final MapController mapController = MapController();

  LatLng? selectedPoint;

  static final LatLngBounds mgBounds = LatLngBounds(
    LatLng(-22.93, -51.05),
    LatLng(-14.23, -39.85),
  );

  void setPoint(LatLng point) {
    selectedPoint = point;
    notifyListeners();
  }

  void clearPoint() {
    selectedPoint = null;
    notifyListeners();
  }

  bool isValidPoint(LatLng point) {
    // O contorno estadual usado para desenhar o mapa é simplificado e pode
    // excluir pontos válidos na divisa. O limite municipal exato é conferido
    // pelo AnalysisService ao confirmar; aqui restringimos só a área do mapa.
    return mgBounds.contains(point);
  }

  void onMapTap(LatLng point, {required VoidCallback onInvalid}) {
    if (!isValidPoint(point)) {
      onInvalid();
      return;
    }

    setPoint(point);
    mapController.move(point, 15);
  }

  void onCitySelected(
    Map<String, dynamic> city, {
    required VoidCallback onInvalid,
    required VoidCallback onSuccess,
  }) {
    final lat = double.tryParse(city['lat'].toString());
    final lng = double.tryParse(city['lon'].toString());

    if (lat == null || lng == null) {
      debugPrint('Erro: coordenadas inválidas');
      return;
    }

    final point = LatLng(lat, lng);

    if (!isValidPoint(point)) {
      onInvalid();
      return;
    }

    setPoint(point);
    onSuccess();
    mapController.move(point, 15);
  }

  Future<void> goToCurrentLocation({
    required VoidCallback onInvalid,
  }) async {
    final point = await _locationService.getCurrentLocation();
    if (point == null) return;

    if (!isValidPoint(point)) {
      onInvalid();
      return;
    }

    setPoint(point);
    mapController.move(point, 15);
  }

}
