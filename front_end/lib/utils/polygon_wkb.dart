import 'dart:typed_data';

/// WKB 2D Polygon/MultiPolygon, preservando partes, buracos e precisão double.
/// A ordem em disco é longitude/latitude, conforme o GeoJSON de origem.
Map<String, dynamic> polygonGeometryFromWkb(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 0;

  void requireBytes(int count) {
    if (count < 0 || offset + count > data.lengthInBytes) {
      throw const FormatException('Geometria WKB incompleta.');
    }
  }

  int integer(Endian endian) {
    requireBytes(4);
    final value = data.getUint32(offset, endian);
    offset += 4;
    return value;
  }

  Map<String, dynamic> geometry({bool polygonOnly = false}) {
    requireBytes(5);
    final order = data.getUint8(offset++);
    if (order != 0 && order != 1) {
      throw const FormatException('Ordem de bytes WKB inválida.');
    }
    final endian = order == 1 ? Endian.little : Endian.big;
    final type = integer(endian);
    final count = integer(endian);
    if (type == 6 && !polygonOnly) {
      // Cada Polygon contém pelo menos cabeçalho e contagem de anéis.
      requireBytes(count * 9);
      return {
        'type': 'MultiPolygon',
        'coordinates': List.generate(
          count,
          (_) => geometry(polygonOnly: true)['coordinates'],
          growable: false,
        ),
      };
    }
    if (type != 3) {
      throw FormatException('Tipo WKB não poligonal: $type.');
    }
    requireBytes(count * 4);
    final rings = List.generate(count, (_) {
      final length = integer(endian);
      requireBytes(length * 16);
      return List.generate(length, (_) {
        final lon = data.getFloat64(offset, endian);
        final lat = data.getFloat64(offset + 8, endian);
        offset += 16;
        if (!lon.isFinite ||
            !lat.isFinite ||
            lon.abs() > 180 ||
            lat.abs() > 90) {
          throw const FormatException('Coordenadas WKB inválidas.');
        }
        return [lon, lat];
      }, growable: false);
    }, growable: false);
    return {'type': 'Polygon', 'coordinates': rings};
  }

  final result = geometry();
  if (offset != data.lengthInBytes) {
    throw const FormatException('Bytes adicionais na geometria WKB.');
  }
  return result;
}
