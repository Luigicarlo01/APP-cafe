import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Serviço que substitui o antigo [LocationSearchService] (Nominatim).
///
/// Usa a **Places API (New)** do Google:
///  - Autocomplete: POST `https://places.googleapis.com/v1/places:autocomplete`
///  - Place Details: GET  `https://places.googleapis.com/v1/places/{placeId}`
///
/// Também expõe [forwardGeocode] via Geocoding API (endpoint separado, não
/// faz parte da Places API), útil quando já se tem um texto completo de
/// endereço (fallback).
///
/// Requer no Google Cloud Console:
///  - Places API (New) habilitada
///  - Geocoding API habilitada (opcional, só para [forwardGeocode])
class GooglePlacesService {
  static const String _autocompleteUrl =
      'https://places.googleapis.com/v1/places:autocomplete';
  static const String _detailsBaseUrl =
      'https://places.googleapis.com/v1/places';
  static const String _geocodeUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  /// Session token para reduzir custo do Autocomplete + Details.
  /// Deve ser reutilizado entre chamadas de uma mesma "sessão de busca"
  /// (várias digitações + 1 seleção) e trocado após a seleção.
  String? _sessionToken;

  void startNewSession() {
    _sessionToken = DateTime.now().microsecondsSinceEpoch.toString();
  }

  void endSession() {
    _sessionToken = null;
  }

  /// Busca sugestões de cidades/lugares por texto digitado.
  ///
  /// Retorna até 5 itens no formato:
  ///   `{"name": <descrição>, "place_id": <id>}`
  ///
  /// As coordenadas NÃO vêm neste passo — são resolvidas depois via
  /// [getPlaceDetails] quando o usuário seleciona uma sugestão.
  Future<List<Map<String, dynamic>>> searchCity(String query) async {
    if (query.trim().isEmpty) return [];

    _sessionToken ??= DateTime.now().microsecondsSinceEpoch.toString();

    final body = <String, dynamic>{
      'input': query,
      'languageCode': 'pt-BR',
      'regionCode': 'br',
      'includedRegionCodes': ['br'],
      'sessionToken': _sessionToken,
    };

    try {
      final response = await http.post(
        Uri.parse(_autocompleteUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': googleMapsApiKey,
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Places Autocomplete (New) HTTP ${response.statusCode}: ${response.body}',
        );
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = (data['suggestions'] as List?) ?? [];

      final results = <Map<String, dynamic>>[];
      for (final s in suggestions.take(5)) {
        final prediction = (s as Map<String, dynamic>)['placePrediction']
            as Map<String, dynamic>?;
        if (prediction == null) continue;

        final placeId = prediction['placeId'] as String? ?? '';
        if (placeId.isEmpty) continue;

        final text = (prediction['text'] as Map?)?['text'] as String?;
        final structured =
            prediction['structuredFormat'] as Map<String, dynamic>?;
        final main = (structured?['mainText'] as Map?)?['text'] as String?;
        final secondary =
            (structured?['secondaryText'] as Map?)?['text'] as String?;

        final label = (main != null && secondary != null)
            ? '$main, $secondary'
            : (text ?? main ?? '');

        results.add({
          'name': label,
          'place_id': placeId,
        });
      }
      return results;
    } catch (e) {
      debugPrint('Erro em Places Autocomplete (New): $e');
      return [];
    }
  }

  /// Recupera as coordenadas de um `place_id` (etapa 2 da busca).
  ///
  /// Retorna `{"name", "lat", "lon"}` compatível com o formato que o
  /// controller e o mapa já esperam, ou `null` se falhar.
  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) return null;

    // Places API (New) usa /v1/places/{placeId} (não `place_id=`).
    final uri = Uri.parse('$_detailsBaseUrl/$placeId').replace(
      queryParameters: {
        'languageCode': 'pt-BR',
        'sessionToken': ?_sessionToken,
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'X-Goog-Api-Key': googleMapsApiKey,
          // FieldMask é obrigatório na Places API (New).
          'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
        },
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Place Details (New) HTTP ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) return null;

      final lat = (location['latitude'] as num?)?.toDouble();
      final lng = (location['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final displayName =
          (data['displayName'] as Map?)?['text'] as String?;
      final formatted = data['formattedAddress'] as String?;

      // Encerra a session token — a busca terminou com sucesso.
      endSession();

      return {
        'name': formatted ?? displayName ?? '',
        'lat': lat,
        'lon': lng,
      };
    } catch (e) {
      debugPrint('Erro em Place Details (New): $e');
      return null;
    }
  }

  /// Geocoding direto: endereço em texto → coordenadas.
  /// Usa a Geocoding API (endpoint separado da Places API).
  Future<Map<String, dynamic>?> forwardGeocode(String address) async {
    if (address.trim().isEmpty) return null;

    final uri = Uri.parse(_geocodeUrl).replace(queryParameters: {
      'address': address,
      'components': 'country:BR',
      'language': 'pt-BR',
      'key': googleMapsApiKey,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if ((data['status'] as String?) != 'OK') {
        debugPrint('Geocoding status: ${data['status']} '
            '${data['error_message'] ?? ''}');
        return null;
      }

      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final location =
          (first['geometry'] as Map)['location'] as Map<String, dynamic>;
      return {
        'name': first['formatted_address'] ?? '',
        'lat': (location['lat'] as num).toDouble(),
        'lon': (location['lng'] as num).toDouble(),
      };
    } catch (e) {
      debugPrint('Erro em Geocoding: $e');
      return null;
    }
  }
}
