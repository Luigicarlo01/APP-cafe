import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../controllers/analysis_controller.dart';
import 'cultivar_info_service.dart';

class PdfReportService {
  // ============================================================
  // CORES
  // ============================================================

  static const PdfColor verde =
      PdfColor(
    0.18,
    0.42,
    0.27,
  );

  static const PdfColor verdeClaro =
      PdfColor(
    0.93,
    0.97,
    0.94,
  );

  // ============================================================
  // GERAR RELATÓRIO
  // ============================================================

  static Future<Uint8List> generate({
    required String municipio,
    required double latitude,
    required double longitude,
    required String ciclo,
    required String filtroFerrugem,
    required String filtroNematoide,
    required List<RecommendedCultivar> cultivares,
    Uint8List? mapa,
  }) async {
    final pdf = pw.Document();

    // ==========================================================
    // CARREGAR LOGO DO TYPICA
    // ==========================================================

    String? logoSvg;

    try {
      logoSvg = await rootBundle.loadString(
        'assets/typica_logo_sem_borda.svg',
      );
    } catch (e) {
      logoSvg = null;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,

        margin: const pw.EdgeInsets.fromLTRB(
          30,
          24,
          30,
          30,
        ),

        // ======================================================
        // CABEÇALHO
        // ======================================================

        header: (
          context,
        ) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(
              bottom: 14,
            ),

            padding: const pw.EdgeInsets.only(
              bottom: 9,
            ),

            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: verde,
                  width: 0.8,
                ),
              ),
            ),

            child: pw.Row(
              crossAxisAlignment:
                  pw.CrossAxisAlignment.center,

              children: [
                // =================================================
                // LOGO
                // =================================================

                if (logoSvg != null)
                  pw.SizedBox(
                    width: 62,
                    height: 42,

                    child: pw.SvgImage(
                      svg: logoSvg,
                      fit: pw.BoxFit.contain,
                    ),
                  ),

                if (logoSvg != null)
                  pw.SizedBox(
                    width: 12,
                  ),

                // =================================================
                // NOME DO RELATÓRIO
                // =================================================

                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,

                    mainAxisSize:
                        pw.MainAxisSize.min,

                    children: [
                      pw.Text(
                        'Relatório de recomendação',

                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight:
                              pw.FontWeight.bold,
                          color: verde,
                        ),
                      ),

                      pw.SizedBox(
                        height: 2,
                      ),

                      pw.Text(
                        'Cultivares de café',

                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),

                // =================================================
                // DATA NO CABEÇALHO
                // =================================================

                pw.Text(
                  _dataAtual(),

                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },

        // ======================================================
        // RODAPÉ
        // ======================================================

        footer: (
          context,
        ) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(
              top: 10,
            ),

            child: pw.Row(
              mainAxisAlignment:
                  pw.MainAxisAlignment.spaceBetween,

              children: [
                pw.Text(
                  'Typica',

                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),

                pw.Text(
                  'Página ${context.pageNumber} de '
                  '${context.pagesCount}',

                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },

        build: (
          context,
        ) {
          return [
            // =================================================
            // TÍTULO PRINCIPAL
            // =================================================

            pw.Text(
              'Relatório de Recomendação de Cultivares',

              style: pw.TextStyle(
                fontSize: 21,
                fontWeight: pw.FontWeight.bold,
                color: verde,
              ),
            ),

            pw.SizedBox(
              height: 4,
            ),

            pw.Text(
              'Coffea arabica',

              style: const pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey700,
              ),
            ),

            pw.SizedBox(
              height: 18,
            ),

            // =================================================
            // LOCAL
            // =================================================

            _tituloSecao(
              'Local da análise',
            ),

            pw.Container(
              width: double.infinity,

              padding: const pw.EdgeInsets.all(
                10,
              ),

              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,

                borderRadius:
                    pw.BorderRadius.circular(
                  5,
                ),
              ),

              child: pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.start,

                children: [
                  pw.Text(
                    municipio,

                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight:
                          pw.FontWeight.bold,
                    ),
                  ),

                  pw.SizedBox(
                    height: 4,
                  ),

                  pw.Text(
                    'Latitude: '
                    '${latitude.toStringAsFixed(5)}',

                    style: const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),

                  pw.Text(
                    'Longitude: '
                    '${longitude.toStringAsFixed(5)}',

                    style: const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),

                  pw.SizedBox(
                    height: 4,
                  ),

                  pw.Text(
                    'Data: ${_dataAtual()}',

                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(
              height: 18,
            ),

            // =================================================
            // FILTROS
            // =================================================

            _tituloSecao(
              'Filtros utilizados',
            ),

            pw.Wrap(
              spacing: 6,
              runSpacing: 6,

              children: [
                _filtro(
                  'Ciclo',
                  ciclo,
                ),

                _filtro(
                  'Ferrugem',
                  filtroFerrugem,
                ),

                _filtro(
                  'Nematóide',
                  filtroNematoide,
                ),
              ],
            ),

            // =================================================
            // MAPA
            // =================================================

            if (mapa != null) ...[
              pw.SizedBox(
                height: 18,
              ),

              _tituloSecao(
                'Mapa da área analisada',
              ),

              // =================================================
              // CAIXA EXTERNA
              // =================================================

              pw.Container(
                width: double.infinity,
                height: 210,

                alignment:
                    pw.Alignment.center,

                padding: const pw.EdgeInsets.all(
                  5,
                ),

                decoration: pw.BoxDecoration(
                  color: PdfColors.white,

                  border: pw.Border.all(
                    color: PdfColors.grey400,
                    width: 0.5,
                  ),

                  borderRadius:
                      pw.BorderRadius.circular(
                    4,
                  ),
                ),

                // ===============================================
                // MAPA CENTRALIZADO
                // ===============================================

                child: pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(
                      mapa,
                    ),

                    height: 198,

                    fit: pw.BoxFit.contain,

                    alignment:
                        pw.Alignment.center,
                  ),
                ),
              ),
            ],

            pw.SizedBox(
              height: 20,
            ),

            // =================================================
            // CULTIVARES
            // =================================================

            _tituloSecao(
              'Cultivares recomendadas',
            ),

            pw.Text(
              'Cultivares que atendem aos filtros selecionados, '
              'na ordem do ranking da célula selecionada.',

              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),

            pw.SizedBox(
              height: 8,
            ),

            // =================================================
            // TABELA
            // =================================================

            _tabelaCultivares(
              cultivares,
            ),

            pw.SizedBox(
              height: 12,
            ),

            pw.Text(
              'A produtividade apresentada abaixo do nome da cultivar '
              'é uma referência municipal ou estadual. A ordem segue '
              'a recomendação do ponto selecionado.',

              style: pw.TextStyle(
                fontSize: 8,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey600,
              ),
            ),

            pw.SizedBox(
              height: 3,
            ),

            pw.Text(
              'Quando o nível tecnológico não estiver disponível '
              'na base de dados, será apresentado como '
              '"Não informado".',

              style: pw.TextStyle(
                fontSize: 8,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey600,
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // ============================================================
  // TABELA DAS CULTIVARES
  // ============================================================

  static pw.Widget _tabelaCultivares(
    List<RecommendedCultivar> cultivares,
  ) {
    final service =
        CultivarInfoService();

    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey400,
        width: 0.5,
      ),

      columnWidths: const {
        // CULTIVAR + PRODUTIVIDADE
        0: pw.FlexColumnWidth(
          2.2,
        ),

        // NÍVEL TECNOLÓGICO
        1: pw.FlexColumnWidth(
          1.4,
        ),

        // FERRUGEM
        2: pw.FlexColumnWidth(
          1.4,
        ),

        // NEMATÓIDE
        3: pw.FlexColumnWidth(
          1.4,
        ),
      },

      children: [
        // ======================================================
        // CABEÇALHO
        // ======================================================

        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: verde,
          ),

          children: [
            _cabecalho(
              'Cultivar',
            ),

            _cabecalho(
              'Nível tecnológico',
            ),

            _cabecalho(
              'Ferrugem',
            ),

            _cabecalho(
              'Nematóide',
            ),
          ],
        ),

        // ======================================================
        // CULTIVARES
        // ======================================================

        for (final cultivar
            in cultivares)
          _linhaCultivar(
            cultivar,
            service,
          ),
      ],
    );
  }

  // ============================================================
  // LINHA DA CULTIVAR
  // ============================================================

  static pw.TableRow _linhaCultivar(
    RecommendedCultivar cultivar,
    CultivarInfoService service,
  ) {
    final info =
        service.infoFor(
      cultivar.nome,
    );

    final produtividade =
        cultivar.produtividade;

    final produtividadeTexto =
        produtividade == null
            ? 'Produtividade não informada'
            : '${produtividade.mediaFormatada} sc/ha';

    return pw.TableRow(
      children: [
        // ======================================================
        // CULTIVAR + PRODUTIVIDADE
        // ======================================================

        pw.Padding(
          padding: const pw.EdgeInsets.all(
            7,
          ),

          child: pw.Column(
            crossAxisAlignment:
                pw.CrossAxisAlignment.start,

            children: [
              pw.Text(
                cultivar.nome,

                style: pw.TextStyle(
                  fontSize: 9,

                  fontWeight:
                      pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(
                height: 3,
              ),

              pw.Text(
                produtividadeTexto,

                style: const pw.TextStyle(
                  fontSize: 8,
                  color: verde,
                ),
              ),
            ],
          ),
        ),

        // ======================================================
        // NÍVEL TECNOLÓGICO
        // ======================================================

        _celula(
          _valor(
            info?.nivelTecnologico,
          ),
        ),

        // ======================================================
        // FERRUGEM
        // ======================================================

        _celula(
          _valor(
            info?.ferrugem,
          ),
        ),

        // ======================================================
        // NEMATÓIDE
        // ======================================================

        _celula(
          _valor(
            info?.nematoide,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TÍTULO DA SEÇÃO
  // ============================================================

  static pw.Widget _tituloSecao(
    String titulo,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        bottom: 7,
      ),

      child: pw.Text(
        titulo,

        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: verde,
        ),
      ),
    );
  }

  // ============================================================
  // FILTRO
  // ============================================================

  static pw.Widget _filtro(
    String label,
    String valor,
  ) {
    return pw.Container(
      padding:
          const pw.EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),

      decoration: pw.BoxDecoration(
        color: verdeClaro,

        borderRadius:
            pw.BorderRadius.circular(
          4,
        ),
      ),

      child: pw.Text(
        '$label: $valor',

        style: const pw.TextStyle(
          fontSize: 9,
        ),
      ),
    );
  }

  // ============================================================
  // CABEÇALHO DA TABELA
  // ============================================================

  static pw.Widget _cabecalho(
    String texto,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(
        7,
      ),

      child: pw.Text(
        texto,

        textAlign:
            pw.TextAlign.center,

        style: pw.TextStyle(
          fontSize: 8,

          fontWeight:
              pw.FontWeight.bold,

          color:
              PdfColors.white,
        ),
      ),
    );
  }

  // ============================================================
  // CÉLULA
  // ============================================================

  static pw.Widget _celula(
    String texto,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(
        7,
      ),

      child: pw.Text(
        texto,

        textAlign:
            pw.TextAlign.center,

        style: const pw.TextStyle(
          fontSize: 8,
        ),
      ),
    );
  }

  // ============================================================
  // VALOR VAZIO
  // ============================================================

  static String _valor(
    String? value,
  ) {
    if (value == null ||
        value.trim().isEmpty) {
      return 'Não informado';
    }

    return value.trim();
  }

  // ============================================================
  // DATA
  // ============================================================

  static String _dataAtual() {
    final data =
        DateTime.now();

    final dia =
        data.day
            .toString()
            .padLeft(
              2,
              '0',
            );

    final mes =
        data.month
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$dia/$mes/${data.year}';
  }
}
