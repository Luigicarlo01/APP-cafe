import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../controllers/map_controller_logic.dart';
import '../../models/bounding_box.dart';
import 'cache_paths.dart';
import 'tile_math.dart';

/// Serviço responsável pelo cache do mapa-base.
///
/// O mapa-base agora utiliza OpenStreetMap em vez de CARTO.
///
/// IMPORTANTE:
/// O servidor público do OpenStreetMap é adequado para exibição normal
/// do mapa, mas não deve ser usado para pré-download massivo de tiles
/// em produção.
///
/// Durante o desenvolvimento/debug, deixe o download offline do mapa-base
/// desativado. O mapa online continuará funcionando normalmente.
class BaseMapService extends ChangeNotifier {
  static final BaseMapService _instance =
      BaseMapService._();

  factory BaseMapService() => _instance;

  BaseMapService._();

  // ============================================================
  // MAPA BASE
  // ============================================================

  /// OpenStreetMap.
  ///
  /// Não utiliza:
  ///
  /// {s}
  /// a.basemaps...
  /// b.basemaps...
  ///
  /// portanto não precisamos mais de subdomains.
  static const String _urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // ============================================================
  // CONFIGURAÇÃO DO CACHE
  // ============================================================

  /// Zoom mínimo do mapa offline.
  static const int _minZoom = 6;

  /// Zoom máximo do mapa offline.
  static const int _maxZoom = 10;

  /// Número máximo de operações paralelas.
  static const int _maxConcurrent = 4;

  /// Timeout por tile.
  static const Duration _perTileTimeout =
      Duration(seconds: 8);

  /// Arquivo utilizado para indicar que um download
  /// de mapa-base foi concluído.
  static const String _sentinelFileName =
      '.complete';

  // ============================================================
  // ESTADO
  // ============================================================

  bool _isDownloading = false;

  bool get isDownloading =>
      _isDownloading;

  bool _isDownloaded = false;

  bool get isDownloaded =>
      _isDownloaded;

  double _progress = 0.0;

  double get progress =>
      _progress;

  int _sizeBytes = 0;

  int get sizeBytes =>
      _sizeBytes;

  int _tileCount = 0;

  int get tileCount =>
      _tileCount;

  // ============================================================
  // VERIFICAR CACHE EXISTENTE
  // ============================================================

  Future<void> refreshStatus() async {
    final dir =
        await CachePaths.baseMapDir();

    final sentinel =
        File(
      p.join(
        dir.path,
        _sentinelFileName,
      ),
    );

    _isDownloaded =
        await sentinel.exists();

    int size = 0;
    int count = 0;

    if (await dir.exists()) {
      await for (final entity
          in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            entity.path.endsWith('.png')) {
          try {
            size +=
                await entity.length();

            count++;
          } catch (_) {
            // Ignora arquivos individuais
            // que não puderam ser lidos.
          }
        }
      }
    }

    _sizeBytes = size;
    _tileCount = count;

    notifyListeners();
  }

  // ============================================================
  // ESTIMATIVAS
  // ============================================================

  int estimateBytes({
    int avgBytesPerTile =
        7 * 1024,
  }) {
    final bbox =
        _mgBoundingBox();

    return TileMath.estimateBytes(
      bbox,
      zMin: _minZoom,
      zMax: _maxZoom,
      avgBytesPerTile:
          avgBytesPerTile,
    );
  }

  int estimateTiles() {
    final bbox =
        _mgBoundingBox();

    var total = 0;

    for (var z = _minZoom;
        z <= _maxZoom;
        z++) {
      total +=
          TileMath.rangeFor(
        bbox,
        z,
      ).count;
    }

    return total;
  }

  // ============================================================
  // DOWNLOAD DO MAPA BASE
  // ============================================================

  /// Atenção:
  ///
  /// O OpenStreetMap público não deve ser utilizado
  /// para download em massa de mapas.
  ///
  /// Por isso esta função fica DESATIVADA enquanto
  /// estivermos usando tile.openstreetmap.org.
  ///
  /// Isso NÃO impede o mapa normal de funcionar.
  Future<void> download() async {
    debugPrint(
      '[base_map] Download offline desativado '
      'para o servidor público do OpenStreetMap.',
    );

    debugPrint(
      '[base_map] O mapa online continua funcionando normalmente.',
    );

    return;
  }

  // ============================================================
  // APAGAR CACHE ANTIGO
  // ============================================================

  /// Apaga todos os tiles anteriormente armazenados.
  ///
  /// Isso é importante agora porque você tinha tiles
  /// antigos da CARTO com "API KEY REQUIRED".
  Future<void> delete() async {
    final dir =
        await CachePaths.baseMapDir();

    if (await dir.exists()) {
      await dir.delete(
        recursive: true,
      );
    }

    _isDownloaded = false;
    _sizeBytes = 0;
    _tileCount = 0;
    _progress = 0.0;

    notifyListeners();

    debugPrint(
      '[base_map] Cache antigo apagado.',
    );
  }

  // ============================================================
  // DOWNLOAD INDIVIDUAL
  // ============================================================
  //
  // Mantemos esta função no arquivo para que a estrutura
  // original do projeto continue disponível.
  //
  // Ela não é chamada atualmente por download(), pois
  // o pré-download foi desativado.
  // ============================================================

  Future<int> _fetchAndSave(
    http.Client client,
    int z,
    int x,
    int y,
  ) async {
    final file =
        await CachePaths
            .baseMapTileFile(
      z,
      x,
      y,
    );

    if (await file.exists()) {
      return 0;
    }

    // ==========================================================
    // OPENSTREETMAP
    // ==========================================================
    //
    // Antes:
    //
    // https://{s}.basemaps.cartocdn.com/...
    //
    // Agora:
    //
    // https://tile.openstreetmap.org/...
    //
    final url =
        _urlTemplate
            .replaceAll(
              '{z}',
              '$z',
            )
            .replaceAll(
              '{x}',
              '$x',
            )
            .replaceAll(
              '{y}',
              '$y',
            );

    try {
      final resp =
          await client
              .get(
                Uri.parse(url),
                headers: const {
                  'User-Agent':
                      'PlantioAPP/1.0',
                },
              )
              .timeout(
                _perTileTimeout,
              );

      if (resp.statusCode !=
          200) {
        debugPrint(
          '[base_map] HTTP '
          '${resp.statusCode} '
          'z=$z x=$x y=$y',
        );

        return 0;
      }

      await file.writeAsBytes(
        resp.bodyBytes,
        flush: false,
      );

      return resp.bodyBytes.length;
    } catch (e) {
      debugPrint(
        '[base_map] Falha no tile '
        'z=$z x=$x y=$y: $e',
      );

      return 0;
    }
  }

  // ============================================================
  // BOUNDING BOX DE MINAS GERAIS
  // ============================================================

  BoundingBox _mgBoundingBox() {
    final b =
        MapControllerLogic.mgBounds;

    return BoundingBox(
      minLat: b.south,
      maxLat: b.north,
      minLon: b.west,
      maxLon: b.east,
    );
  }
}