import 'package:flutter/material.dart';

class OnboardingStep {
  /// Chave pendurada no widget que será destacado. `null` = passo sem
  /// destaque (abertura/encerramento): o texto fica centralizado e o
  /// buraco tem tamanho zero no centro da tela.
  final GlobalKey? targetKey;

  final String title;
  final String description;

  /// Recorte circular em vez de retangular. Bom pra alvos redondos
  /// (o FAB do GPS) e pra alvos grandes onde um retângulo viraria a
  /// tela inteira (o mapa).
  final bool circular;

  /// Teto do tamanho do recorte, em pixels lógicos. Quando o alvo é
  /// maior que isso, o recorte encolhe pro centro do alvo.
  ///
  /// Existe por causa do mapa: destacar o `RenderBox` inteiro dele
  /// abriria um buraco do tamanho da tela e o "spotlight" não
  /// destacaria nada.
  final double? maxSize;

  /// Folga entre a borda do alvo e a borda do recorte. Alvos baixos e
  /// largos (a pílula do ciclo) pedem folga menor pra a sombra não
  /// sobrar em volta.
  final double padding;

  /// Em que versão do roteiro este passo entrou.
  ///
  /// É o que permite apresentar **recurso novo pra usuário antigo**:
  /// quando a `version` do `OnboardingFlow` sobe, o tutorial roda de
  /// novo mostrando só os passos com `introducedIn` maior que a versão
  /// que o usuário já viu. Quem nunca viu (versão 0) recebe tudo.
  ///
  /// Passo novo = `introducedIn: <nova versão do fluxo>`.
  final int introducedIn;

  const OnboardingStep({
    required this.title,
    required this.description,
    this.targetKey,
    this.circular = false,
    this.maxSize,
    this.padding = 8,
    this.introducedIn = 1,
  });
}

