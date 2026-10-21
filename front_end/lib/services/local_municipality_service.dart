import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/polygon_wkb.dart';
import 'cultivar_database.dart';

/// Município que possui resultados na cópia SQLite distribuída com o app.
class LocalMunicipality {
  final String code;
  final String name;
  final String assetPath;
  final double latitude;
  final double longitude;
  final List<double> _bounds;

  LocalMunicipality._(Map<String, dynamic> json)
    : code = json['code'] as String,
      name = json['name'] as String,
      assetPath = json['asset'] as String,
      latitude = (json['center'][1] as num).toDouble(),
      longitude = (json['center'][0] as num).toDouble(),
      _bounds = (json['bbox'] as List)
          .map((value) => (value as num).toDouble())
          .toList(growable: false);

  bool _mayContain(double latitude, double longitude) =>
      longitude >= _bounds[0] &&
      latitude >= _bounds[1] &&
      longitude <= _bounds[2] &&
      latitude <= _bounds[3];
}

/// Pesquisa offline e identificação exata do município por coordenadas.
///
/// O catálogo e os limites vêm do SQLite. Apenas os limites candidatos pela
/// bbox são consultados. Nenhuma seleção anterior interfere nessa resolução.
class LocalMunicipalityService {
  static final LocalMunicipalityService instance = LocalMunicipalityService();

  final AssetBundle _bundle;
  final CultivarDatabase? _database;
  final Iterable<String>? _assetPaths;
  final int year;
  Future<List<LocalMunicipality>>? _catalog;
  final Map<String, Future<_MunicipalBoundary>> _boundaries = {};

  LocalMunicipalityService({
    CultivarDatabase? database,
    AssetBundle? bundle,
    Iterable<String>? assetPaths,
    this.year = 2026,
  }) : _bundle = bundle ?? rootBundle,
       // O bundle explícito mantém os testes das geometrias de origem. O app
       // usa sempre SQLite, sem fallback silencioso para os GeoJSONs.
       _database =
           database ?? (bundle == null ? CultivarDatabase.instance : null),
       _assetPaths = assetPaths;

  Future<List<LocalMunicipality>> _loadCatalog() async {
    final database = _database;
    if (database != null) {
      final municipalities = (await database.municipalities(
        year,
      )).map(LocalMunicipality._).toList();
      municipalities.sort(
        (a, b) => normalizeName(a.name).compareTo(normalizeName(b.name)),
      );
      return List.unmodifiable(municipalities);
    }
    final paths =
        _assetPaths ??
        (await AssetManifest.loadFromAssetBundle(_bundle)).listAssets();
    final available = paths.toSet();
    final raw = await _bundle.loadString('assets/municipalities_$year.json');
    final catalog = jsonDecode(raw) as Map<String, dynamic>;
    final municipalities = (catalog['municipalities'] as List)
        .cast<Map<String, dynamic>>()
        .map(LocalMunicipality._)
        .where((municipality) => available.contains(municipality.assetPath))
        .toList();
    municipalities.sort(
      (a, b) => normalizeName(a.name).compareTo(normalizeName(b.name)),
    );
    return List.unmodifiable(municipalities);
  }

  Future<List<LocalMunicipality>> getMunicipalities() async {
    try {
      return await (_catalog ??= _loadCatalog());
    } catch (_) {
      // Uma falha de leitura não deve ficar memorizada por toda a sessão.
      _catalog = null;
      rethrow;
    }
  }

  /// Aceita nomes acentuados, sem acentos e sinais como em Olhos-d'Água.
  /// Também aceita o nome completo de uma sugestão antiga, separado por vírgula.
  Future<LocalMunicipality?> findByName(String name) async {
    final normalized = normalizeName(name.split(',').first);
    if (normalized.isEmpty) return null;
    for (final municipality in await getMunicipalities()) {
      if (normalizeName(municipality.name) == normalized) return municipality;
    }
    return null;
  }

  Future<List<LocalMunicipality>> search(String query, {int limit = 8}) async {
    final normalized = normalizeName(query);
    if (normalized.isEmpty || limit <= 0) return const [];
    final tokens = normalized.split('_');
    final matches = (await getMunicipalities()).where((municipality) {
      final name = normalizeName(municipality.name);
      return tokens.every(name.contains);
    }).toList();
    matches.sort((a, b) {
      final aName = normalizeName(a.name);
      final bName = normalizeName(b.name);
      int rank(String name) =>
          name == normalized ? 0 : (name.startsWith(normalized) ? 1 : 2);
      final order = rank(aName).compareTo(rank(bName));
      return order == 0 ? aName.compareTo(bName) : order;
    });
    return matches.take(limit).toList(growable: false);
  }

  Future<LocalMunicipality?> findByCoordinates({
    required double lat,
    required double lng,
  }) async {
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    for (final municipality in await getMunicipalities()) {
      if (!municipality._mayContain(lat, lng)) continue;
      final boundary = await _loadBoundary(municipality.assetPath);
      if (boundary.contains(lat, lng)) return municipality;
    }
    return null;
  }

