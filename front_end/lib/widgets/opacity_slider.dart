import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Slider de opacidade com trilho em gradiente.
///
/// Design:
///   - Um `Container` decorativo pinta o trilho como um `LinearGradient`
///     que vai de transparente (esquerda) até a cor cheia (direita).
///     Isso deixa o gradiente sempre visível por inteiro, sem ficar
///     cortado no meio como acontece no slider padrão do Material
///     (que colore só o lado "ativo").
///   - Um `SliderTheme` sobrepõe um `Slider` real por cima, mas com
///     track transparente — o Material só cuida do thumb e da
///     interação de arrastar.
///
/// Range: 0.0 (totalmente transparente) até 1.0 (opaco).
class OpacitySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  /// Cor cheia usada como âncora do gradient (lado direito). Padrão =
  /// o MESMO verde escuro das células do mapa, pra que o trilho seja
  /// uma pré-visualização honesta do que o slider controla.
  final Color color;

  /// Se mostra o label "Opacidade" acima do trilho. Default = true
  /// (uso normal na AnalysisScreen). No modo fullscreen do mapa,
  /// passa `false` — o slider aparece flutuando sobre o mapa e não
  /// precisa da legenda pra ser entendido.
  final bool showLabel;

  const OpacitySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.color = AppColors.green,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // EdgeInsets.only: aplica cada lado independentemente.
      // Aqui: 16 nos lados, 16 no topo, 0 embaixo.
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabel) ...[
            Text(
              'Opacidade',
              // Mesmo estilo dos outros títulos de seção da AnalysisScreen
              // ('Top Genótipos', 'Top 5 — ponto selecionado').
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
          ],
          Stack(
            alignment: Alignment.center,
            children: [
              // Trilho decorativo (gradient sempre inteiro)
              Container(
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.0),
                      color,
                    ],
                  ),
                  border: Border.all(
                    color: Colors.grey.shade400,
                    width: 0.5,
                  ),
                ),
              ),

              // Slider real por cima — track transparente, só o thumb aparece
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 8,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: color.withValues(alpha: 0.15),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10,
                    elevation: 2,
                  ),
                ),
                child: Slider(
                  value: value.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
