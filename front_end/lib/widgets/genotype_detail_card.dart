import 'package:flutter/material.dart';

import '../services/cultivar_info_service.dart';
import '../utils/app_colors.dart';

class GenotypeDetailCard extends StatelessWidget {
  final String genotype;
  final String? municipio;

  const GenotypeDetailCard({
    super.key,
    required this.genotype,
    this.municipio,
  });

  @override
  Widget build(BuildContext context) {
    final info =
        CultivarInfoService().infoFor(
      genotype,
    );

    // ==========================================================
    // SEM INFORMAÇÕES
    // ==========================================================

    if (info == null) {
      return Container(
        width: double.infinity,

        padding: const EdgeInsets.all(
          14,
        ),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius:
              BorderRadius.circular(
            12,
          ),

          border: Border.all(
            color: Colors.black.withOpacity(
              0.08,
            ),
          ),
        ),

        child: Text(
          'Informações adicionais não disponíveis.',

          style: TextStyle(
            fontSize: 13,

            color:
                Colors.black.withOpacity(
              0.55,
            ),
          ),
        ),
      );
    }

    // ==========================================================
    // FICHA
    // ==========================================================

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(
        14,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(
          12,
        ),

        border: Border.all(
          color: AppColors.green.withOpacity(
            0.25,
          ),
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              0.025,
            ),

            blurRadius: 5,

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

          Row(
            children: [
              Expanded(
                child: Text(
                  genotype,

                  style:
                      const TextStyle(
                    fontSize: 15,

                    fontWeight:
                        FontWeight.w700,

                    color:
                        AppColors.greenDark,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          // ====================================================
          // CICLO
          // ====================================================

          if (_temValor(
            info.maturacao,
          ))
            _InfoRow(
              icon:
                  Icons.schedule_outlined,

              label:
                  'Ciclo de maturação',

              value:
                  info.maturacao!,
            ),

          // ====================================================
          // NÍVEL TECNOLÓGICO
          // ====================================================

          if (_temValor(
            info.nivelTecnologico,
          ))
            _InfoRow(
              icon:
                  Icons.agriculture_outlined,

              label:
                  'Nível tecnológico',

              value:
                  info.nivelTecnologico!,
            ),

          // ====================================================
          // FERRUGEM
          // ====================================================

          if (_temValor(
            info.ferrugem,
          ))
            _InfoRow(
              icon:
                  Icons.grass_outlined,

              label:
                  'Ferrugem',

              value:
                  info.ferrugem!,
            ),

          // ====================================================
          // NEMATÓIDE
          // ====================================================

          if (_temValor(
            info.nematoide,
          ))
            _InfoRow(
              icon:
                  Icons.bug_report_outlined,

              label:
                  'Nematóide',

              value:
                  info.nematoide!,
            ),

          // ====================================================
          // DETALHE DO NEMATÓIDE
          // ====================================================

          if (_temValor(
            info.nematoideDetalhe,
          ))
            _InfoRow(
              icon:
                  Icons.info_outline,

              label:
                  'Detalhe do nematóide',

              value:
                  info.nematoideDetalhe!,
            ),
        ],
      ),
    );
  }

  // ============================================================
  // TESTAR VALOR
  // ============================================================

  static bool _temValor(
    String? value,
  ) {
    return value != null &&
        value.trim().isNotEmpty;
  }
}

// =============================================================
// LINHA DE INFORMAÇÃO
// =============================================================

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),

      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          // ====================================================
          // ÍCONE
          // ====================================================

          Padding(
            padding:
                const EdgeInsets.only(
              top: 1,
            ),

            child: Icon(
              icon,

              size: 17,

              color:
                  AppColors.greenDark,
            ),
          ),

          const SizedBox(
            width: 9,
          ),

          // ====================================================
          // TEXTO
          // ====================================================

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  label,

                  style: TextStyle(
                    fontSize: 11.5,

                    color:
                        Colors.black.withOpacity(
                      0.50,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  value,

                  style:
                      const TextStyle(
                    fontSize: 13.5,

                    fontWeight:
                        FontWeight.w600,

                    color:
                        Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}