/// Abre o tutorial por cima da tela atual.
///
/// `onFinish` roda quando o usuário conclui OU pula — nos dois casos a
/// tela hospedeira deve marcar o tutorial como visto.
///
/// `sinceVersion` filtra o roteiro: só entram passos com
/// `introducedIn` MAIOR que ela. É o mecanismo de "recurso novo":
///
///   - `0` (default) → roteiro inteiro. Usuário novo, ou quem pediu
///     pra rever o tutorial pelo botão "?".
///   - `2` → só o que entrou da versão 3 em diante. Usuário antigo
///     recebendo a novidade, sem reassistir o que já sabe.
///
/// Se a filtragem não sobrar nenhum passo, a rota nem é empilhada e o
/// `onFinish` é chamado assim mesmo — a sentinela avança e o app não
/// tenta de novo no próximo boot.
Future<void> showOnboarding(
  BuildContext context, {
  required List<OnboardingStep> steps,
  required VoidCallback onFinish,
  int sinceVersion = 0,
}) {
  final novos =
      steps.where((s) => s.introducedIn > sinceVersion).toList();

  if (novos.isEmpty) {
    onFinish();
    return Future<void>.value();
  }

  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      // `opaque: false` mantém a tela de baixo montada e pintada — é
      // ela que aparece pelo buraco do spotlight.
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => _OnboardingOverlay(
        steps: novos,
        onFinish: onFinish,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _OnboardingOverlay extends StatefulWidget {
  final List<OnboardingStep> steps;
  final VoidCallback onFinish;

  const _OnboardingOverlay({
    required this.steps,
    required this.onFinish,
  });

  @override
  State<_OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<_OnboardingOverlay> {
  int _index = 0;

  /// Passos que sobraram depois de descartar os que não têm alvo na
  /// tela. Resolvido uma vez, no primeiro frame, pra que a navegação
  /// entre dicas não mude de tamanho no meio do caminho.
  late List<OnboardingStep> _steps = widget.steps;

  bool _ready = false;

  static const Duration _morph = Duration(milliseconds: 480);
  static const Curve _morphCurve = Curves.easeInOutCubic;

  static const Duration _textSwap = Duration(milliseconds: 700);

  /// Entrada só começa depois que o foco praticamente chegou.
  static const Curve _textInCurve =
      Interval(0.65, 1.0, curve: Curves.easeOut);

  /// Saída acontece logo no início — o texto antigo some antes do foco
  /// sair do lugar. (A curva do "out" é aplicada ao controller indo de
  /// 1 → 0; o intervalo alto significa "os primeiros instantes".)
  static const Curve _textOutCurve =
      Interval(0.7, 1.0, curve: Curves.easeIn);

  @override
  void initState() {
    super.initState();
    // `addPostFrameCallback` porque no initState a tela de baixo pode
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final visible = widget.steps
          .where((s) => s.targetKey == null || _rectFor(s) != null)
          .toList();

      if (visible.isNotEmpty) await _ensureVisible(visible.first);
      if (!mounted) return;

      setState(() {
        _steps = visible;
        _ready = true;
      });
    });
  }

  /// Rola a tela de baixo até o alvo, se ele estiver dentro de uma área
  /// rolável.
  ///
  /// Necessário na tela de análise: ela é um `SingleChildScrollView` e
  /// metade dos alvos (lista de cultivares, card de detalhes) começa
  /// fora da viewport. Sem isso, o spotlight abriria um buraco em
  /// coordenadas que o usuário não está vendo.
  ///
  /// A rolagem acontece ANTES de trocar o passo — se fosse depois, o
  /// buraco animaria até a posição antiga do alvo e só então corrigiria,
  /// dando um solavanco.
  ///
  /// `Scrollable.ensureVisible` é no-op quando não há `Scrollable`
  /// ancestral (caso da MapScreen), então não precisa de guarda.
  Future<void> _ensureVisible(OnboardingStep step) async {
    final ctx = step.targetKey?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      // 0.5 = centraliza o alvo na viewport. Deixa espaço dos dois
      // lados pro texto da dica se encaixar.
      alignment: 0.5,
    );
  }

  /// Geometria global do alvo, já com padding, teto de tamanho e
  /// clamp na tela. `null` quando o widget não está montado/medido.
  Rect? _rectFor(OnboardingStep step) {
    final ctx = step.targetKey?.currentContext;
    if (ctx == null) return null;

    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final origin = box.localToGlobal(Offset.zero);
    var rect = origin & box.size;

    // Teto de tamanho: encolhe pro centro mantendo proporção do alvo.
    final max = step.maxSize;
    if (max != null && (rect.width > max || rect.height > max)) {
      rect = Rect.fromCenter(
        center: rect.center,
        width: rect.width > max ? max : rect.width,
        height: rect.height > max ? max : rect.height,
      );
    }

    rect = rect.inflate(step.padding);

    // Alvos colados na borda (FAB, ícone da AppBar) gerariam recorte
    // saindo da tela; o clamp mantém o buraco visível por inteiro.
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    return rect.intersect(screen);
  }

  /// Recorte efetivo do passo: o retângulo do alvo ou, quando não há
  /// alvo, um ponto no centro da tela (buraco de tamanho zero).
  ///
  /// Nunca devolve `null` — é isso que mantém UM único
  /// `TweenAnimationBuilder` vivo do primeiro ao último passo e faz o
  /// foco abrir/fechar animado nas pontas.
  Rect _holeFor(OnboardingStep step) {
    return _rectFor(step) ??
        Rect.fromCenter(
          center: (Offset.zero & MediaQuery.sizeOf(context)).center,
          width: 0,
          height: 0,
        );
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      _close();
      return;
    }
    _goTo(_index + 1);
  }

  void _previous() {
    if (_index == 0) return;
    _goTo(_index - 1);
  }

  /// Troca de passo: rola até o alvo primeiro, depois muda o índice.
  /// A ordem importa — ver `_ensureVisible`.
  Future<void> _goTo(int index) async {
    await _ensureVisible(_steps[index]);
    if (!mounted) return;
    setState(() => _index = index);
  }

  /// Fecha o tutorial. Um caminho só pra sair (concluir, pular ou
  /// botão físico de voltar) — assim `onFinish` nunca deixa de rodar
  /// e o tutorial não reaparece na próxima abertura.
  void _close() {
    widget.onFinish();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();

    // Nenhum alvo disponível (tela ainda vazia, caso improvável):
    // encerra em silêncio em vez de mostrar overlay preto sem conteúdo.
    if (_steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return const SizedBox.shrink();
    }

    final step = _steps[_index];
    final hole = _holeFor(step);
    final screen = MediaQuery.sizeOf(context);

    // Raio: metade do maior lado satura o arredondamento e o RRect vira
    final radius = step.circular ? hole.longestSide / 2 : 18.0;

    return PopScope(
      // Botão físico de voltar sai do tutorial inteiro (não volta uma
      // dica) — é o gesto de "quero sair disso".
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Um único TweenAnimationBuilder pra TODOS os passos: o
            Positioned.fill(
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(begin: hole, end: hole),
                duration: _morph,
                curve: _morphCurve,
                builder: (_, animatedHole, _) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: radius, end: radius),
                    duration: _morph,
                    curve: _morphCurve,
                    builder: (_, animatedRadius, _) => CustomPaint(
                      painter: _SpotlightPainter(
                        hole: animatedHole ?? hole,
                        radius: animatedRadius,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Absorve toques na área escura pra que o usuário não
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
              ),
            ),

            _buildContent(context, hole, screen),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Rect hole, Size screen) {
    // Margem externa menor que o recuo interno do bloco (`_inset`): o
    // respiro do texto vem de dentro, não da borda da tela.
    const margin = 14.0;
    const gap = 26.0;

    // Altura típica do bloco (contador + título 2 linhas + texto 3
    const needed = 290.0;

    final insets = MediaQuery.paddingOf(context);

    // Troca escalonada do texto (ver a coreografia lá em cima): o antigo
    final content = AnimatedSwitcher(
      duration: _textSwap,
      switchInCurve: _textInCurve,
      switchOutCurve: _textOutCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _StepContent(
        key: ValueKey(_index),
        step: _steps[_index],
        index: _index,
        total: _steps.length,
        onPrevious: _index > 0 ? _previous : null,
        onNext: _next,
        onSkip: _close,
        isLast: _index == _steps.length - 1,
      ),
    );

    // Buraco de tamanho zero = passo sem alvo: centraliza.
    if (hole.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: margin),
          child: content,
        ),
      );
    }

    final spaceBelow = screen.height - insets.bottom - hole.bottom - gap;
    final spaceAbove = hole.top - insets.top - gap;

    if (spaceBelow >= needed) {
      return Positioned(
        left: margin,
        right: margin,
        top: hole.bottom + gap,
        child: content,
      );
    }

    if (spaceAbove >= needed) {
      return Positioned(
        left: margin,
        right: margin,
        bottom: screen.height - hole.top + gap,
        child: content,
      );
    }

    return Positioned(
      left: margin,
      right: margin,
      bottom: insets.bottom + margin,
      child: content,
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect hole;
  final double radius;

  const _SpotlightPainter({required this.hole, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final screenPath = Path()..addRect(Offset.zero & size);
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.78);

    // Buraco degenerado (passo sem alvo): sombra cheia, sem recorte.
    if (hole.isEmpty) {
      canvas.drawPath(screenPath, scrim);
      return;
    }

    final rrect = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    final holePath = Path()..addRRect(rrect);

    // `PathOperation.difference` = tela MENOS buraco. É recorte de
    // verdade: o que está embaixo aparece nítido, sem véu por cima.
    canvas.drawPath(
      Path.combine(PathOperation.difference, screenPath, holePath),
      scrim,
    );

    // Halo: um stroke largo e borrado logo fora do buraco
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(
      holePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..color = Colors.white.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Recorta o halo que invadiu o miolo do buraco: o elemento
    // destacado precisa aparecer limpo, sem véu esbranquiçado.
    canvas.drawPath(holePath, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Fio claro exatamente na borda — define o limite do foco quando o
    canvas.drawPath(
      holePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.radius != radius;
}

class _StepContent extends StatelessWidget {
  final OnboardingStep step;
  final int index;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  const _StepContent({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
  });

  /// Recuo interno do bloco. Vale pro texto E pros controles: os dois
  /// compartilham a mesma margem esquerda, senão o título "flutua" e a
  /// coluna fica desalinhada.
  static const double _inset = 18;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TextScrim(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contador discreto — dá noção de "quanto falta" sem
              Text(
                total == 1 ? 'NOVIDADE' : '${index + 1} de $total',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                step.description,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Escondido quando há um passo só: uma bolinha sozinha não
        // informa nada.
        if (total > 1)
        Padding(
          padding: const EdgeInsets.only(left: _inset),
          child: Row(
            children: [
              for (int i = 0; i < total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.only(right: 6),
                  width: i == index ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == index
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Mesmo recuo do texto pra a coluna ficar alinhada.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          child: Row(
            children: [
              // Voltar: círculo vazado
              if (total > 1) ...[
                _CircleAction(
                  icon: Icons.arrow_back,
                  onTap: onPrevious,
                  tooltip: 'Dica anterior',
                ),
                const SizedBox(width: 12),
              ],
              // Próximo: pílula branca sólida — o único elemento cheio
              // do conjunto, então é o alvo óbvio.
              Expanded(
                child: _PrimaryAction(
                  // Um passo só = aviso de novidade, não um percurso;
                  label: !isLast
                      ? 'Próximo'
                      : (total == 1 ? 'Entendi' : 'Começar a usar'),
                  icon: isLast ? Icons.check : Icons.arrow_forward,
                  onTap: onNext,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        if (total > 1)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.62),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text(
                'Não desejo fazer o tutorial',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// Degradê de reforço atrás do texto.
///
/// Substitui o antigo cartão branco: escurece um pouco mais a região do
/// texto (garantindo contraste se algo claro aparecer atrás) sem borda,
/// sem elevação e sem competir visualmente com o spotlight.
class _TextScrim extends StatelessWidget {
  final Widget child;

  const _TextScrim({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: RadialGradient(
          center: Alignment.centerLeft,
          radius: 1.6,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Botão redondo vazado (voltar). `onTap` nulo = estado apagado.
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  const _CircleAction({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: enabled ? 0.55 : 0.18),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 20,
              color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.25),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pílula branca sólida (próximo/concluir).
class _PrimaryAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: Colors.black87),
            ],
          ),
        ),
      ),
    );
  }
}
