import 'dart:convert';
import 'package:http/http.dart' as http;

/// **DESATIVADO** — substituído por [GooglePlacesService].
///
/// Mantido no repositório caso seja preciso voltar ao Nominatim rapidamente,
/// mas nenhuma parte ativa do app chama esta classe.
@Deprecated('Use GooglePlacesService (google_places_service.dart)')
class LocationSearchService {
  Future<List<Map<String, dynamic>>> searchCity(String query) async {
    final response = await http.get(
      Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&countrycodes=br',
      ),
      headers: {
        'User-Agent': 'PlantioApp/1.0 (luis.f.pereira@ufv.br)',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);

      if (data.isNotEmpty) {
        
        return data.take(5)
        .map((item){
          return {
            "name": item["display_name"],
            "lat": double.parse(item["lat"]),
            "lon": double.parse(item["lon"]),
          };
        })
        .toList();
      }

    }

  return [];
  }
}