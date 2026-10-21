import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Verde principal da marca. AppBar, botões preenchidos, seed do
  /// `ColorScheme`, botão de localização (FAB) — e as células
  /// selecionáveis do grid na tela de análise, que usam exatamente
  /// este tom pra o mapa falar a mesma língua dos controles.
  static const Color green = Color(0xFF02890A);

  /// Tom mais escuro da paleta. Contraste sobre o verde principal:
  /// ícone dentro do FAB, títulos, realces.
  static const Color greenDark = Color(0xFF013A03);

  /// Bege de fundo — empty state do mapa, superfícies neutras.
  static const Color bege = Color(0xFFF5F0E8);
}
