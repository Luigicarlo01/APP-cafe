import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../screens/history_screen.dart';

/// Drawer lateral global do app — **fora de uso**.
///
/// Todos os quatro itens ("Conta", "Meu Formulário", "Locais
/// Favoritados", "Histórico de acessos") navegavam pra mesma
/// `HistoryScreen`: o menu prometia quatro destinos e entregava um.
/// Como as features por trás dele dependem de login (que também está
/// deprecated), o `MapScreen` deixou de declarar `drawer:` e o
/// hambúrguer sumiu da AppBar.
///
/// O arquivo fica no repo porque o menu volta junto com a conta de
/// usuário. Para reativar: `drawer: const AppDrawer()` no Scaffold do
/// `MapScreen` e apontar cada ListTile pra sua tela real.
///
/// Nota de implementação (preservada): uso `Container` no lugar do
/// `DrawerHeader` do Material — mesma aparência, mas evita o esquema
/// de const-propagation do DrawerHeader que às vezes conflita com
/// children não-const e deixa o analyzer reportar erros bizarros pelo
/// arquivo.
@Deprecated(
  'Menu lateral desligado: os itens dependem de conta de usuário, '
  'que está deprecated junto com o LoginScreen.',
)
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // Inset do topo da tela (status bar / notch)
    final topInset = MediaQuery.of(context).padding.top;

    return Drawer(
      // Column no lugar de ListView+SafeArea externo — assim o
      child: Column(
        children: [
          // Ocupa toda a largura e vai até o topo absoluto da tela.
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: topInset + 16,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFF02890A)),
            child: const Text(
              'Menu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // SafeArea(top: false) — o cabeçalho já cobriu o inset do
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
            // Respiro entre o cabeçalho e o primeiro item do menu.
            const SizedBox(height: 24),

            // Pra adicionar mais entradas (Configurações, Sobre, etc),
            // é só copiar o padrão do ListTile abaixo.
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Conta'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Meu Formulário'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.star),
              title: const Text('Locais Favoritados'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Histórico de acessos'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  ),
                );
              },
            ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox(height: 16);
                  final info = snapshot.data!;
                  return Text(
                    'Versão ${info.version} (build ${info.buildNumber})',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),

    );
  }
}
