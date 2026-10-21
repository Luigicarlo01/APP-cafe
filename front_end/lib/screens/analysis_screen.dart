import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart';
import 'package:printing/printing.dart';

import '../controllers/analysis_controller.dart';

import '../services/analysis_service.dart';
import '../services/crop_cycle_service.dart';
import '../services/onboarding_service.dart';
import '../services/pdf_report_service.dart';

import '../widgets/cycle_selection_picker.dart';
import '../widgets/genotype_plot.dart';
import '../widgets/genotypes_list.dart';
import '../widgets/onboarding_overlay.dart';
import '../widgets/opacity_slider.dart';
import '../widgets/resistance_filter_picker.dart';

class AnalysisScreen extends StatefulWidget {
  final LatLng selectedPoint;

  final String selectedCrop;

  const AnalysisScreen({
    super.key,
    required this.selectedPoint,
    required this.selectedCrop,
  });

  @override
  State<AnalysisScreen> createState() =>
      _AnalysisScreenState();
}

class _AnalysisScreenState
    extends State<AnalysisScreen> {
  final AnalysisController _controller =
      AnalysisController();

  // ============================================================
  // MAPA
  // ============================================================

  double _opacity = 0.7;

  /// O mapa começa oculto.
  bool _showMap = false;

  bool _isMapFullscreen = false;

  // ============================================================
  // COMPARTILHAMENTO
  // ============================================================

  bool _generatingPdf = false;

  /// Utilizada para capturar apenas o mapa
  /// que será inserido no relatório.
  final GlobalKey _mapCaptureKey =
      GlobalKey();

  // ============================================================
  // KEYS
  // ============================================================

  final GlobalKey _mapToggleKey =
      GlobalKey();

  final GlobalKey _mapKey =
      GlobalKey();

  final GlobalKey _fullscreenKey =
      GlobalKey();

  final GlobalKey _sliderKey =
      GlobalKey();

  final GlobalKey _cycleKey =
      GlobalKey();

  final GlobalKey _resistanceKey =
      GlobalKey();

  final GlobalKey _cultivaresKey =
      GlobalKey();

  bool _onboardingChecked = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _controller.addListener(
      _onControllerChanged,
    );

    _controller.load(
      position: widget.selectedPoint,
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _controller.removeListener(
      _onControllerChanged,
    );

    _controller.dispose();

    super.dispose();
  }

  // ============================================================
  // CONTROLLER
  // ============================================================

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});

    if (_onboardingChecked) {
      return;
    }

    if (_controller.isLoading) {
      return;
    }

    if (_controller.errorMessage !=
        null) {
      return;
    }

    _onboardingChecked = true;

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) => _maybeShowOnboarding(),
    );
  }

  // ============================================================
  // MOSTRAR / OCULTAR MAPA
  // ============================================================

  void _toggleMap() {
    setState(() {
      _showMap = !_showMap;
    });
  }

  // ============================================================
  // COMPARTILHAR PDF
  // ============================================================

  Future<void> _sharePdf() async {
    if (_generatingPdf) {
      return;
    }

    final ranking =
        _controller.selectedRanking;

    // ==========================================================
    // SEM CULTIVARES
    // ==========================================================

    if (ranking.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Não existem cultivares para compartilhar.',
          ),
        ),
      );

      return;
    }

    // ==========================================================
    // CARREGAMENTO
    // ==========================================================

    setState(() {
      _generatingPdf = true;
    });

    try {
      // ========================================================
      // CAPTURAR MAPA
      // ========================================================

      final mapa =
          await _captureMap();

      // ========================================================
      // MUNICÍPIO
      // ========================================================

      final displayName =
          AnalysisService()
              .displayName;

      final municipioInterno =
          AnalysisService()
              .municipio;

      final municipio =
          displayName ??
              (
                municipioInterno != null
                    ? _toTitleCase(
                        municipioInterno,
                      )
                    : 'Local selecionado'
              );

      // ========================================================
      // GERAR PDF
      // ========================================================

      final bytes =
          await PdfReportService.generate(
        municipio: municipio,

        latitude:
            widget.selectedPoint.latitude,

        longitude:
            widget.selectedPoint.longitude,

        ciclo:
            CropCycleService()
                .cycle
                .label,

        filtroFerrugem:
            _controller
                .ferrugemFilter
                .label,

        filtroNematoide:
            _controller
                .nematoideFilter
                .label,

        cultivares:
            ranking,

        mapa:
            mapa,
      );

      // ========================================================
      // NOME DO ARQUIVO
      // ========================================================

      final nomeArquivo =
          'relatorio_${_normalizarArquivo(municipio)}.pdf';

      // ========================================================
      // COMPARTILHAR
      // ========================================================

      await Printing.sharePdf(
        bytes: bytes,
        filename: nomeArquivo,
      );
    } catch (e) {
      debugPrint(
        'Erro ao compartilhar relatório: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível compartilhar o relatório.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingPdf = false;
        });
      }
    }
  }

  // ============================================================
  // CAPTURAR MAPA
  // ============================================================

  Future<Uint8List?> _captureMap() async {
    final estavaAberto =
        _showMap;

    // ==========================================================
    // MAPA FECHADO
    // ==========================================================
    //
    // Abre temporariamente para ser renderizado.
    // ==========================================================

    if (!estavaAberto) {
      setState(() {
        _showMap = true;
      });

      await WidgetsBinding
          .instance
          .endOfFrame;

      // Aguarda os tiles.
      await Future<void>.delayed(
        const Duration(
          milliseconds: 1000,
        ),
      );

      await WidgetsBinding
          .instance
          .endOfFrame;
    }

    Uint8List? bytes;

    try {
      final captureContext =
          _mapCaptureKey
              .currentContext;

      if (captureContext == null) {
        return null;
      }

      final object =
          captureContext
              .findRenderObject();

      if (object
          is! RenderRepaintBoundary) {
        return null;
      }

      final image =
          await object.toImage(
        pixelRatio: 2.0,
      );

      final byteData =
          await image.toByteData(
        format:
            ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        bytes =
            byteData
                .buffer
                .asUint8List();
      }
    } catch (e) {
      debugPrint(
        'Erro ao capturar mapa: $e',
      );
    } finally {
      // ========================================================
      // RESTAURAR MAPA
      // ========================================================

      if (!estavaAberto &&
          mounted) {
        setState(() {
          _showMap = false;
        });
      }
    }

    return bytes;
  }

  // ============================================================
  // ONBOARDING
  // ============================================================

  Future<void>
      _maybeShowOnboarding() async {
    final visto =
        await OnboardingService()
            .seenVersion(
      OnboardingFlow.analysis,
    );

    if (visto >=
        OnboardingFlow
            .analysis.version) {
      return;
    }

    if (!mounted ||
        _isMapFullscreen) {
      return;
    }

    _startOnboarding(
      sinceVersion: visto,
    );
  }

  void _startOnboarding({
    int sinceVersion = 0,
  }) {
    showOnboarding(
      context,

      steps:
          _onboardingSteps(),

      sinceVersion:
          sinceVersion,

      onFinish: () =>
          OnboardingService()
              .markSeen(
        OnboardingFlow.analysis,
      ),
    );
  }

  List<OnboardingStep>
      _onboardingSteps() {
    return [
      const OnboardingStep(
        title:
            'Sua análise está pronta',

        description:
            'Aqui você encontra as cultivares recomendadas '
            'para a região escolhida.',
      ),

      OnboardingStep(
        targetKey:
            _mapToggleKey,

        padding: 6,

        title:
            'Mapa da análise',

        description:
            'O mapa começa oculto. Use este botão para '
            'visualizar o mapa e ajustar a opacidade.',
      ),

      OnboardingStep(
        targetKey:
            _cycleKey,

        padding: 6,

        title:
            'Ciclo de maturação',

        description:
            'Escolha o ciclo para filtrar as cultivares.',
      ),

      OnboardingStep(
        targetKey:
            _resistanceKey,

        padding: 6,

        title:
            'Filtros de resistência',

        description:
            'Filtre pela resistência à ferrugem e ao nematóide.',
      ),

      OnboardingStep(
        targetKey:
            _cultivaresKey,

        padding: 6,

        title:
            'Cultivares recomendadas',

        description:
            'Toque em uma cultivar para visualizar '
            'suas informações.',
      ),
    ];
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final municipio =
        AnalysisService()
            .municipio;

    final displayName =
        AnalysisService()
            .displayName;

    final titleText =
        displayName ??
            (
              municipio != null
                  ? _toTitleCase(
                      municipio,
                    )
                  : null
            );

    // ==========================================================
    // MAPA EM TELA CHEIA
    // ==========================================================

    if (_isMapFullscreen) {
      return PopScope(
        canPop: false,

        onPopInvokedWithResult: (
          didPop,
          _,
        ) {
          if (didPop) {
            return;
          }

          setState(() {
            _isMapFullscreen =
                false;
          });
        },

        child: Scaffold(
          body: Stack(
            children: [
              // ================================================
              // MAPA
              // ================================================

              Positioned.fill(
                child: GenotypePlot(
                  key: _mapKey,

                  isLoading:
                      _controller
                          .isLoading,

                  selectedPoint:
                      widget
                          .selectedPoint,

                  opacity:
                      _opacity,

                  onMarkerMoved: (
                    geoOffset,
                  ) {
                    _controller
                        .updateSelectedGenotypeFromPosition(
                      geoOffset,
                    );
                  },
                ),
              ),

              // ================================================
              // VOLTAR
              // ================================================

              Positioned(
                top: 0,
                left: 0,
                right: 0,

                child: SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      8,
                    ),

                    child: Align(
                      alignment:
                          Alignment.centerLeft,

                      child: Material(
                        color:
                            Colors.white
                                .withOpacity(
                                  0.88,
                                ),

                        shape:
                            const CircleBorder(),

                        child: IconButton(
                          tooltip:
                              'Voltar',

                          onPressed: () {
                            setState(() {
                              _isMapFullscreen =
                                  false;
                            });
                          },

                          icon:
                              const Icon(
                            Icons.arrow_back,

                            color:
                                Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ================================================
              // OPACIDADE
              // ================================================

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,

                child: SafeArea(
                  top: false,

                  child: OpacitySlider(
                    value:
                        _opacity,

                    showLabel:
                        false,

                    onChanged: (
                      value,
                    ) {
                      setState(() {
                        _opacity =
                            value;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ==========================================================
    // CULTIVARES FILTRADAS
    // ==========================================================

    final ranking =
        _controller
            .selectedRanking;

    // ==========================================================
    // TELA PRINCIPAL
    // ==========================================================

    return Scaffold(
      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        centerTitle: true,

        toolbarHeight: 70,

        titleSpacing: 0,

        title: titleText != null
            ? Column(
                mainAxisSize:
                    MainAxisSize.min,

                children: [
                  const Text(
                    'Análise de',

                    style:
                        TextStyle(
                      fontSize: 13,

                      fontWeight:
                          FontWeight.w400,

                      height: 1,
                    ),
                  ),

                  const SizedBox(
                    height: 3,
                  ),

                  Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 4,
                    ),

                    child: FittedBox(
                      fit:
                          BoxFit.scaleDown,

                      child: Text(
                        titleText,

                        maxLines: 1,

                        textAlign:
                            TextAlign.center,

                        style:
                            const TextStyle(
                          fontSize: 19,

                          fontWeight:
                              FontWeight.w600,

                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const SizedBox(
                width: 20,
                height: 20,

                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,

                  color:
                      Colors.white,
                ),
              ),

        actions: [
          IconButton(
            onPressed:
                _startOnboarding,

            tooltip:
                'Rever tutorial',

            icon:
                const Icon(
              Icons.help_outline,
            ),
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: SafeArea(
        top: false,

        child:
            SingleChildScrollView(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,

            children: [
              // =================================================
              // ERRO
              // =================================================

              if (_controller
                      .errorMessage !=
                  null)
                MaterialBanner(
                  content: Text(
                    _controller
                        .errorMessage!,
                  ),

                  backgroundColor:
                      Colors
                          .red
                          .shade100,

                  actions: [
                    TextButton(
                      onPressed: () {
                        _controller
                            .load(
                          position:
                              widget
                                  .selectedPoint,
                        );
                      },

                      child:
                          const Text(
                        'Tentar novamente',
                      ),
                    ),
                  ],
                ),

              // =================================================
              // BOTÃO DO MAPA
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  0,
                ),

                child:
                    OutlinedButton(
                  key:
                      _mapToggleKey,

                  onPressed:
                      _toggleMap,

                  style:
                      OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 14,

                      vertical: 11,
                    ),

                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                  ),

                  child: Row(
                    mainAxisSize:
                        MainAxisSize.min,

                    mainAxisAlignment:
                        MainAxisAlignment.center,

                    children: [
                      const Icon(
                        Icons.map_outlined,

                        size: 19,
                      ),

                      const SizedBox(
                        width: 7,
                      ),

                      Text(
                        _showMap
                            ? 'Ocultar mapa e opacidade'
                            : 'Mostrar mapa e opacidade',
                      ),

                      const SizedBox(
                        width: 5,
                      ),

                      Icon(
                        _showMap
                            ? Icons
                                .keyboard_arrow_up
                            : Icons
                                .keyboard_arrow_down,

                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // =================================================
              // MAPA
              // =================================================

              if (_showMap) ...[
                const SizedBox(
                  height: 12,
                ),

                SizedBox(
                  height: 300,

                  child: Stack(
                    children: [
                      // =========================================
                      // MAPA CAPTURADO NO PDF
                      // =========================================

                      Positioned.fill(
                        child:
                            RepaintBoundary(
                          key:
                              _mapCaptureKey,

                          child:
                              GenotypePlot(
                            key:
                                _mapKey,

                            isLoading:
                                _controller
                                    .isLoading,

                            selectedPoint:
                                widget
                                    .selectedPoint,

                            opacity:
                                _opacity,

                            onMarkerMoved:
                                (
                              geoOffset,
                            ) {
                              _controller
                                  .updateSelectedGenotypeFromPosition(
                                geoOffset,
                              );
                            },
                          ),
                        ),
                      ),

                      // =========================================
                      // TELA CHEIA
                      // =========================================

                      Align(
                        alignment:
                            Alignment
                                .bottomRight,

                        child:
                            Padding(
                          padding:
                              const EdgeInsets.all(
                            8,
                          ),

                          child:
                              Material(
                            color:
                                Colors.white
                                    .withOpacity(
                                      0.82,
                                    ),

                            shape:
                                const CircleBorder(),

                            child:
                                IconButton(
                              key:
                                  _fullscreenKey,

                              tooltip:
                                  'Tela cheia',

                              onPressed:
                                  () {
                                setState(() {
                                  _isMapFullscreen =
                                      true;
                                });
                              },

                              icon:
                                  const Icon(
                                Icons.zoom_out_map,

                                color:
                                    Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ===============================================
                // OPACIDADE
                // ===============================================

                OpacitySlider(
                  key:
                      _sliderKey,

                  value:
                      _opacity,

                  onChanged: (
                    value,
                  ) {
                    setState(() {
                      _opacity =
                          value;
                    });
                  },
                ),
              ],

              // =================================================
              // CICLO
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  0,
                ),

                child:
                    CycleSelectionPicker(
                  key:
                      _cycleKey,
                ),
              ),

              // =================================================
              // RESISTÊNCIA
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  0,
                ),

                child:
                    ResistanceFilterPicker(
                  key:
                      _resistanceKey,

                  ferrugem:
                      _controller
                          .ferrugemFilter,

                  nematoide:
                      _controller
                          .nematoideFilter,

                  onFerrugemChanged:
                      _controller
                          .setFerrugemFilter,

                  onNematoideChanged:
                      _controller
                          .setNematoideFilter,
                ),
              ),

              // =================================================
              // CULTIVARES + COMPARTILHAR
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  18,
                  8,
                  3,
                ),

                child: Row(
                  children: [
                    // ===========================================
                    // TÍTULO
                    // ===========================================

                    Expanded(
                      child: Text(
                        'Cultivares recomendadas',

                        style:
                            Theme.of(
                          context,
                        )
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                      ),
                    ),

                    // ===========================================
                    // COMPARTILHAR RELATÓRIO
                    // ===========================================

                    IconButton(
                      tooltip:
                          'Compartilhar relatório',

                      onPressed:
                          ranking.isEmpty ||
                                  _generatingPdf
                              ? null
                              : _sharePdf,

                      icon:
                          _generatingPdf
                              ? const SizedBox(
                                  width: 20,

                                  height: 20,

                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.share_outlined,

                                  size: 23,
                                ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // ESPAÇO ENTRE TÍTULO E LISTA
              // =================================================

              const SizedBox(
                height: 8,
              ),

              // =================================================
              // CULTIVARES
              // =================================================

              if (ranking.isNotEmpty)
                GenotypeList(
                  key:
                      _cultivaresKey,

                  cultivares:
                      ranking,

                  selectedGenotype:
                      _controller
                          .selectedGenotype,

                  municipio:
                      AnalysisService()
                          .municipio,

                  onSelect:
                      _controller
                          .selectGenotype,
                )

              // =================================================
              // SEM CULTIVARES
              // =================================================

              else
                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 24,

                    vertical: 24,
                  ),

                  child: Column(
                    children: [
                      Icon(
                        Icons
                            .filter_alt_off_outlined,

                        size: 32,

                        color:
                            Colors.black
                                .withOpacity(
                                  0.30,
                                ),
                      ),

                      const SizedBox(
                        height: 9,
                      ),

                      Text(
                        'Nenhuma cultivar atende aos filtros selecionados.',

                        textAlign:
                            TextAlign.center,

                        style:
                            TextStyle(
                          fontSize: 14,

                          fontWeight:
                              FontWeight.w500,

                          color:
                              Colors.black
                                  .withOpacity(
                                    0.60,
                                  ),
                        ),
                      ),

                      const SizedBox(
                        height: 4,
                      ),

                      Text(
                        'Tente alterar o ciclo, a ferrugem '
                        'ou o nematóide.',

                        textAlign:
                            TextAlign.center,

                        style:
                            TextStyle(
                          fontSize: 12.5,

                          color:
                              Colors.black
                                  .withOpacity(
                                    0.45,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(
                height: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FORMATAR MUNICÍPIO
  // ============================================================

  String _toTitleCase(
    String text,
  ) {
    final semAno =
        text.replaceAll(
      RegExp(
        r'_\d{4}$',
      ),
      '',
    );

    return semAno
        .split('_')
        .map(
          (
            word,
          ) =>
              word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}'
                      '${word.substring(1).toLowerCase()}',
        )
        .join(
          ' ',
        );
  }

  // ============================================================
  // NOME DO ARQUIVO PDF
  // ============================================================

  String _normalizarArquivo(
    String text,
  ) {
    var value =
        text
            .toLowerCase()
            .trim();

    const substituicoes =
        <String, String>{
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',

      'é': 'e',
      'ê': 'e',

      'í': 'i',

      'ó': 'o',
      'õ': 'o',
      'ô': 'o',

      'ú': 'u',

      'ç': 'c',
    };

    substituicoes.forEach(
      (
        de,
        para,
      ) {
        value =
            value.replaceAll(
          de,
          para,
        );
      },
    );

    value =
        value.replaceAll(
      RegExp(
        r'[^a-z0-9]+',
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
}