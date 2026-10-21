import 'package:flutter/material.dart';

import '../services/crop_cycle_service.dart';
import '../utils/app_colors.dart';

/// Filtro de ciclo de maturação.
///
/// Visual:
///
/// ┌─────────────────────────────────┐
/// │ Ciclo de maturação              │
/// │ [ Médio                      ▼ ] │
/// └─────────────────────────────────┘
class CycleSelectionPicker extends StatelessWidget {
  const CycleSelectionPicker({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final service =
        CropCycleService();

    return AnimatedBuilder(
      animation: service,

      builder: (
        context,
        _,
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
              // ================================================
              // TÍTULO
              // ================================================

              const Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 18,
                    color:
                        AppColors.greenDark,
                  ),

                  SizedBox(
                    width: 7,
                  ),

                  Text(
                    'Ciclo de maturação',
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
                height: 10,
              ),

              // ================================================
              // DROPDOWN
              // ================================================

              Container(
                width: double.infinity,

                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
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
                      DropdownButton<CropCycle>(
                    value: service.cycle,

                    isExpanded: true,

                    borderRadius:
                        BorderRadius.circular(
                      14,
                    ),

                    icon: const Icon(
                      Icons
                          .keyboard_arrow_down_rounded,
                    ),

                    items: CropCycle.values
                        .map(
                      (
                        ciclo,
                      ) {
                        return DropdownMenuItem<
                            CropCycle>(
                          value: ciclo,

                          child: Text(
                            ciclo.label,

                            style:
                                const TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.w500,
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

                      service.setCycle(
                        novo,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}