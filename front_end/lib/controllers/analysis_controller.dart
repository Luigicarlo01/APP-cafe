import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/analysis_service.dart';
import '../services/crop_cycle_service.dart';
import '../services/cultivar_info_service.dart';

enum ResistanceFilter { todos, resistente, moderadamenteResistente, suscetivel }

extension ResistanceFilterLabel on ResistanceFilter {
  String get label {
    switch (this) {
      case ResistanceFilter.todos:
        return 'Todos';

      case ResistanceFilter.resistente:
        return 'Resistente';

      case ResistanceFilter.moderadamenteResistente:
        return 'Moderadamente resistente';

      case ResistanceFilter.suscetivel:
        return 'Suscetível';
    }
  }
}

class RecommendedCultivar {
  final String nome;
  final ProdutividadeInfo? produtividade;
  final String? maturacao;
  final int ordemOriginal;

  const RecommendedCultivar({
    required this.nome,
    required this.produtividade,
    required this.maturacao,
    required this.ordemOriginal,
  });
}

class AnalysisController extends ChangeNotifier {
  String? selectedGenotype;
  String? errorMessage;

  GridCell? _selectedCell;

  bool isLoading = false;

  final CropCycleService _cycleService = CropCycleService();
  final AnalysisService _analysisService;

  ResistanceFilter _ferrugemFilter = ResistanceFilter.todos;

  ResistanceFilter _nematoideFilter = ResistanceFilter.todos;

  AnalysisController({AnalysisService? analysisService})
    : _analysisService = analysisService ?? AnalysisService() {
    _cycleService.addListener(_onCycleChanged);
  }

  ResistanceFilter get ferrugemFilter => _ferrugemFilter;

  ResistanceFilter get nematoideFilter => _nematoideFilter;

  CropCycle get selectedCycle => _cycleService.cycle;

  List<String> get winners => _analysisService.winners;

  // ============================================================
  // CARREGAR ANÁLISE
  // ============================================================

  Future<void> load({required LatLng position}) async {
    isLoading = true;
    errorMessage = null;
    selectedGenotype = null;

    notifyListeners();

    try {
      await _analysisService.load(
        lat: position.latitude,
        lng: position.longitude,
      );
    } on NoDataException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = 'Erro ao carregar dados. Verifique sua conexão.';

      debugPrint('Erro ao carregar análise: $e');
    }

    isLoading = false;

    _selectInitialCell(position);

