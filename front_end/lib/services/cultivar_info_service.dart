import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ProdutividadeInfo {
  final int ano;
  final double media;
  final int registros;
  final bool doMunicipio;

  const ProdutividadeInfo({
    required this.ano,
    required this.media,
    required this.registros,
    required this.doMunicipio,
  });

  String get mediaFormatada =>
      media.toStringAsFixed(1).replaceAll('.', ',');
}

class CultivarInfo {
  final String nome;

  final String? maturacao;

  /// Nível tecnológico da cultivar.
  ///
  /// Se não estiver presente no JSON,
  /// aparecerá como "Não informado" no relatório.
  final String? nivelTecnologico;

  final String? ferrugem;

  final String? nematoide;

  final String? nematoideDetalhe;

  final Map<String, dynamic>? produtividadeEstado;

  final Map<String, dynamic> produtividadeMunicipios;

  const CultivarInfo({
    required this.nome,
    this.maturacao,
    this.nivelTecnologico,
    this.ferrugem,
    this.nematoide,
    this.nematoideDetalhe,
    this.produtividadeEstado,
    this.produtividadeMunicipios = const {},
  });

  // ============================================================
  // PRODUTIVIDADE
  // ============================================================

  ProdutividadeInfo? produtividade({
    String? municipio,
  }) {
    // Primeiro tenta utilizar a produtividade do município.
    if (municipio != null) {
      final local =
          produtividadeMunicipios[municipio];

      if (local is Map) {
        final mapa =
            Map<String, dynamic>.from(
          local,
        );

        return _produtividadeFromMap(
          mapa,
          doMunicipio: true,
        );
      }
    }

    // Caso contrário, utiliza a produtividade estadual.
    return produtividadeEstadual();
  }

  ProdutividadeInfo? produtividadeEstadual() {
    final estado =
        produtividadeEstado;

    if (estado == null) {
      return null;
    }

    return _produtividadeFromMap(
      estado,
      doMunicipio: false,
    );
  }

  ProdutividadeInfo? _produtividadeFromMap(
    Map<String, dynamic> dados, {
    required bool doMunicipio,
  }) {
    final media =
        _toDouble(
      dados['media'],
    );

    if (media == null) {
      return null;
    }

    final ano =
        _toInt(
          dados['ano'],
        ) ??
        0;

    final registros =
        _toInt(
          dados['registros'],
        ) ??
        0;

    return ProdutividadeInfo(
      ano: ano,
      media: media,
      registros: registros,
      doMunicipio: doMunicipio,
    );
  }

  static double? _toDouble(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value
          .toString()
          .replaceAll(',', '.'),
    );
  }

  static int? _toInt(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    );
  }
}

class CultivarInfoService {
  static final CultivarInfoService _instance =
      CultivarInfoService._internal();

  factory CultivarInfoService() {
    return _instance;
  }

  CultivarInfoService._internal();

  final Map<String, CultivarInfo> _cultivares = {};

  bool _loaded = false;

  // ============================================================
  // CARREGAR JSON
  // ============================================================

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    try {
      final texto =
          await rootBundle.loadString(
        'assets/cultivares.json',
      );

      final decoded =
          jsonDecode(
        texto,
      );

      _cultivares.clear();

      dynamic bruto =
          decoded;

      if (decoded is Map &&
          decoded.containsKey(
            'cultivares',
          )) {
        bruto =
            decoded['cultivares'];
      }

      if (bruto is Map) {
        bruto.forEach(
          (
            key,
            value,
          ) {
            if (value is! Map) {
              return;
            }

            final json =
                Map<String, dynamic>.from(
              value,
            );

            final nome =
                json['nome']?.toString() ??
                    key.toString();

            final produtividadeBruta =
                json['produtividade'];

            Map<String, dynamic>?
                produtividadeEstado;

            Map<String, dynamic>
                produtividadeMunicipios =
                {};

            if (produtividadeBruta is Map) {
              final prod =
                  Map<String, dynamic>.from(
                produtividadeBruta,
              );

              final estado =
                  prod['estado'];

              if (estado is Map) {
                produtividadeEstado =
                    Map<String, dynamic>.from(
                  estado,
                );
              }

              final municipios =
                  prod['municipios'];

              if (municipios is Map) {
                produtividadeMunicipios =
                    Map<String, dynamic>.from(
                  municipios,
                );
              }
            }

            final info =
                CultivarInfo(
              nome: nome,

              maturacao:
                  json['maturacao']
                      ?.toString(),

              nivelTecnologico:
                  (
                    json['nivelTecnologico'] ??
                    json['nivel_tecnologico']
                  )
                      ?.toString(),

              ferrugem:
                  json['ferrugem']
                      ?.toString(),

              nematoide:
                  json['nematoide']
                      ?.toString(),

              nematoideDetalhe:
                  (
                    json['nematoideDetalhe'] ??
                    json['nematoide_detalhe']
                  )
                      ?.toString(),

              produtividadeEstado:
                  produtividadeEstado,

              produtividadeMunicipios:
                  produtividadeMunicipios,
            );

            _cultivares[
              chaveCultivar(
                nome,
              )
            ] = info;
          },
        );
      }

      _loaded = true;
    } catch (e) {
      debugPrint(
        'Erro ao carregar cultivares.json: $e',
      );

      _loaded = true;
    }
  }

  // ============================================================
  // BUSCAR CULTIVAR
  // ============================================================

  CultivarInfo? infoFor(
    String nomeCultivar,
  ) {
    return _cultivares[
      chaveCultivar(
        nomeCultivar,
      )
    ];
  }

  // ============================================================
  // NORMALIZAR CULTIVAR
  // ============================================================

  static String chaveCultivar(
    String nome,
  ) {
    var value =
        _removeAccents(
          nome,
        ).toLowerCase();

    value =
        value.replaceAll(
      RegExp(
        r'[^a-z0-9]+',
      ),
      ' ',
    );

    return value.trim();
  }

  // ============================================================
  // NORMALIZAR MUNICÍPIO
  // ============================================================

  static String chaveMunicipio(
    String municipio,
  ) {
    var value =
        municipio.replaceAll(
      RegExp(
        r'_\d{4}$',
      ),
      '',
    );

    value =
        _removeAccents(
          value,
        ).toUpperCase();

    value =
        value.replaceAll(
      RegExp(
        r'[^A-Z0-9]+',
      ),
      '_',
    );

    return value.replaceAll(
      RegExp(
        r'^_+|_+$',
      ),
      '',
    );
  }

  // ============================================================
  // REMOVER ACENTOS
  // ============================================================

  static String _removeAccents(
    String text,
  ) {
    const replacements =
        <String, String>{
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',

      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',

      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',

      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',

      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',

      'ç': 'c',

      'Á': 'A',
      'À': 'A',
      'Ã': 'A',
      'Â': 'A',

      'É': 'E',
      'Ê': 'E',

      'Í': 'I',

      'Ó': 'O',
      'Õ': 'O',
      'Ô': 'O',

      'Ú': 'U',

      'Ç': 'C',
    };

    var result =
        text;

    replacements.forEach(
      (
        from,
        to,
      ) {
        result =
            result.replaceAll(
          from,
          to,
        );
      },
    );

    return result;
  }
}