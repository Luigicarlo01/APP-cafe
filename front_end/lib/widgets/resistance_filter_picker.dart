import 'package:flutter/material.dart';

import '../controllers/analysis_controller.dart';
import '../utils/app_colors.dart';

/// Filtros de resistência.
///
/// Visual:
///
/// ┌─────────────────────────────────────┐
/// │ Filtros de resistência              │
/// │                                     │
/// │ Ferrugem           Nematóide         │
/// │ [ Todos ▼ ]        [ Todos ▼ ]       │
/// └─────────────────────────────────────┘
class ResistanceFilterPicker
    extends StatelessWidget {
  final ResistanceFilter ferrugem;

  final ResistanceFilter nematoide;

  final ValueChanged<ResistanceFilter>
      onFerrugemChanged;

  final ValueChanged<ResistanceFilter>
      onNematoideChanged;

  const ResistanceFilterPicker({
    super.key,
    required this.ferrugem,
    required this.nematoide,
    required this.onFerrugemChanged,
    required this.onNematoideChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(
        14,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(
          16,
        ),

        border: Border.all(
          color: Colors.black.withOpacity(
            0.08,
          ),
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              0.035,
            ),

            blurRadius: 6,

            offset: const Offset(
              0,
              2,
            ),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          // ====================================================
          // TÍTULO
          // ====================================================

          const Row(
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 18,
                color:
                    AppColors.greenDark,
              ),

              SizedBox(
                width: 7,
              ),

              Text(
                'Filtros de resistência',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight:
                      FontWeight.w700,
                  color:
                      AppColors.greenDark,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 14,
          ),

          // ====================================================
          // FERRUGEM + NEMATÓIDE
          // ====================================================

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [
              // ================================================
              // FERRUGEM
              // ================================================

              Expanded(
                child:
                    _ResistanceDropdown(
                  label: 'Ferrugem',

                  icon:
                      Icons.grass_outlined,

                  value: ferrugem,

                  onChanged:
                      onFerrugemChanged,
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              // ================================================
              // NEMATÓIDE
              // ================================================

              Expanded(
                child:
                    _ResistanceDropdown(
                  label: 'Nematóide',

                  icon: Icons
                      .bug_report_outlined,

                  value: nematoide,

                  onChanged:
                      onNematoideChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================
// DROPDOWN
// =============================================================

class _ResistanceDropdown
    extends StatelessWidget {
  final String label;

  final IconData icon;

  final ResistanceFilter value;

  final ValueChanged<ResistanceFilter>
      onChanged;

  const _ResistanceDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [
        // ======================================================
        // LABEL
        // ======================================================

        Row(
          children: [
            Icon(
              icon,

              size: 15,

              color:
                  Colors.black54,
            ),

            const SizedBox(
              width: 5,
            ),

            Expanded(
              child: Text(
                label,

                maxLines: 1,

                overflow:
                    TextOverflow.ellipsis,

                style:
                    const TextStyle(
                  fontSize: 12.5,
                  fontWeight:
                      FontWeight.w600,
                  color:
                      Colors.black87,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 6,
        ),

        // ======================================================
        // CAIXA
        // ======================================================

        Container(
          width: double.infinity,

          height: 46,

          padding:
              const EdgeInsets.symmetric(
            horizontal: 9,
          ),

          decoration: BoxDecoration(
            color: AppColors.bege
                .withOpacity(
              0.45,
            ),

            borderRadius:
                BorderRadius.circular(
              12,
            ),

            border: Border.all(
              color: Colors.black
                  .withOpacity(
                0.10,
              ),
            ),
          ),

          child:
              DropdownButtonHideUnderline(
            child:
                DropdownButton<
                    ResistanceFilter>(
              value: value,

              isExpanded: true,

              borderRadius:
                  BorderRadius.circular(
                14,
              ),

              icon: const Icon(
                Icons
                    .keyboard_arrow_down_rounded,

                size: 20,
              ),

              // ================================================
              // VALOR EXIBIDO QUANDO FECHADO
              // ================================================

              selectedItemBuilder:
                  (
                context,
              ) {
                return ResistanceFilter
                    .values
                    .map(
                  (
                    filtro,
                  ) {
                    return Align(
                      alignment:
                          Alignment.centerLeft,

                      child: Text(
                        _shortLabel(
                          filtro,
                        ),

                        maxLines: 1,

                        overflow:
                            TextOverflow
                                .ellipsis,

                        style:
                            const TextStyle(
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ).toList();
              },

              // ================================================
              // OPÇÕES
              // ================================================

              items:
                  ResistanceFilter
                      .values
                      .map(
                (
                  filtro,
                ) {
                  return DropdownMenuItem<
                      ResistanceFilter>(
                    value: filtro,

                    child: Text(
                      filtro.label,

                      style:
                          const TextStyle(
                        fontSize: 13,
                      ),
                    ),
                  );
                },
              ).toList(),

              onChanged: (
                novo,
              ) {
                if (novo == null) {
                  return;
                }

                onChanged(
                  novo,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // TEXTO CURTO MOSTRADO NA CAIXA FECHADA
  // ===========================================================
  //
  // Isso evita que:
  //
  // "Moderadamente resistente"
  //
  // fique cortado quando os dois filtros estão lado a lado.
  //
  // No menu aberto aparece o nome completo.
  // ===========================================================

  String _shortLabel(
    ResistanceFilter filtro,
  ) {
    switch (filtro) {
      case ResistanceFilter.todos:
        return 'Todos';

      case ResistanceFilter.resistente:
        return 'Resistente';

      case ResistanceFilter
            .moderadamenteResistente:
        return 'Moderado';

      case ResistanceFilter.suscetivel:
        return 'Suscetível';
    }
  }
}