import 'dart:math' as math;

import '../../models/bounding_box.dart';

/// Coleção de funções estáticas puras. Sem estado, sem dependência.
class TileMath {

  /// Fórmula pra achar o `x` do tile a partir de longitude no zoom [z].
  ///
  /// Deriva: no zoom 0 o mundo inteiro cabe em 1 tile. Cada zoom dobra
  /// pra cada eixo. Longitude vai de -180 a +180. Então:
  ///
  ///   fração = (lon + 180) / 360   // de 0 (oeste) a 1 (leste)
  ///   x      = floor(fração * 2^z) // tile inteiro
  static int lonToTileX(double lon, int z) {
    final n = math.pow(2, z).toDouble();
    return ((lon + 180.0) / 360.0 * n).floor();
  }

  /// Longitude → `y` do tile. A fórmula é mais complicada porque a
  /// projeção Web Mercator distorce latitudes altas — sinos matemáticos:
  ///
  ///   y = floor( (1 - ln(tan(lat) + sec(lat)) / π) / 2 * 2^z )
  ///
  /// Basicamente: converte latitude pra "y de mercator" (escala não-linear)
  /// e depois pra tile inteiro. Isso é o que a wiki do OSM define.
  ///
  /// Nota: `1/cos(latRad)` é o mesmo que `sec(latRad)`. Dart não tem
  /// `sec()` nativo, então usamos `1 / cos()`.
  static int latToTileY(double lat, int z) {
    final n = math.pow(2, z).toDouble();
    final latRad = lat * math.pi / 180.0;
    return ((1.0 -
                math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) /
                    math.pi) /
            2.0 *
            n)
        .floor();
  }


  /// Quantos tiles cobrem [bbox] no zoom [z] (inclusive nos limites)?
  ///
  /// Retorna o range como objeto `TileRange` que facilita iterar depois.
  ///
  /// Sutileza: no eixo Y (norte-sul), o tile de menor Y é o MAIS AO NORTE.
  /// Por isso o `yMin` corresponde a `maxLat` e o `yMax` a `minLat` —
  /// invertido em relação à intuição.
  static TileRange rangeFor(BoundingBox bbox, int z) {
    final xMin = lonToTileX(bbox.minLon, z);
    final xMax = lonToTileX(bbox.maxLon, z);
    // Y invertido: norte tem y menor. maxLat vira yMin.
    final yMin = latToTileY(bbox.maxLat, z);
    final yMax = latToTileY(bbox.minLat, z);
    return TileRange(z: z, xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax);
  }


  /// Estimativa GROSSA de bytes ocupados por uma pirâmide `[zMin, zMax]`
  /// de tiles cobrindo [bbox]. Usa `avgBytesPerTile` como palpite:
  ///
  ///   - CartoDB Light (o que usamos): ~7-8 KB médio.
  ///   - OSM padrão colorido: ~15-20 KB médio.
  ///
  /// A estimativa é usada em duas situações:
  ///   1) Mostrar ao usuário antes de baixar mapa base ("~15 MB").
  ///   2) Escolher zoom adaptativo (`pickMaxZoom` — legado).
  static int estimateBytes(
    BoundingBox bbox, {
    required int zMin,
    required int zMax,
    int avgBytesPerTile = 8 * 1024,
  }) {
    var total = 0;
    for (var z = zMin; z <= zMax; z++) {
      total += rangeFor(bbox, z).count * avgBytesPerTile;
    }
    return total;
  }


  /// Escolhe o maior `zMax` no range `[minZoom, maxZoom]` tal que a
  /// pirâmide `[minZoom, zMax]` caiba em [quotaBytes].
  ///
  /// Percorre decrescente do `maxZoom` — o primeiro que couber é a
  /// resposta.
  ///
  /// Retorna `null` se nem `minZoom` sozinho cabe (bbox gigante ou
  /// quota apertada demais).
  ///
  /// Não é mais chamado (o TileDownloader que usava isso está
  /// deprecated), mas fica pronto se um dia decidirmos voltar ao
  /// adaptativo por região.
  static int? pickMaxZoom(
    BoundingBox bbox, {
    required int quotaBytes,
    int minZoom = 10,
    int maxZoom = 15,
    int avgBytesPerTile = 8 * 1024,
  }) {
    for (var z = maxZoom; z >= minZoom; z--) {
      final estimate = estimateBytes(
        bbox,
        zMin: minZoom,
        zMax: z,
        avgBytesPerTile: avgBytesPerTile,
      );
      if (estimate <= quotaBytes) return z;
    }
    return null;
  }
}

/// Um range de tiles num único zoom, com iteração pronta.
///
/// Uso típico:
/// ```dart
/// final range = TileMath.rangeFor(bbox, 10);
/// for (final coord in range.iterate()) {
///   // coord.x, coord.y, coord.z
/// }
/// ```
class TileRange {
  final int z;
  final int xMin;
  final int xMax;
  final int yMin;
  final int yMax;

  const TileRange({
    required this.z,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
  });

  /// Nº total de tiles no range. `+ 1` porque os limites são inclusivos.
  int get count => (xMax - xMin + 1) * (yMax - yMin + 1);

  /// Itera todos os `(z, x, y)` do range.
  ///
  /// `sync*` transforma a função num "generator" — cada `yield` produz
  /// um item e pausa. Isso é lazy: não aloca uma lista gigante com
  /// todos os tiles de uma vez.
  Iterable<({int z, int x, int y})> iterate() sync* {
    for (var x = xMin; x <= xMax; x++) {
      for (var y = yMin; y <= yMax; y++) {
        // Record com labels — sintaxe do Dart 3
        yield (z: z, x: x, y: y);
      }
    }
  }

  @override
  String toString() =>
      'TileRange(z=$z, x=[$xMin..$xMax], y=[$yMin..$yMax], n=$count)';
}
