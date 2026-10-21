import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/map_controller_logic.dart';

class MapWidget extends StatefulWidget {
  final MapController mapController;
  final LatLng? selectedPoint;
  final Function(LatLng) onTap;

  /// Zoom máximo permitido.
  final double? maxZoom;

  /// Até qual zoom existem tiles nativos.
  final int? maxNativeZoom;

  const MapWidget({
    super.key,
    required this.mapController,
    required this.selectedPoint,
    required this.onTap,
    this.maxZoom,
    this.maxNativeZoom,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  List<LatLng> _mgShape = [];

  @override
  void initState() {
    super.initState();

    _loadMask();
  }

  // ============================================================
  // CARREGA O CONTORNO DE MINAS GERAIS
  // ============================================================

  Future<void> _loadMask() async {
    try {
      final String data =
          await rootBundle.loadString(
        'assets/mg.geojson',
      );

      final geojson =
          jsonDecode(data);

      final feature =
          geojson['features'][0];

      final coordinates =
          feature['geometry']['coordinates'][0]
              as List;

      final mgShape =
          coordinates.map<LatLng>(
        (c) {
          return LatLng(
            c[1].toDouble(),
            c[0].toDouble(),
          );
        },
      ).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _mgShape = mgShape;
      });
    } catch (e, stack) {
      debugPrint(
        '❌ Erro ao carregar mg.geojson: $e',
      );

      debugPrint(
        '❌ Stack: $stack',
      );
    }
  }

  // ============================================================
  // INTERFACE
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return FlutterMap(
      mapController:
          widget.mapController,

      options: MapOptions(
        // Centro aproximado de Minas Gerais.
        initialCenter:
            const LatLng(
          -18.5,
          -44.0,
        ),

        initialZoom:
            6,

        minZoom:
            6,

        maxZoom:
            widget.maxZoom,

        // Evita que o usuário navegue muito
        // para fora de Minas Gerais.
        cameraConstraint:
            CameraConstraint.containCenter(
          bounds:
              MapControllerLogic.mgBounds,
        ),

        // Clique no mapa.
        onTap:
            (_, point) {
          widget.onTap(
            point,
          );
        },

        interactionOptions:
            InteractionOptions(
          flags:
              InteractiveFlag.all &
                  ~InteractiveFlag.rotate,

          scrollWheelVelocity:
              0.005,

          pinchZoomThreshold:
              0.5,
        ),
      ),

      children: [
        // ======================================================
        // MAPA BASE
        // ======================================================
        //
        // Antes:
        //
        // CARTO
        // https://{s}.basemaps.cartocdn.com/...
        //
        // Agora:
        //
        // OpenStreetMap
        //
        // Não precisa de API key.
        // ======================================================

        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

          userAgentPackageName:
              'com.LuisFelipe.PlantioAPP.dev',

          maxNativeZoom:
              widget.maxNativeZoom ??
                  19,
        ),

        // ======================================================
        // CONTORNO DE MINAS GERAIS
        // ======================================================

        if (_mgShape.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points:
                    _mgShape,

                color:
                    Colors.green,

                strokeWidth:
                    3.0,
              ),
            ],
          ),

        // ======================================================
        // MARCADOR DA LOCALIZAÇÃO SELECIONADA
        // ======================================================

        if (widget.selectedPoint != null)
          MarkerLayer(
            markers: [
              Marker(
                point:
                    widget.selectedPoint!,

                width:
                    40,

                height:
                    40,

                child:
                    const Icon(
                  Icons.location_pin,
                  size:
                      40,
                  color:
                      Colors.green,
                ),
              ),
            ],
          ),

        // ======================================================
        // ATRIBUIÇÃO OPENSTREETMAP
        // ======================================================

        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
            ),
          ],
        ),
      ],
    );
  }
}