import 'package:flutter/material.dart';

import '../controllers/analysis_controller.dart';
import '../utils/app_colors.dart';
import 'genotype_detail_card.dart';

class GenotypeList extends StatelessWidget {
  final List<RecommendedCultivar> cultivares;

  final String? selectedGenotype;

  final ValueChanged<String> onSelect;

  final String? municipio;

  const GenotypeList({
    super.key,
    required this.cultivares,
    required this.selectedGenotype,
    required this.onSelect,
    required this.municipio,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    if (cultivares.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ),

      child: Column(
        children: [
          for (final cultivar in cultivares) ...[
            // ==================================================
            // CULTIVAR
            // ==================================================

            _CultivarItem(
              cultivar: cultivar,

              isSelected:
                  selectedGenotype ==
                      cultivar.nome,

              onTap: () {
                onSelect(
                  cultivar.nome,
                );
              },
            ),

            // ==================================================
            // DETALHES DA CULTIVAR
            // ==================================================

            if (selectedGenotype ==
                cultivar.nome)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: 9,
                ),

                child: GenotypeDetailCard(
                  genotype:
                      cultivar.nome,

                  municipio:
                      municipio,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// =============================================================
// ITEM DA CULTIVAR
// =============================================================

class _CultivarItem
    extends StatelessWidget {
  final RecommendedCultivar cultivar;

  final bool isSelected;

  final VoidCallback onTap;

  const _CultivarItem({
    required this.cultivar,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 7,
      ),

      child: Material(
        color: Colors.transparent,

        child: InkWell(
          onTap: onTap,

          borderRadius:
              BorderRadius.circular(
            11,
          ),

          child: AnimatedContainer(
            duration: const Duration(
              milliseconds: 150,
            ),

            width: double.infinity,

            constraints:
                const BoxConstraints(
              minHeight: 48,
            ),

            padding:
                const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 9,
            ),

            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.green
                      .withOpacity(
                        0.11,
                      )
                  : Colors.white,

              borderRadius:
                  BorderRadius.circular(
                11,
              ),

              border: Border.all(
                color: isSelected
                    ? AppColors.green
                    : Colors.black
                        .withOpacity(
                          0.10,
                        ),

                width:
                    isSelected
                        ? 1.4
                        : 1,
              ),
            ),

            child: Row(
              children: [
                // ==============================================
                // NOME DA CULTIVAR
                // ==============================================

                Expanded(
                  child: Text(
                    cultivar.nome,

                    maxLines: 2,

                    overflow:
                        TextOverflow
                            .ellipsis,

                    style:
                        const TextStyle(
                      fontSize: 14.5,

                      height: 1.15,

                      fontWeight:
                          FontWeight.w600,

                      color:
                          Colors.black87,
                    ),
                  ),
                ),

                const SizedBox(
                  width: 8,
                ),

                // ==============================================
                // SETA ABRIR / FECHAR
                // ==============================================

                Icon(
                  isSelected
                      ? Icons
                          .keyboard_arrow_up
                      : Icons
                          .keyboard_arrow_down,

                  size: 21,

                  color: isSelected
                      ? AppColors.greenDark
                      : Colors.black45,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}