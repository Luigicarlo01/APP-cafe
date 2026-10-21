/// Retângulo geográfico definido por 4 limites (em graus decimais).
///
/// Um `BoundingBox` é um "AABB" (axis-aligned bounding box) — os lados
/// são paralelos aos eixos lat/lon. Não representa curvatura da Terra;
/// para os tamanhos que usamos (município ou estado) o erro é
/// desprezível.
class BoundingBox {
  // Todas as coordenadas são `final` — o objeto é imutável
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  /// Construtor const — permite usar `BoundingBox(...)` em expressões
  /// constantes (ex.: em testes) sem alocar novo objeto a cada avaliação.
  const BoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  /// Área em graus² (não em km²). Serve **exclusivamente** como métrica
  /// de desempate quando dois bboxes contêm o mesmo ponto — o menor
  /// (mais específico) ganha.
  ///
  /// Como é só desempate, tanto faz que 1° de latitude ≠ 1° de longitude
  /// em km. A ordem relativa entre bboxes fica correta.
  double get area => (maxLat - minLat) * (maxLon - minLon);

  /// Testa se um ponto está dentro do bbox (bordas inclusivas).
  ///
  /// Usado quando o app pergunta "existe alguma região cacheada que
  /// englobe este LatLon?". A query SQL faz o mesmo teste, mas em Dart
  /// serve pra validações locais.
  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  /// Cria um `BoundingBox` a partir do JSON do backend.
  ///
  /// Formato esperado (definido pelo backend em `analysis_route.py`):
  /// ```
  /// { "min_lat": -20.85, "max_lat": -20.70,
  ///   "min_lon": -42.95, "max_lon": -42.80 }
  /// ```
  ///
  /// O cast pra `num` primeiro e depois `.toDouble()` é defensivo:
  /// alguns JSONs podem trazer int (ex: `-20`) e queremos double sempre.
  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        minLat: (json['min_lat'] as num).toDouble(),
        maxLat: (json['max_lat'] as num).toDouble(),
        minLon: (json['min_lon'] as num).toDouble(),
        maxLon: (json['max_lon'] as num).toDouble(),
      );

  /// Serializa para o mesmo formato que o backend usa. Útil pra debug
  /// e testes (não é chamado em runtime hoje).
  Map<String, dynamic> toJson() => {
        'min_lat': minLat,
        'max_lat': maxLat,
        'min_lon': minLon,
        'max_lon': maxLon,
      };

  /// Formato humano — aparece em `debugPrint` e mensagens de erro.
  /// Ex.: `BoundingBox(-20.85..-20.70, -42.95..-42.80)`
  @override
  String toString() => 'BoundingBox($minLat..$maxLat, $minLon..$maxLon)';
}
