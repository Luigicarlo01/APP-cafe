import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/bounding_box.dart';
import 'cache_paths.dart';
import 'region_cache_service.dart';
import 'region_database.dart';
import 'tile_math.dart';

/// Resultado de tentar baixar 1 tile.
enum _TileOutcome {
  written,
  skipped,
  failed,
}

class _TileResult {
  final _TileOutcome outcome;
  final int bytes;

  const _TileResult(
    this.outcome,
    this.bytes,
  );
}

/// ============================================================
/// TILE DOWNLOADER
/// ============================================================
///
/// ATENÇÃO:
///
/// Esta classe está DESATIVADA no fluxo atual do aplicativo.
///
/// O app utiliza atualmente o [BaseMapService].
///
/// Mantemos este arquivo apenas porque a lógica de cache por
/// região pode ser útil posteriormente.
///
/// O mapa-base foi alterado de CARTO para OpenStreetMap.
///
/// ============================================================

@Deprecated(
  'Substituído pelo BaseMapService — não é chamado por ninguém.',
)
class TileDownloader {
  static final TileDownloader _instance =
      TileDownloader._();

  factory TileDownloader() => _instance;

  TileDownloader._();

  // ============================================================
  // MAPA BASE
  // ============================================================

  /// OpenStreetMap.
  ///
  /// Antes:
  ///
  /// https://cartodb-basemaps-a.global.ssl.fastly.net/...
  ///
  /// Agora:
  ///
  /// https://tile.openstreetmap.org/{z}/{x}/{y}.png
  ///
  /// Não precisa de API Key.
  static const String _urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // ============================================================
  // CONFIGURAÇÕES
  // ============================================================

  static const int _maxConcurrent = 6;

  static const Duration _perTileTimeout =
      Duration(
    seconds: 6,
  );

  final Set<int> _inFlight =
      <int>{};

  // ============================================================
  // DOWNLOAD
  // ============================================================

  Future<int> download({
    required int regionId,
    required BoundingBox bbox,
    int quotaBytesPerRegion =
        30 * 1024 * 1024,
    int minZoom = 10,
    int maxZoom = 15,
  }) async {
    if (_inFlight.contains(regionId)) {
      debugPrint(
        '[tiles] download já em curso '
        'pra região #$regionId, ignorando',
      );

      return 0;
    }

    _inFlight.add(regionId);

    try {
      final chosenMax =
          TileMath.pickMaxZoom(
        bbox,
        quotaBytes:
            quotaBytesPerRegion,
        minZoom:
            minZoom,
        maxZoom:
            maxZoom,
      );

      if (chosenMax == null) {
        debugPrint(
          '[tiles] região #$regionId '
          'não cabe na quota nem no zoom '
          '$minZoom — sem download proativo.',
        );

        return 0;
      }

      final estimate =
          TileMath.estimateBytes(
        bbox,
        zMin:
            minZoom,
        zMax:
            chosenMax,
      );

      debugPrint(
        '[tiles] iniciando região #$regionId '
        'zoom $minZoom..$chosenMax '
        '(~${(estimate / 1024 / 1024).toStringAsFixed(1)} MB estimados)',
      );

      final client =
          http.Client();

      var totalBytesWritten = 0;

      var tilesWritten = 0;
      var tilesSkipped = 0;
      var tilesFailed = 0;

      try {
        for (var z = minZoom;
            z <= chosenMax;
            z++) {
          final range =
              TileMath.rangeFor(
            bbox,
            z,
          );

          final coords =
              range
                  .iterate()
                  .toList();

          for (var i = 0;
              i < coords.length;
              i += _maxConcurrent) {
            final end =
                math.min(
              i + _maxConcurrent,
              coords.length,
            );

            final chunk =
                coords.sublist(
              i,
              end,
            );

            final results =
                await Future.wait(
              chunk.map(
                (c) => _fetchAndSave(
                  client,
                  regionId,
                  c.z,
                  c.x,
                  c.y,
                ),
              ),
              eagerError:
                  false,
            );

            for (final r in results) {
              switch (r.outcome) {
                case _TileOutcome.written:
                  tilesWritten++;

                  totalBytesWritten +=
                      r.bytes;

                  break;

                case _TileOutcome.skipped:
                  tilesSkipped++;

                  break;

                case _TileOutcome.failed:
                  tilesFailed++;

                  break;
              }
            }
          }
        }
      } finally {
        client.close();
      }

      // Soma com o que já havia no cache.
      final existing =
          await RegionDatabase
              .instance
              .findById(
        regionId,
      );

      final prevTilesBytes =
          existing?.tilesBytes ??
              0;

      await RegionDatabase
          .instance
          .updateTilesInfo(
        regionId,
        tilesBytes:
            prevTilesBytes +
                totalBytesWritten,
        maxZoom:
            chosenMax,
      );

      debugPrint(
        '[tiles] fim região #$regionId '
        '| novos=$tilesWritten '
        '| existentes=$tilesSkipped '
        '| falhas=$tilesFailed '
        '| +${(totalBytesWritten / 1024 / 1024).toStringAsFixed(2)} MB',
      );

      // Mantém o controle de quota
      // utilizado originalmente pelo app.
      await RegionCacheService()
          .enforceQuota();

      return totalBytesWritten;
    } finally {
      _inFlight.remove(
        regionId,
      );
    }
  }

  // ============================================================
  // DOWNLOAD DE UM TILE
  // ============================================================

  Future<_TileResult> _fetchAndSave(
    http.Client client,
    int regionId,
    int z,
    int x,
    int y,
  ) async {
    // ----------------------------------------------------------
    // Verifica se o tile já existe no cache da região.
    // ----------------------------------------------------------

    final file =
        await CachePaths.tileFile(
      regionId,
      z,
      x,
      y,
    );

    if (await file.exists()) {
      return const _TileResult(
        _TileOutcome.skipped,
        0,
      );
    }

    // ----------------------------------------------------------
    // Verifica se o tile já existe no cache global.
    // ----------------------------------------------------------

    final baseTile =
        await CachePaths
            .baseMapTileFile(
      z,
      x,
      y,
    );

    if (await baseTile.exists()) {
      return const _TileResult(
        _TileOutcome.skipped,
        0,
      );
    }

    // ==========================================================
    // MONTA A URL DO OPENSTREETMAP
    // ==========================================================

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
                Uri.parse(
                  url,
                ),
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
          '[tiles] Erro HTTP '
          '${resp.statusCode} '
          'z=$z x=$x y=$y',
        );

        return const _TileResult(
          _TileOutcome.failed,
          0,
        );
      }

      await file.writeAsBytes(
        resp.bodyBytes,
        flush:
            false,
      );

      return _TileResult(
        _TileOutcome.written,
        resp.bodyBytes.length,
      );
    } catch (e) {
      debugPrint(
        '[tiles] erro ao baixar '
        'z=$z x=$x y=$y: $e',
      );

      return const _TileResult(
        _TileOutcome.failed,
        0,
      );
    }
  }
}