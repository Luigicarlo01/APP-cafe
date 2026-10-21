import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/onboarding_service.dart';
import '../utils/app_colors.dart';
import '../widgets/partner_logos.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bege,
      appBar: AppBar(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Sobre o app'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            children: [
              SvgPicture.asset(
                'assets/typica_logo_sem_borda.svg',
                width: 200,
              ),
              const SizedBox(height: 20),
              Text(
                'Recomendação de cultivares de café para Minas Gerais, '
                'com granularidade de célula e uso sem internet no campo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: Colors.black.withValues(alpha: 0.7),
                ),
              ),

              const SizedBox(height: 36),
              const _Secao(titulo: 'Instituições parceiras'),
              const SizedBox(height: 20),
              const PartnerLogos(altura: 56),

              const SizedBox(height: 36),
              const _Secao(titulo: 'Origem dos dados'),
              const SizedBox(height: 12),
              const _Paragrafo(
                'As recomendações vêm da análise agronômica processada '
                'sobre a malha de municípios do IBGE.',
              ),
              const SizedBox(height: 8),
              const _Paragrafo(
                'A ficha de cada cultivar — resistência a ferrugem e '
                'nematóide e produtividade medida — vem dos ensaios de '
                'campo, e sempre indica o ano e quantas medições '
                'sustentam o número.',
              ),
              const SizedBox(height: 8),
              const _Paragrafo(
                'O mapa base usa tiles do CARTO sobre dados do '
                'OpenStreetMap.',
              ),

              const SizedBox(height: 36),
              const _Secao(titulo: 'Versão'),
              const SizedBox(height: 12),
              // FutureBuilder porque `PackageInfo` é assíncrono
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox(height: 20);
                  final info = snapshot.data!;
                  return _Paragrafo(
                    '${info.version} (build ${info.buildNumber})',
                  );
                },
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 36),
                const _Secao(titulo: 'Desenvolvimento'),
                const SizedBox(height: 12),
                const _ResetTutoriais(),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão que apaga as sentinelas dos tutoriais. Visível só em debug.
class _ResetTutoriais extends StatelessWidget {
  const _ResetTutoriais();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        await OnboardingService().resetAll();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tutoriais reiniciados. Feche e abra o app para ver a '
              'tela inicial, e entre numa análise para ver a outra.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      },
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Reapresentar tutoriais'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.greenDark,
        side: BorderSide(color: AppColors.greenDark.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

/// Título de seção — pequeno, espaçado, em maiúsculas de baixo contraste.
/// Separa os blocos sem competir com o conteúdo.
class _Secao extends StatelessWidget {
  final String titulo;

  const _Secao({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.black.withValues(alpha: 0.12))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            titulo.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.black.withValues(alpha: 0.12))),
      ],
    );
  }
}

class _Paragrafo extends StatelessWidget {
  final String texto;

  const _Paragrafo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13.5,
        height: 1.5,
        color: Colors.black.withValues(alpha: 0.65),
      ),
    );
  }
}
