import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Singleton `ChangeNotifier`. UI se registra via `addListener` e reage
/// a mudanças de conectividade.
class AppMode extends ChangeNotifier {

  static final AppMode _instance = AppMode._();
  factory AppMode() => _instance;
  AppMode._();


  /// Cliente do plugin. Uma instância pra o app inteiro.
  final Connectivity _connectivity = Connectivity();

  /// Assinatura do Stream de mudanças. Cancelada em `dispose`.
  /// (`?` porque só é criada quando `init()` roda.)
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Assume online até o SO dizer o contrário. Motivo: se der ruim no
  /// plugin (erro de inicialização, versão bugada), preferimos tentar
  /// rede e falhar naturalmente do que travar tudo em offline sem
  /// razão.
  bool _isOnline = true;


  bool get isOnline => _isOnline;

  /// Açúcar sintático. `isOffline` lê melhor em ifs.
  bool get isOffline => !_isOnline;

  /// Chame no `main.dart` ANTES de `runApp`. Faz a leitura inicial e
  /// assina o Stream.
  ///
  /// É essencial rodar antes do primeiro build — senão o app renderiza
  /// como "online" e alguns milissegundos depois pisca pra "offline",
  /// causando flicker no badge.
  Future<void> init() async {
    // 1) Leitura inicial
    try {
      final initial = await _connectivity.checkConnectivity();
      _apply(initial);
    } catch (e) {
      debugPrint('[app_mode] falha na leitura inicial: $e');
      // Já assumimos true no default; mantém.
    }

    // 2) Assinatura contínua
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen(_apply);
  }

  /// Força uma releitura manual. Útil se o app volta de background e
  /// você desconfia que o Stream perdeu evento.
  Future<void> forceCheck() async {
    final result = await _connectivity.checkConnectivity();
    _apply(result);
  }

  /// A regra de decisão: "somos online?"
  ///
  /// Recebe uma lista pq versões novas do plugin retornam múltiplos
  /// tipos simultâneos (ex: `[wifi, ethernet]` se o cabo E o Wi-Fi
  /// estão ligados).
  ///
  /// "Online" = qualquer tipo que NÃO seja `.none`. Se a lista está
  /// vazia OU só contém `.none`, é offline.
  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none) &&
        results.isNotEmpty;

    // Early return se não mudou — evita notificar listeners que não
    // precisam re-renderizar.
    if (online == _isOnline) return;

    _isOnline = online;
    debugPrint('[app_mode] → ${_isOnline ? "ONLINE" : "OFFLINE"} '
        '(sinais: $results)');
    notifyListeners();
  }

  /// Cancela a assinatura do Stream. Como somos singleton, na prática
  /// nunca é chamado (a instância vive o app todo). Mas o `super.dispose`
  /// dá warning se não a gente não sobrescrever.
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
