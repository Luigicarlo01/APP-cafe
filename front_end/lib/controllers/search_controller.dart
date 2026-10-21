import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/local_municipality_service.dart';

class CitySearchController extends ChangeNotifier {
  final LocalMunicipalityService _searchService;

  List<Map<String, dynamic>> suggestions = [];

  Timer? _debounce;
  int _searchGeneration = 0;
  bool _disposed = false;
  bool _isResolving = false;

  CitySearchController({LocalMunicipalityService? searchService})
    : _searchService = searchService ?? LocalMunicipalityService.instance;

  bool get isResolving => _isResolving;

  void onSearchChanged(String query) {
    if (_disposed) return;
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    suggestions = [];
    notifyListeners();
    if (_disposed || generation != _searchGeneration) return;

    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) return;

    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_search(normalizedQuery, generation));
    });
  }

  Future<void> _search(String query, int generation) async {
    try {
      final municipalities = await _searchService.search(query);
      if (_disposed || generation != _searchGeneration) return;
      suggestions = municipalities
          .map(
            (municipality) => <String, dynamic>{
              'name': '${municipality.name}, Minas Gerais',
              'lat': municipality.latitude,
              'lon': municipality.longitude,
            },
          )
          .toList(growable: false);
      notifyListeners();
    } catch (error) {
      if (_disposed || generation != _searchGeneration) return;
      suggestions = [];
      debugPrint('Erro ao pesquisar municípios locais: $error');
      notifyListeners();
    }
  }

  /// As sugestões locais já contêm um ponto interior ao município.
  Future<Map<String, dynamic>?> resolveSuggestion(
    Map<String, dynamic> suggestion,
  ) async {
    if (_disposed) return null;
    _isResolving = true;
    notifyListeners();

    try {
      if (_disposed) return null;
      final lat = suggestion['lat'];
      final lon = suggestion['lon'];
      if (lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        return null;
      }
      return {...suggestion, 'lat': lat.toDouble(), 'lon': lon.toDouble()};
    } finally {
      _isResolving = false;
      if (!_disposed) notifyListeners();
    }
  }

  void clearSuggestions() {
    if (_disposed) return;
    _debounce?.cancel();
    ++_searchGeneration;
    suggestions = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    ++_searchGeneration;
    super.dispose();
  }
}
