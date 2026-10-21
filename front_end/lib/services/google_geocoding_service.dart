import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'api_config.dart';

/// **DESATIVADO** — reverse geocoding não é mais consumido pelo app.
/// Arquivo mantido caso seja preciso reativar no futuro.
///
/// Reverse Geocoding do Google.
///
/// O mapa (flutter_map + tiles OSM) continua emitindo cliques com um [LatLng].
/// Sempre que quisermos transformar essas coordenadas em um endereço legível,
/// chamamos [reverseGeocode] e recebemos o `formatted_address` do Google.
@Deprecated('Reverse geocoding foi desativado — não usar.')
class GoogleGeocodingService {
  static const String _geocodeUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  /// Recebe coordenadas (ex.: vindas do OpenStreetMap/flutter_map) e devolve
  /// o endereço formatado do Google, ou `null` em caso de falha.
  ///
  /// Retorno: `{"name": <formatted_address>, "lat": <double>, "lon": <double>}`.
  Future<Map<String, dynamic>?> reverseGeocode(LatLng point) async {
    final uri = Uri.parse(_geocodeUrl).replace(queryParameters: {
      'latlng': '${point.latitude},${point.longitude}',
      'language': 'pt-BR',
      'key': googleMapsApiKey,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint('Reverse Geocoding HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'UNKNOWN';
      if (status != 'OK') {
        debugPrint('Reverse Geocoding status: $status '
            '${data['error_message'] ?? ''}');
        return null;
      }

      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      return {
        'name': first['formatted_address'] ?? '',
        'lat': point.latitude,
        'lon': point.longitude,
      };
    } catch (e) {
      debugPrint('Erro em Reverse Geocoding: $e');
      return null;
    }
  }

  /// Versão que devolve só a string do endereço (conveniência).
  Future<String?> addressOf(LatLng point) async {
    final result = await reverseGeocode(point);
    return result?['name'] as String?;
  }
}
