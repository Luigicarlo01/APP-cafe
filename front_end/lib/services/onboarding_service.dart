import 'package:flutter/foundation.dart';

import 'cache/cache_paths.dart';

/// Tutoriais existentes.
///
/// O `id` vira sufixo do arquivo em disco (`.onboarding_done`,
/// `.onboarding_analysis`). **Não renomeie ids já publicados**: mudar o
/// id equivale a apagar a sentinela e o tutorial reaparece inteiro pra
/// quem já tinha visto.
///
/// `map` mantém o id histórico `done` — era o nome do arquivo quando só
/// existia um tutorial.
///
///
/// O tutorial não é só "primeira abertura do app": ele também precisa
/// apresentar **recurso novo pra usuário antigo**. Quem instalou o app
/// em janeiro e já viu o tutorial não deve ficar sem saber que existe
/// um botão novo em março.
///
/// Como funciona: a sentinela guarda a versão vista. Se a `version` do
/// fluxo for maior, o tutorial roda de novo — mostrando **só os passos
/// introduzidos depois** (ver `OnboardingStep.introducedIn`). Usuário
/// novo (versão vista = 0) recebe o roteiro inteiro.
///
/// **Ao adicionar uma feature numa tela**: crie o `OnboardingStep` com
/// `introducedIn: <nova versão>` e incremente a `version` do fluxo aqui.
/// São as duas linhas que fazem o recurso se anunciar sozinho.
enum OnboardingFlow {
  map('done', 1),
  analysis('analysis', 1);

  const OnboardingFlow(this.id, this.version);

  final String id;

  /// Versão atual do roteiro. Incrementar = reapresentar as novidades.
  final int version;
}

class OnboardingService {
  static final OnboardingService _instance = OnboardingService._();
  factory OnboardingService() => _instance;
  OnboardingService._();

  /// Cache em memória por fluxo. Ausente = ainda não consultamos o disco.
  final Map<OnboardingFlow, int> _seenVersion = {};

  /// Versão do roteiro que o usuário já viu (ou pulou).
  ///
  ///   - `0`  → nunca viu. Recebe o roteiro inteiro.
  ///   - `>0` → viu até aquela versão. Só passos mais novos aparecem.
  ///
  /// Sentinela vazia (formato antigo, de quando só existia "viu/não
  /// viu") conta como versão 1 — quem já tinha visto o tutorial não o
  /// recebe de novo por causa da migração.
  ///
  /// Falha de I/O devolve a versão ATUAL do fluxo, ou seja "já viu
  /// tudo": em caso de dúvida, não incomodar. Um veterano tomando
  /// tutorial na cara por erro de disco é pior que um novato sem
  /// tutorial.
  Future<int> seenVersion(OnboardingFlow flow) async {
    final cached = _seenVersion[flow];
    if (cached != null) return cached;

    int value;
    try {
      final file = await CachePaths.onboardingFlagFile(flow.id);
      if (!await file.exists()) {
        value = 0;
      } else {
        final raw = (await file.readAsString()).trim();
        value = int.tryParse(raw) ?? 1;
      }
    } catch (e) {
      debugPrint('Onboarding: falha ao ler sentinela ($e) — assumindo visto.');
      value = flow.version;
    }

    debugPrint(
      'Onboarding[${flow.id}]: versão vista=$value, atual=${flow.version} '
      '→ ${value >= flow.version ? "não mostra" : "mostra"}',
    );

    _seenVersion[flow] = value;
    return value;
  }

  /// Marca o roteiro como visto até a versão atual. Chamado tanto ao
  /// concluir quanto ao pular — pular é decisão do usuário e deve ser
  /// respeitada nas próximas aberturas.
  ///
  /// Atualiza o cache em memória ANTES do await: mesmo que a gravação
  /// falhe, o tutorial não reaparece no meio da sessão.
  Future<void> markSeen(OnboardingFlow flow) async {
    _seenVersion[flow] = flow.version;
    try {
      final file = await CachePaths.onboardingFlagFile(flow.id);
      await file.writeAsString('${flow.version}', flush: true);
    } catch (e) {
      debugPrint('Onboarding: falha ao gravar sentinela ($e).');
    }
  }

  /// Apaga a sentinela — o tutorial volta inteiro na próxima abertura
  /// da tela. Útil em testes e durante o desenvolvimento.
  Future<void> reset(OnboardingFlow flow) async {
    _seenVersion[flow] = 0;
    try {
      final file = await CachePaths.onboardingFlagFile(flow.id);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Onboarding: falha ao apagar sentinela ($e).');
    }
  }

  /// Reseta todos os fluxos de uma vez.
  Future<void> resetAll() async {
    for (final flow in OnboardingFlow.values) {
      await reset(flow);
    }
  }
}
