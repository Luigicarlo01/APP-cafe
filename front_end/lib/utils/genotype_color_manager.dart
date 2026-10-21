import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

/// Dicionário "genótipo → cor" lido de `assets/colors_2026.json`.
///
/// **Fora de uso**: o mapa da análise virou monocromático (todas as
/// células em `AppColors.green`) e a legenda por cor foi removida,
/// então ninguém consulta mais esta paleta. O `main.dart` deixou de
/// chamar `load()` no boot.
///
/// Preservado porque o JSON de cores continua sendo gerado pelo
/// backend e a coloração por genótipo pode voltar como camada opcional.
@Deprecated(
  'Mapa monocromático não usa cor por genótipo. '
  'Reative chamando load() no main.dart se a coloração voltar.',
)
class GenotypeColorManager {
  static final GenotypeColorManager _instance = GenotypeColorManager._internal();
  factory GenotypeColorManager() => _instance;
  GenotypeColorManager._internal();

  Map<String, Color> _colorMap = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final jsonStr = await rootBundle.loadString('assets/colors_2026.json');
    final Map<String, dynamic> raw = jsonDecode(jsonStr);
    _colorMap = raw.map((key, value) => MapEntry(key, _hexToColor(value)));
    _loaded = true;
  }

  Color getColor(String genotype) {
    return _colorMap[genotype] ?? Colors.grey.withOpacity(0.4);
  }

  Map<String, Color> colorsFor(List<String> genotypes) {
    return { for (final g in genotypes) g: getColor(g) };
  }

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
  // hex é RRGGBBAA
    final r = int.parse(h.substring(0, 2), radix: 16);
    final g = int.parse(h.substring(2, 4), radix: 16);
    final b = int.parse(h.substring(4, 6), radix: 16);
    final a = int.parse(h.substring(6, 8), radix: 16);
    return Color.fromARGB(a, r, g, b);}
}