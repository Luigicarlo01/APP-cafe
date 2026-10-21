import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:front_end/screens/analysis_screen.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_mode.dart';
import '../services/cache/region_database.dart';
import '../utils/app_colors.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final AppMode _mode = AppMode();
  late final VoidCallback _modeListener;

  /// O `Future` é criado UMA vez e guardado. Se ficasse inline no
  /// `FutureBuilder`, cada rebuild (ex: mudança de conectividade)
  /// dispararia uma query nova e a lista piscaria.
  late Future<List<CachedRegionRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHistory();
    _modeListener = () => setState(() {});
    _mode.addListener(_modeListener);
  }

  @override
  void dispose() {
    _mode.removeListener(_modeListener);
    super.dispose();
  }

  Future<List<CachedRegionRow>> _loadHistory() {
    final db = RegionDatabase.instance;
    return (db.select(db.cachedRegions)
          ..orderBy([
            (r) => OrderingTerm(
                  expression: r.lastAccessAt,
                  mode: OrderingMode.desc,
                )
          ])
          ..limit(50))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Histórico de acessos'),
      ),
      body: FutureBuilder<List<CachedRegionRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.error_outline,
              title: 'Não foi possível ler o histórico',
              message:
                  'O banco local do aparelho não respondeu. Feche e abra '
                  'o app; se continuar, o cache pode ter sido corrompido.',
            );
          }

          final rows = snapshot.data ?? const <CachedRegionRow>[];

          if (rows.isEmpty) {
            return const _MessageState(
              icon: Icons.travel_explore_outlined,
              title: 'Nenhuma região por aqui ainda',
              message:
                  'Toda vez que você confirma uma localização no mapa, a '
                  'região fica salva no aparelho e aparece nesta lista — '
                  'pronta para ser aberta de novo, mesmo sem internet.',
            );
          }

          return Column(
            children: [
              _Header(count: rows.length, isOffline: _mode.isOffline),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) => _RegionTile(
                    row: rows[i],
                    isOffline: _mode.isOffline,
                    onTap: () => _openRegion(rows[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Abre a análise no CENTRO do bbox salvo.
  ///
  /// O centro é uma aproximação: o usuário pode ter consultado a borda
  /// do município. Mas o bbox é tudo que o cache guarda — as células
  /// individuais moram no `.geojson`, e o ponto exato do acesso não é
  /// registrado. Se um dia isso incomodar, o caminho é gravar o
  /// lat/lng do acesso numa coluna nova (ou numa tabela `access_log`).
  void _openRegion(CachedRegionRow row) {
    final center = LatLng(
      (row.minLat + row.maxLat) / 2,
      (row.minLon + row.maxLon) / 2,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisScreen(
          selectedPoint: center,
          selectedCrop: 'Café',
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final bool isOffline;

  const _Header({required this.count, required this.isOffline});

  @override
  Widget build(BuildContext context) {
    final singular = count == 1;

    // Offline o texto responde à dúvida do momento ("consigo abrir
    // alguma coisa sem sinal?"); online ele explica o que é a lista.
    final texto = isOffline
        ? '$count ${singular ? 'região salva' : 'regiões salvas'} no aparelho. '
            'Todas abrem sem internet.'
        : '$count ${singular ? 'região consultada' : 'regiões consultadas'} '
            'recentemente. Toque para abrir a análise de novo.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      color: AppColors.green.withValues(alpha: 0.06),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.35,
          color: Colors.black.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _RegionTile extends StatelessWidget {
  final CachedRegionRow row;
  final bool isOffline;
  final VoidCallback onTap;

  const _RegionTile({
    required this.row,
    required this.isOffline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = _displayName(row) ?? _toTitleCase(row.municipio);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.location_on_outlined,
            color: AppColors.greenDark, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _subtitle(row),
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            // Selo só offline: online ele seria ruído (toda linha da
            // tabela está em cache, então o selo não distinguiria nada).
            if (isOffline) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.offline_pin_outlined,
                        size: 13, color: AppColors.greenDark),
                    SizedBox(width: 4),
                    Text(
                      'Disponível offline',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.greenDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.black38),
      onTap: onTap,
    );
  }

  /// "Há 2 dias · 5 consultas". A contagem só aparece quando é maior
  /// que 1 — "1 consulta" não informa nada que a data já não diga.
  String _subtitle(CachedRegionRow row) {
    final quando = _relativeDate(row.lastAccessAt);
    if (row.accessCount > 1) {
      return '$quando · ${row.accessCount} consultas';
    }
    return quando;
  }

  /// Data em linguagem natural, sem depender do pacote `intl`.
  ///
  /// Granularidade proposital: ninguém precisa saber que foi "há 3
  /// horas e 12 minutos" — a pergunta é "isto é recente ou velho?".
  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) return 'Agora mesmo';
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    if (diff.inHours < 24) {
      return 'Há ${diff.inHours} ${diff.inHours == 1 ? 'hora' : 'horas'}';
    }
    if (diff.inDays == 1) return 'Ontem';
    if (diff.inDays < 30) return 'Há ${diff.inDays} dias';

    final meses = diff.inDays ~/ 30;
    if (meses < 12) return 'Há $meses ${meses == 1 ? 'mês' : 'meses'}';

    final anos = meses ~/ 12;
    return 'Há $anos ${anos == 1 ? 'ano' : 'anos'}';
  }

  /// Nome IBGE com acentos, guardado no JSON de metadata. Null em
  /// linhas gravadas antes dessa feature — o chamador cai no
  /// `_toTitleCase`.
  String? _displayName(CachedRegionRow row) {
    final raw = row.metadata;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded['display_name'] as String?;
    } catch (_) {
      return null; // JSON corrompido — fallback.
    }
  }

  /// "VICOSA_2026" → "Vicosa". Fallback pro nome sem acento.
  String _toTitleCase(String text) {
    final semAno = text.replaceAll(RegExp(r'_\d{4}$'), '');
    return semAno
        .split('_')
        .map((w) =>
            w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.black.withValues(alpha: 0.25)),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