    notifyListeners();
  }

  // ============================================================
  // CÉLULA INICIAL
  // ============================================================

  void _selectInitialCell(LatLng position) {
    final point = Offset(position.longitude, position.latitude);

    final cell = _analysisService.resolveCell(point);

    if (cell == null) {
      _selectedCell = null;
      selectedGenotype = null;
      return;
    }

    _selectedCell = cell;

    // A ficha começa sempre fechada.
    selectedGenotype = null;
  }

  // ============================================================
  // ABRIR / FECHAR CULTIVAR
  // ============================================================

  void selectGenotype(String genotype) {
    // Clicou novamente na cultivar aberta:
    // fecha a ficha.
    if (selectedGenotype == genotype) {
      selectedGenotype = null;
    } else {
      // Clicou em outra:
      // troca diretamente para ela.
      selectedGenotype = genotype;
    }

    notifyListeners();
  }

  // ============================================================
  // ALTERAÇÃO DA CÉLULA NO MAPA
  // ============================================================

  void updateSelectedGenotypeFromPosition(Offset geoPoint) {
    final cell = _analysisService.resolveCell(geoPoint);

    if (cell == null) {
      return;
    }

    _selectedCell = cell;

    // Fecha ficha antiga ao trocar de célula.
    selectedGenotype = null;

    notifyListeners();
  }

  // ============================================================
  // FILTRO DE FERRUGEM
  // ============================================================

  void setFerrugemFilter(ResistanceFilter value) {
    if (_ferrugemFilter == value) {
      return;
    }

    _ferrugemFilter = value;

    selectedGenotype = null;

    notifyListeners();
  }

  // ============================================================
  // FILTRO DE NEMATÓIDE
  // ============================================================

  void setNematoideFilter(ResistanceFilter value) {
    if (_nematoideFilter == value) {
      return;
    }

    _nematoideFilter = value;

    selectedGenotype = null;

    notifyListeners();
  }

  // ============================================================
  // ALTERAÇÃO DO CICLO
  // ============================================================

  void _onCycleChanged() {
    selectedGenotype = null;

    notifyListeners();
  }

  // ============================================================
  // CULTIVARES DA CÉLULA
  // ============================================================

  List<String> get _rawRanking {
    final cell = _selectedCell;

    if (cell == null) {
      return [];
    }

    final nomes = <String>{};

    if (cell.winner != null && cell.winner!.trim().isNotEmpty) {
      nomes.add(cell.winner!);
    }

    for (final alternative in cell.alternatives) {
      final nome = alternative.trim();

      if (nome.isNotEmpty) {
        nomes.add(nome);
      }
    }

    return nomes.toList();
  }

  // ============================================================
  // MUNICÍPIO
  // ============================================================

  String? get _municipioKey {
    final municipio = _analysisService.municipio;

    if (municipio == null || municipio.isEmpty) {
      return null;
    }

    return CultivarInfoService.chaveMunicipio(municipio);
  }

  // ============================================================
  // CICLO
  // ============================================================

  bool _matchesSelectedCycle(CultivarInfo? info) {
    if (info == null || info.maturacao == null) {
      return false;
    }

    final maturacao = _normalizeText(info.maturacao!);

    switch (_cycleService.cycle) {
      case CropCycle.curto:
        return maturacao == 'precoce';

      case CropCycle.medio:
        return maturacao == 'intermediario';

      case CropCycle.longo:
        return maturacao == 'tardio';
    }
  }

  // ============================================================
  // FERRUGEM
  // ============================================================

  bool _matchesFerrugem(CultivarInfo? info) {
    return _matchesResistance(info?.ferrugem, _ferrugemFilter);
  }

  // ============================================================
  // NEMATÓIDE
  // ============================================================

  bool _matchesNematoide(CultivarInfo? info) {
    return _matchesResistance(info?.nematoide, _nematoideFilter);
  }

  // ============================================================
  // RESISTÊNCIA
  // ============================================================

  bool _matchesResistance(String? value, ResistanceFilter filter) {
    if (filter == ResistanceFilter.todos) {
      return true;
    }

    if (value == null || value.trim().isEmpty) {
      return false;
    }

    final normalized = _normalizeText(value);

    switch (filter) {
      case ResistanceFilter.todos:
        return true;

      case ResistanceFilter.resistente:
        return normalized == 'resistente';

      case ResistanceFilter.moderadamenteResistente:
        return normalized == 'moderadamente resistente';

      case ResistanceFilter.suscetivel:
        return normalized == 'suscetivel';
    }
  }

  // ============================================================
  // NORMALIZAR TEXTO
  // ============================================================

  String _normalizeText(String text) {
    var value = text.trim().toLowerCase();

    const replacements = <String, String>{
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
    };

    replacements.forEach((from, to) {
      value = value.replaceAll(from, to);
    });

    return value.replaceAll(RegExp(r'\s+'), ' ');
  }

  // ============================================================
  // RANKING FINAL
  // ============================================================

  List<RecommendedCultivar> get selectedRanking {
    final nomes = _rawRanking;

    if (nomes.isEmpty) {
      return [];
    }

    final infoService = CultivarInfoService();

    final municipio = _municipioKey;

    final resultado = <RecommendedCultivar>[];

    for (int i = 0; i < nomes.length; i++) {
      final nome = nomes[i];

      final info = infoService.infoFor(nome);

      // Ciclo.
      if (!_matchesSelectedCycle(info)) {
        continue;
      }

      // Ferrugem.
      if (!_matchesFerrugem(info)) {
        continue;
      }

      // Nematóide.
      if (!_matchesNematoide(info)) {
        continue;
      }

      final produtividade = info?.produtividade(municipio: municipio);

      resultado.add(
        RecommendedCultivar(
          nome: nome,

          produtividade: produtividade,

          maturacao: info?.maturacao,

          ordemOriginal: i,
        ),
      );
    }

    // O GeoJSON já traz o ranking da célula: winner seguido de alternatives.
    // Os filtros preservam essa ordem; produtividade é apenas informativa.
    // Mostra até cinco cultivares que atendem aos filtros selecionados.
    return resultado.take(5).toList();
  }

  @override
  void dispose() {
    _cycleService.removeListener(_onCycleChanged);

    super.dispose();
  }
}
