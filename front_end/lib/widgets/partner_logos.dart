import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PartnerLogos extends StatelessWidget {
  final double altura;

  /// Terceira logo opcional.
  final String? terceiraLogoAsset;

  /// Tamanho da terceira logo em relação à logo da UFV.
  final double fatorTerceiraLogo;

  static const double _fatorEpamig = 0.60;

  const PartnerLogos({
    super.key,
    this.altura = 52,
    this.terceiraLogoAsset,
    this.fatorTerceiraLogo = 0.75,
  });

  Widget _buildLogo(
    String asset,
    double height,
  ) {
    final lower = asset.toLowerCase();

    // SVG
    if (lower.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        height: height,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
    }

    // PNG, JPG, JPEG etc.
    return Image.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final terceira =
        terceiraLogoAsset?.trim();

    final temTerceira =
        terceira != null &&
        terceira.isNotEmpty;

    return Semantics(
      label: temTerceira
          ? 'Instituições parceiras: EPAMIG, UFV e Embrapa Café'
          : 'Instituições parceiras: EPAMIG e UFV',

      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.center,

        crossAxisAlignment:
            CrossAxisAlignment.center,

        mainAxisSize:
            MainAxisSize.min,

        children: [
          // ==========================================
          // EPAMIG
          // ==========================================

          SvgPicture.asset(
            'assets/logo_epamig.svg',
            height:
                altura * _fatorEpamig,
            fit:
                BoxFit.contain,
            excludeFromSemantics:
                true,
          ),

          SizedBox(
            width:
                altura * 0.40,
          ),

          // ==========================================
          // UFV
          // ==========================================

          SvgPicture.asset(
            'assets/logo_ufv.svg',
            height:
                altura,
            fit:
                BoxFit.contain,
            excludeFromSemantics:
                true,
          ),

          // ==========================================
          // EMBRAPA CAFÉ
          // ==========================================

          if (temTerceira) ...[
            SizedBox(
              width:
                  altura * 0.40,
            ),

            _buildLogo(
              terceira,
              altura *
                  fatorTerceiraLogo,
            ),
          ],
        ],
      ),
    );
  }
}