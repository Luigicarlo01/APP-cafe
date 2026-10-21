import 'package:flutter/material.dart';
import '../services/analysis_service.dart';

/// Plot de pontos em canvas puro — **fora de uso**.
///
/// Foi o primeiro desenho da análise, antes do `GenotypePlot` sobre o
/// `flutter_map`. Desenhava um marker por célula, colorido por
/// genótipo. Nenhuma tela o monta desde então, e a coloração por
/// genótipo saiu de cena com o mapa monocromático.
///
/// Mantido como referência do cálculo de projeção geo → pixel, útil
/// se um dia precisarmos de um mini-mapa sem tiles.
@Deprecated(
  'Substituído pelo GenotypePlot (flutter_map). Sem uso no app.',
)
class PointsPlot extends StatefulWidget {
  final List<Offset> points;
  final List<Color>? pointColors;
  final double pointRadius;
  final Color pointColor;
  final Offset? initialMarker; // 👈 posição inicial em coordenadas geo
  final Function(Offset)? onMarkerMoved; // 👈 callback com coordenada geo

  const PointsPlot({
    super.key,
    required this.points,
    this.pointColors,
    this.pointRadius = 6,
    this.pointColor = Colors.red,
    this.initialMarker,
    this.onMarkerMoved,
  });

  @override
  State<PointsPlot> createState() => _PointsPlotState();
}

class _PointsPlotState extends State<PointsPlot> {
  Offset? _markerPixel; // posição do marker em pixels

  // Parâmetros de escala — calculados no build e reutilizados no gesture
  double _minX = 0, _minY = 0, _scaleFactor = 1;
  double _offsetX = 0, _offsetY = 0;
  double _canvasHeight = 0;

  Offset _toPixel(Offset geo) {
    final x = (geo.dx - _minX) * _scaleFactor + _offsetX;
    final y = _canvasHeight - ((geo.dy - _minY) * _scaleFactor + _offsetY);
    return Offset(x, y);
  }

  Offset _toGeo(Offset pixel) {
    final x = (pixel.dx - _offsetX) / _scaleFactor + _minX;
    final y = (_canvasHeight - pixel.dy - _offsetY) / _scaleFactor + _minY;
    return Offset(x, y);
  }

  void _updateMarker(Offset pixelPosition) {
    final geoPos = _toGeo(pixelPosition);

    // Verifica se está dentro de alguma célula
    final cell = AnalysisService().cellContaining(geoPos);
    if (cell == null) return; // rejeita se fora de todas as células

    setState(() => _markerPixel = pixelPosition);
    widget.onMarkerMoved?.call(geoPos);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        if (widget.points.isEmpty) return SizedBox(width: width, height: height);

        _minX = widget.points.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
        final maxX = widget.points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
        _minY = widget.points.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
        final maxY = widget.points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);

        final mapWidth = maxX - _minX;
        final mapHeight = maxY - _minY;

        const paddingFactor = 0.05;
        final paddedWidth = width * (1 - 2 * paddingFactor);
        final paddedHeight = height * (1 - 2 * paddingFactor);

        final scaleX = paddedWidth / mapWidth;
        final scaleY = paddedHeight / mapHeight;
        _scaleFactor = scaleX < scaleY ? scaleX : scaleY;

        _offsetX = (width - mapWidth * _scaleFactor) / 2;
        _offsetY = (height - mapHeight * _scaleFactor) / 2;
        _canvasHeight = height;

        final scaledPoints = widget.points.map(_toPixel).toList();


        // Inicializa marker na célula mais próxima do selectedPoint
        if (_markerPixel == null && widget.initialMarker != null) {
          final nearest = AnalysisService().nearestCellCentroid(widget.initialMarker!);
          _markerPixel = _toPixel(nearest);
        }

        return GestureDetector(
          onPanUpdate: (details) => _updateMarker(details.localPosition),
          onTapDown: (details) => _updateMarker(details.localPosition),
          child: CustomPaint(
            size: Size(width, height),
            painter: _PointsPainter(
              points: scaledPoints,
              radius: widget.pointRadius,
              defaultColor: widget.pointColor,
              colors: widget.pointColors,
              markerPosition: _markerPixel,
            ),
          ),
        );
      },
    );
  }
}

class _PointsPainter extends CustomPainter {
  final List<Offset> points;
  final double radius;
  final Color defaultColor;
  final List<Color>? colors;
  final Offset? markerPosition;

  _PointsPainter({
    required this.points,
    required this.radius,
    required this.defaultColor,
    this.colors,
    this.markerPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Desenha os pontos
    for (int i = 0; i < points.length; i++) {
      final paint = Paint()
        ..color = colors != null && i < colors!.length
            ? colors![i]
            : defaultColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(points[i], radius, paint);
    }

    // Desenha o marker por cima
    if (markerPosition != null) {
      // Sombra
      canvas.drawCircle(
        markerPosition!,
        14,
        Paint()..color = Colors.black.withValues(alpha: 0.2),
      );
      // Círculo externo branco
      canvas.drawCircle(
        markerPosition!,
        12,
        Paint()..color = Colors.white,
      );
      // Círculo interno verde
      canvas.drawCircle(
        markerPosition!,
        8,
        Paint()..color = const Color(0xFF02890A),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PointsPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.colors != colors ||
        oldDelegate.markerPosition != markerPosition;
  }
}