  Future<_MunicipalBoundary> _loadBoundary(String assetPath) async {
    final cached = _boundaries.remove(assetPath);
    if (cached != null) {
      _boundaries[assetPath] = cached;
      return cached;
    }
    final loading = _readBoundary(assetPath);
    _boundaries[assetPath] = loading;
    // Guarda poucos limites, sem manter os GeoJSONs inteiros nem suas células.
    if (_boundaries.length > 8) _boundaries.remove(_boundaries.keys.first);
    try {
      return await loading;
    } catch (_) {
      _boundaries.remove(assetPath);
      rethrow;
    }
  }

  Future<_MunicipalBoundary> _readBoundary(String assetPath) async {
    final database = _database;
    if (database != null) {
      return compute(
        _parseSqlMunicipalBoundary,
        await database.boundary(assetPath),
      );
    }
    final raw = await _bundle.loadString(assetPath, cache: false);
    return compute(_parseMunicipalBoundary, raw);
  }

  static String normalizeName(String value) {
    var result = value.toUpperCase();
    const replacements = {
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ã': 'A',
      'Ä': 'A',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ö': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ç': 'C',
      'Ñ': 'N',
    };
    replacements.forEach((from, to) => result = result.replaceAll(from, to));
    return result
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

typedef _Ring = List<List<double>>;
typedef _Polygon = List<_Ring>;

_MunicipalBoundary _parseMunicipalBoundary(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final features = data['features'] as List;
  final feature = features.cast<Map<String, dynamic>>().firstWhere(
    (feature) => (feature['properties'] as Map?)?['type'] == 'municipio',
    orElse: () => throw const FormatException('GeoJSON sem limite municipal.'),
  );
  final geometry = feature['geometry'] as Map<String, dynamic>;
  return _boundaryFromGeometry(geometry);
}

_MunicipalBoundary _parseSqlMunicipalBoundary(Uint8List bytes) =>
    _boundaryFromGeometry(polygonGeometryFromWkb(bytes));

_MunicipalBoundary _boundaryFromGeometry(Map<String, dynamic> geometry) {
  final coordinates = geometry['coordinates'] as List;
  final List polygons;
  switch (geometry['type']) {
    case 'Polygon':
      polygons = [coordinates];
    case 'MultiPolygon':
      polygons = coordinates;
    default:
      throw FormatException(
        'Geometria municipal inválida: ${geometry['type']}',
      );
  }
  return _MunicipalBoundary(
    polygons
        .map(
          (polygon) => (polygon as List)
              .map(
                (ring) => (ring as List)
                    .map(
                      (point) => [
                        (point[0] as num).toDouble(),
                        (point[1] as num).toDouble(),
                      ],
                    )
                    .toList(growable: false),
              )
              .toList(growable: false),
        )
        .toList(growable: false),
  );
}

class _MunicipalBoundary {
  final List<_Polygon> polygons;

  _MunicipalBoundary(this.polygons);

  bool contains(double latitude, double longitude) {
    for (final polygon in polygons) {
      if (polygon.isEmpty) continue;
      final outer = _pointInRing(longitude, latitude, polygon.first);
      // A borda externa pertence ao município; não deixa uma faixa sem dados.
      if (outer == 2) return true;
      if (outer == 0) continue;
      var insideHole = false;
      for (final hole in polygon.skip(1)) {
        final relation = _pointInRing(longitude, latitude, hole);
        if (relation == 2) return true;
        if (relation == 1) {
          insideHole = true;
          break;
        }
      }
      if (!insideHole) return true;
    }
    return false;
  }
}

// 0: exterior; 1: interior; 2: na borda. Inclui anéis não explicitamente fechados.
int _pointInRing(double x, double y, _Ring ring) {
  if (ring.length < 3) return 0;
  var inside = false;
  var previous = ring.last;
  for (final current in ring) {
    final x1 = previous[0];
    final y1 = previous[1];
    final x2 = current[0];
    final y2 = current[1];
    final dx = x2 - x1;
    final dy = y2 - y1;
    final cross = (x - x1) * dy - (y - y1) * dx;
    const tolerance = 1e-10;
    if (cross.abs() <= tolerance * (dx.abs() + dy.abs()) &&
        x >= (x1 < x2 ? x1 : x2) - tolerance &&
        x <= (x1 > x2 ? x1 : x2) + tolerance &&
        y >= (y1 < y2 ? y1 : y2) - tolerance &&
        y <= (y1 > y2 ? y1 : y2) + tolerance) {
      return 2;
    }
    if ((y1 > y) != (y2 > y) && x < x1 + (y - y1) * dx / dy) {
      inside = !inside;
    }
    previous = current;
  }
  return inside ? 1 : 0;
}
