import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/analysis_service.dart';
import '../utils/app_colors.dart';

/// Mapa da tela de análise.
///
/// As células de recomendação são desenhadas sobre o mapa-base.
///
/// O mapa-base utiliza OpenStreetMap diretamente,
/// sem CARTO e sem necessidade de API Key.
class GenotypePlot extends StatefulWidget {
  final bool isLoading;
  final LatLng selectedPoint;
  final Function(Offset)? onMarkerMoved;

  final double minZoom;
  final double maxZoom;

  /// Opacidade das células do mapa.
  final double opacity;

  const GenotypePlot({
    super.key,
    required this.isLoading,
    required this.selectedPoint,
    this.onMarkerMoved,
    this.minZoom = 10.0,
    this.maxZoom = 17.0,
    this.opacity = 0.7,
  });

  @override
  State<GenotypePlot> createState() =>
      _GenotypePlotState();
}

class _GenotypePlotState
    extends State<GenotypePlot> {
  final MapController _mapController =
      MapController();

  /// Célula atualmente selecionada.
  GridCell? _selectedCell;

  /// Limites geográficos do município.
  LatLngBounds? _bounds;

  static const double _outerBorderWidth =
      6.0;

  static const double _innerBorderWidth =
      3.0;

  static const Color _outerBorderColor =
      Colors.black;

  static const Color _innerBorderColor =
      Colors.white;

  @override
  void initState() {
    super.initState();

    _selectedCell =
        AnalysisService().resolveCell(
      Offset(
        widget.selectedPoint.longitude,
        widget.selectedPoint.latitude,
      ),
    );

    final cells =
        AnalysisService().cells;

    if (cells.isNotEmpty) {
      _bounds =
          _computeBounds(cells);

      WidgetsBinding.instance
          .addPostFrameCallback(
        (_) {
          if (!mounted ||
              _bounds == null) {
            return;
          }

          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: _bounds!,
              padding:
                  const EdgeInsets.only(
                left: 24,
                right: 72,
                top: 48,
                bottom: 48,
              ),
              forceIntegerZoomLevel:
                  false,
            ),
          );
        },
      );
    }
  }

  // ============================================================
  // CALCULAR OS LIMITES DO MUNICÍPIO
  // ============================================================

  LatLngBounds _computeBounds(
    List<GridCell> cells,
  ) {
    double minLat =
        double.infinity;

    double maxLat =
        -double.infinity;

    double minLng =
        double.infinity;

    double maxLng =
        -double.infinity;

    for (final cell in cells) {
      for (final p in cell.points) {
        if (p.dy < minLat) {
          minLat = p.dy;
        }

        if (p.dy > maxLat) {
          maxLat = p.dy;
        }

        if (p.dx < minLng) {
          minLng = p.dx;
        }

        if (p.dx > maxLng) {
          maxLng = p.dx;
        }
      }
    }

    return LatLngBounds(
      LatLng(
        minLat,
        minLng,
      ),
      LatLng(
        maxLat,
        maxLng,
      ),
    );
  }

  // ============================================================
  // IMPEDE O MAPA DE SAIR MUITO DA ÁREA ANALISADA
  // ============================================================

  void _onPositionChanged(
    MapCamera camera,
    bool hasGesture,
  ) {
    if (!hasGesture ||
        _bounds == null) {
      return;
    }

    final center =
        camera.center;

    final b =
        _bounds!;

    if (!b.contains(center)) {
      _mapController.move(
        LatLng(
          center.latitude.clamp(
            b.south,
            b.north,
          ),
          center.longitude.clamp(
            b.west,
            b.east,
          ),
        ),
        camera.zoom,
      );
    }
  }

  // ============================================================
  // CLIQUE EM UMA CÉLULA
  // ============================================================

  void _onTap(
    TapPosition _,
    LatLng latlng,
  ) {
    final geo =
        Offset(
      latlng.longitude,
      latlng.latitude,
    );

    final cell =
        AnalysisService()
            .cellContaining(
      geo,
    );

    if (cell == null) {
      return;
    }

    setState(
      () {
        _selectedCell =
            cell;
      },
    );

    widget.onMarkerMoved?.call(
      cell.centroid,
    );
  }

  // ============================================================
  // DESTACAR A CÉLULA SELECIONADA
  // ============================================================

  List<Polygon>
      _buildHighlightPolygons() {
    final cell =
        _selectedCell;

    if (cell == null) {
      return const [];
    }

    final points =
        cell.points
            .map(
              (o) => LatLng(
                o.dy,
                o.dx,
              ),
            )
            .toList();

    return [
      // Borda preta externa.
      Polygon(
        points: points,
        color:
            Colors.transparent,
        borderColor:
            _outerBorderColor,
        borderStrokeWidth:
            _outerBorderWidth,
      ),

      // Borda branca interna.
      Polygon(
        points: points,
        color:
            Colors.transparent,
        borderColor:
            _innerBorderColor,
        borderStrokeWidth:
            _innerBorderWidth,
      ),
    ];
  }

  // ============================================================
  // INTERFACE
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (widget.isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    final cells =
        AnalysisService().cells;

    if (cells.isEmpty) {
      return const ColoredBox(
        color:
            AppColors.bege,
        child:
            Center(
          child:
              Text(
            'Sem dados',
          ),
        ),
      );
    }

    // Polígonos da recomendação.
    final polygons =
        AnalysisService()
            .polygonsFor(
      widget.opacity,
    );

    _bounds ??=
        _computeBounds(
      cells,
    );

    if (_selectedCell == null) {
      _selectedCell =
          AnalysisService()
              .resolveCell(
        Offset(
          widget
              .selectedPoint
              .longitude,
          widget
              .selectedPoint
              .latitude,
        ),
      );
    }

    return ColoredBox(
      color:
          Colors.grey.shade200,

      child:
          Stack(
        children: [
          // =====================================================
          // MAPA
          // =====================================================

          FlutterMap(
            mapController:
                _mapController,

            options:
                MapOptions(
              initialCameraFit:
                  CameraFit.bounds(
                bounds:
                    _bounds!,
                padding:
                    const EdgeInsets.only(
                  left: 24,
                  right: 72,
                  top: 48,
                  bottom: 48,
                ),
                forceIntegerZoomLevel:
                    false,
              ),

              minZoom:
                  widget.minZoom,

              maxZoom:
                  widget.maxZoom,

              onTap:
                  _onTap,

              onPositionChanged:
                  _onPositionChanged,

              interactionOptions:
                  const InteractionOptions(
                flags:
                    InteractiveFlag
                            .pinchZoom |
                        InteractiveFlag
                            .drag |
                        InteractiveFlag
                            .doubleTapZoom |
                        InteractiveFlag
                            .doubleTapDragZoom,
              ),
            ),

            children: [
              // =================================================
              // OPENSTREETMAP
              // =================================================

              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

                userAgentPackageName:
                    'com.LuisFelipe.PlantioAPP.dev',

                maxNativeZoom:
                    19,
              ),

              // =================================================
              // CÉLULAS DE RECOMENDAÇÃO
              // =================================================

              RepaintBoundary(
                child:
                    PolygonLayer(
                  useAltRendering:
                      true,

                  polygons:
                      polygons,
                ),
              ),

              // =================================================
              // CÉLULA SELECIONADA
              // =================================================

              PolygonLayer(
                polygons:
                    _buildHighlightPolygons(),
              ),
            ],
          ),

          // =====================================================
          // ATRIBUIÇÃO OPENSTREETMAP
          // =====================================================
          //
          // Texto pequeno e discreto.
          //
          // Não existe mais aquele botão/ícone do
          // RichAttributionWidget.
          // =====================================================

          Positioned(
            left: 4,
            bottom: 3,

            child:
                Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),

              decoration:
                  BoxDecoration(
                color:
                    Colors.white
                        .withOpacity(
                  0.75,
                ),

                borderRadius:
                    BorderRadius.circular(
                  3,
                ),
              ),

              child:
                  const Text(
                '© OpenStreetMap contributors',

                style:
                    TextStyle(
                  fontSize:
                      8,

                  color:
                      Colors.black54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FINALIZAÇÃO
  // ============================================================

  @override
  void dispose() {
    _mapController.dispose();

    super.dispose();
  }
}