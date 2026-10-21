import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import 'map_screen.dart';

/// Tela de login — **fora de uso**.
///
/// Não há backend de autenticação: os campos nunca foram validados
/// contra nada e o botão "Entrar" só empurrava a `MapScreen`. Enquanto
/// isso, ela obrigava todo usuário a uma etapa vazia antes de usar o
/// app. O `main.dart` agora abre direto na `MapScreen`.
///
/// O arquivo fica no repo (com o layout pronto) porque conta/histórico/
/// favoritos por usuário são features planejadas — quando houver auth
/// de verdade, é aqui que se retoma.
///
/// Para reativar:
///   1. `home: const LoginScreen()` no `main.dart`.
///   2. Ligar os `validator`s a um `Form` + `GlobalKey<FormState>`.
///   3. Trocar o `Navigator.push` do "Entrar" por chamada de auth.
@Deprecated(
  'Login desligado até existir backend de autenticação. '
  'O app abre direto na MapScreen.',
)
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // SingleChildScrollView: quando o teclado aparece, a tela vira
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 150, bottom: 100),
                child: SvgPicture.asset(
                  'assets/typica_logo_sem_borda.svg',
                  width: 420,
                ),
              ),

              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 370),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10.0,
                    children: [
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Usuário',
                          hintText: 'Digite seu login',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Obrigatório';
                          return null;
                        },
                      ),
                      TextFormField(
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Senha',
                          hintText: 'Digite sua senha',
                          prefixIcon: Icon(Icons.lock),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Obrigatório';
                          return null;
                        },
                      ),

                      // Link discreto de recuperar senha — logo abaixo do
                      // campo, alinhado à direita (padrão visual comum).
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            // TODO: navegar pra ForgotPasswordScreen
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                          child: const Text('Esqueceu sua senha?'),
                        ),
                      ),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MapScreen(),
                              ),
                            );
                          },
                          child: const Text('Entrar'),
                        ),
                      ),

                      // Cadastre-se — paleta contrária ao "Entrar":
                      // fundo branco, borda verde, letra verde.
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Row(
                          children:[
                            Text('Ainda não tem login?'),
                            TextButton(
                              onPressed: () {
                                //TODO: Encamimha para a tela de cadastro
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                foregroundColor: Colors.green,
                              ),
                              child: const Text('Cadastre-se'),
                            ),
                          ],
                        )
                      ),
                    ],
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
