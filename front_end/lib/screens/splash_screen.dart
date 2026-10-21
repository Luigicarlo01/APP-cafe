import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/app_bootstrap.dart';
import '../utils/app_colors.dart';
import '../widgets/partner_logos.dart';
import 'map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _bootError;

  /// Tempo mínimo da tela de abertura.
  static const Duration _minimo = Duration(milliseconds: 3000);

  @override
  void initState() {
    super.initState();

    _abrir();
  }

  Future<void> _abrir() async {
    if (mounted) setState(() => _bootError = null);
    try {
      await Future.wait([bootstrapApp(), Future<void>.delayed(_minimo)]);
    } catch (error) {
      debugPrint('Falha ao preparar os dados locais: $error');
      if (mounted) {
        setState(
          () => _bootError =
              'Não foi possível preparar os dados do aplicativo. '
              'Verifique se há espaço livre no aparelho e tente novamente.',
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),

        pageBuilder: (_, _, _) => const MapScreen(),

        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bege,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),

          child: Column(
            children: [
              // ================================================
              // LOGO PRINCIPAL DO APP
              // ================================================

              Expanded(
                flex: 5,

                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    SvgPicture.asset(
                      'assets/typica_logo_sem_borda.svg',
                      width: 240,
                    ),

                    const SizedBox(height: 40),

                    if (_bootError != null) ...[
                      Text(_bootError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _abrir,
                        child: const Text('Tentar novamente'),
                      ),
                    ] else
                      const SizedBox(
                        width: 22,
                        height: 22,

                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,

                          color: AppColors.green,
                        ),
                      ),
                  ],
                ),
              ),

              // ================================================
              // LOGOS DAS INSTITUIÇÕES
              // ================================================
              Expanded(
                flex: 2,

                child: Align(
                  alignment: Alignment.bottomCenter,

                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),

                    child: PartnerLogos(
                      altura: 48,

                      // EPAMIG:
                      // assets/logo_epamig.svg
                      //
                      // UFV:
                      // assets/logo_ufv.svg
                      //
                      // EMBRAPA CAFÉ:
                      terceiraLogoAsset: 'assets/Logo embrapa cafe.png',

                      // Ajuste o tamanho da Embrapa Café aqui.
                      fatorTerceiraLogo: 0.75,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
