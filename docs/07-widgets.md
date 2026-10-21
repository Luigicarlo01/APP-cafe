# 07 — Widgets

---

## `map_widget.dart` — 128 linhas

O mapa da tela inicial. `StatefulWidget`.

### Interface

```dart
final MapController mapController;   // vem do MapControllerLogic
final LatLng? selectedPoint;
final Function(LatLng) onTap;
final double? maxZoom;               // null = teto do flutter_map (~18)
final int? maxNativeZoom;            // null = 18
```

`maxZoom` limita a câmera; `maxNativeZoom` diz até onde existem tiles de
verdade. Acima do `maxNativeZoom`, o `flutter_map` **estica** o último
tile disponível em vez de pedir rede. Offline, a `MapScreen` passa 10 em
ambos.

### `MapOptions`

```dart
initialCenter: LatLng(-18.5, -44.0),   // centro aproximado de MG
initialZoom: 6,
minZoom: 6,
cameraConstraint: CameraConstraint.containCenter(
  bounds: MapControllerLogic.mgBounds,
),
interactionOptions: InteractionOptions(
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
  scrollWheelVelocity: 0.005,
  pinchZoomThreshold: 0.5,
),
```

`InteractiveFlag.all & ~InteractiveFlag.rotate` habilita todos os gestos
**menos** rotação — um mapa girado confunde e não traz nada aqui.

### Camadas

1. **`TileLayer`** — CARTO Light com `{s}` e quatro subdomínios. A URL
   com placeholder de subdomínio corrigiu um bug real: tudo ia para o
   mesmo host e o rate-limit derrubava tiles em Belo Horizonte e região.
   `userAgentPackageName: 'com.LuisFelipe.PlantioAPP.dev'`.
2. **`PolylineLayer`** — contorno de MG em verde, 3 px, se o shape
   carregou.
3. **`MarkerLayer`** — pin verde de 40 px no ponto selecionado, se
   houver.

### ⚠ Duplicação com `MgShapeService`

O widget tem um `_loadMask()` próprio que lê `assets/mg.geojson` e faz
exatamente o mesmo parse do `MgShapeService`, já carregado no boot. São
duas cópias do polígono em memória e duas leituras do asset.

**Note também** que este `TileLayer` **não** usa o
`CachedRegionTileProvider` — ou seja, a tela inicial não lê do mapa base
em disco; só o mapa da análise faz isso. Ambos no doc 12.

---

## `genotype_plot.dart` — 314 linhas

O mapa da tela de análise. `StatefulWidget`. Onde as células aparecem.

### Interface

```dart
final bool isLoading;
final LatLng selectedPoint;
final Function(Offset)? onMarkerMoved;
final double minZoom;   // default 10
final double maxZoom;   // default 17
final double opacity;   // default 0.7, vem do state pai
```

Desde o mapa monocromático, o widget **não recebe mais** `points` nem
`winnerColors`: lê `AnalysisService().cells` direto e pede os polígonos
prontos ao service.

### Estado

```dart
final MapController _mapController = MapController();
GridCell? _selectedCell;
LatLngBounds? _bounds;
final AppMode _mode = AppMode();
```

### Seleção inicial

No `initState`, resolve a célula do ponto que veio da `MapScreen`:

```dart
_selectedCell = AnalysisService().resolveCell(
  Offset(widget.selectedPoint.longitude, widget.selectedPoint.latitude),
);
```

É o **mesmo `resolveCell`** que o `AnalysisController` usa. Antes cada um
fazia a própria dança de `cellContaining` mais centroide mais próximo, e
os dois podiam discordar — o realce sumia ou marcava célula diferente da
que estava na lista.

Há uma segunda tentativa no `build`, porque no `initState` as células
podem ainda não estar carregadas. Só roda enquanto `_selectedCell` é
`null`.

### O workaround do `fitCamera`

```dart
if (cells.isNotEmpty) {
  _bounds = _computeBounds(cells);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _mapController.fitCamera(CameraFit.bounds(bounds: _bounds!, padding: ...));
  });
}
```

O `flutter_map` não pede tiles no primeiro frame quando usa
`initialCameraFit` dentro de um `Stack`. Pré-computar os bounds e agendar
um `fitCamera` no primeiro post-frame força o mapa a pedir tiles assim
que sabe o próprio tamanho. Sem isso, a tela abre cinza até o usuário
dar zoom.

O padding é assimétrico (`right: 72`) para deixar espaço ao botão de
tela cheia.

### `_onPositionChanged` — clamp da câmera

Se o usuário arrasta (`hasGesture`) para fora dos bounds das células, a
câmera é trazida de volta com `clamp` em latitude e longitude. Mantém o
usuário dentro da região analisada.

### `_onTap`

```dart
final cell = AnalysisService().cellContaining(geo);
if (cell == null) return;            // tap fora do grid: ignora
setState(() => _selectedCell = cell);
widget.onMarkerMoved?.call(cell.centroid);
```

**⚠ Nota**: aqui é `cellContaining`, não `resolveCell`. É coerente — no
toque, um tap fora do grid deve ser ignorado, não "aproximado" — mas o
callback leva o centroide ao controller, que então chama `resolveCell`.
Como o centroide sempre cai dentro da própria célula, os dois concordam.

### O realce "sanduíche"

```dart
static const double _outerBorderWidth = 6.0;   // preta
static const double _innerBorderWidth = 3.0;   // branca
```

Dois polígonos empilhados com os **mesmos pontos** e fill transparente:
o traço branco, mais fino, é desenhado sobre o centro do traço preto,
resultando em preto-branco-preto de fora para dentro.

Cores opostas garantem contraste em qualquer cenário: a borda preta
aparece sobre fundo claro, a branca sobre fill escuro. É uma decisão de
acessibilidade — funciona também para quem não distingue bem cores.

### As três camadas do mapa

1. **`TileLayer`** — CARTO Light, `maxNativeZoom: _mode.isOffline ? 10 :
   18`, e `tileProvider: CachedRegionTileProvider()` — este é o único
   mapa do app que lê do mapa base offline.
2. **`PolygonLayer` das células**, com `useAltRendering: true` (renderer
   alternativo do `flutter_map`, mais rápido para muitos polígonos),
   dentro de um `RepaintBoundary` para que mudanças no realce não forcem
   repaint das milhares de células.
3. **`PolygonLayer` do realce**, com a lista vazia quando nada está
   selecionado (a camada aceita lista vazia sem drama).

### Estados

- `isLoading` → `CircularProgressIndicator` centralizado.
- `cells.isEmpty` → `ColoredBox` bege com "Sem dados".

---

## `genotype_detail_card.dart` — 350 linhas

A ficha do cultivar selecionado. `StatelessWidget`.

Todo o conteúdo vem de `assets/cultivares.json` via `CultivarInfoService`.

### O que mudou e por quê

Antes esta tela mostrava quatro linhas **fixas no código**, iguais para
qualquer cultivar: "92 sc/ha", "Estabilidade Climática: Alta", "Ciclo:
Médio", "Tolerância Hídrica: Boa".

Sumiram todas. As duas primeiras viraram dado real; as outras duas não
têm fonte nenhuma por trás.

> **O card não inventa**: campo sem dado simplesmente não aparece, e
> cultivar fora da planilha mostra um aviso honesto em vez de zeros.

### Interface

```dart
final String genotype;     // nome como o backend devolve
final String? municipio;   // "PATROCINIO_2026" — normalizado internamente
final double? width;
```

```dart
final info = CultivarInfoService().infoFor(genotype);
final produtividade = info?.produtividade(
  municipio: municipio == null ? null
      : CultivarInfoService.chaveMunicipio(municipio!),
);
```

### Estrutura

1. Nome do cultivar centralizado, 20 px, negrito.
2. Se `info == null` → `_SemDados`.
3. Senão: bloco de produtividade (se houver), linha de ferrugem (se
   houver), linha de nematóide (se houver).

### `_BlocoProdutividade`

Número grande em `AppColors.greenDark` (30 px) com "sc/ha" ao lado, sobre
fundo verde a 8% de opacidade.

Abaixo, a procedência:

- `"Média dos ensaios deste município em 2025 · 4 registros"`, ou
- `"Média dos ensaios em Minas Gerais em 2025 · 62 registros"`.

Quando o dado é estadual, acrescenta em itálico: *"Ainda não há ensaio
registrado neste município."*

#### A regra da amostra pequena

```dart
static const int _amostraMinima = 3;

final comparar = dados.doMunicipio &&
    dados.registros < _amostraMinima &&
    estadual != null;
```

Abaixo de 3 registros, um número municipal é uma medição solta, não uma
média — vários municípios têm um único registro, às vezes de anos atrás.
Nesses casos o card mostra a média estadual ao lado:

> "Amostra pequena. Em Minas Gerais: 35,5 sc/ha (2025, 62 registros)."

Sem isso, uma única medição de 102 sc/ha viraria a manchete do card como
se fosse o esperado da região.

### `_LinhaResistencia`

Rótulo à esquerda, chip colorido à direita, detalhe opcional abaixo.

```dart
Color get _cor {
  final v = valor.toLowerCase();
  if (v.startsWith('moderadamente')) return const Color(0xFFB26A00);  // âmbar
  if (v.startsWith('resistente'))    return AppColors.greenDark;      // verde
  if (v.startsWith('suscet'))        return const Color(0xFFB3261E);  // vermelho
  return Colors.black54;                                              // cinza
}
```

A ordem dos testes importa: "Moderadamente Resistente" precisa ser
testado antes de "Resistente", senão cairia no verde.

Verde/âmbar/vermelho é leitura que qualquer produtor faz sem legenda; o
cinza cobre texto que não se encaixa nos três.

O chip está dentro de `Flexible` para que nomes longos não estourem a
linha em telas estreitas.

O `detalhe` é o texto completo da célula de nematóide quando ele
acrescenta algo ao rótulo — por exemplo "Suscetível a M. paranaensis…
Resistente (M. exigua)". É `null` quando repetiria o rótulo.

### `_SemDados`

Ícone de informação e o texto:

> "Ainda não temos ficha técnica deste cultivar. A recomendação do mapa
> continua válida — só não há dados de resistência e produtividade
> registrados para ele."

---

## `genotypes_list.dart` — 80 linhas

Lista horizontal de chips com os cultivares recomendados.
`StatelessWidget`.

```dart
final List<String> cultivares;      // o selectedRanking do controller
final String? selectedGenotype;
final ValueChanged<String> onSelect;
```

`ListView.builder` horizontal de 60 px de altura. Cada item é um
`AnimatedContainer` (200 ms) com raio 20:

- selecionado → fundo `AppColors.green`, texto branco;
- não selecionado → fundo `AppColors.green` a 12%, borda a 35%, texto
  escuro.

Devolve `SizedBox.shrink()` se a lista estiver vazia.

### Contexto histórico

Existiam **duas** listas na tela de análise: a "Legenda" (todos os
vencedores do município, cada um com a cor que o mapa usava) e o ranking
do ponto. Com o mapa monocromático a legenda perdeu função — não há mais
cor para legendar. Sobrou esta, que responde à pergunta que o usuário
realmente faz: *"o que planto aqui?"*.

Por isso o widget não recebe mais mapa de cores.

---

## `cycle_selection_picker.dart` — 223 linhas

Seletor de Ciclo de Maturação. `StatefulWidget`.

Uma pílula que **expande para o lado**:

```
Colapsada:   Ciclo de Maturação · Médio                    ›
Expandida:   Ciclo de Maturação · Curto Médio Longo        ‹
```

### Por que horizontal

A pílula flutua sobre o mapa. Crescer para baixo empurraria conteúdo
sobre a área onde o usuário toca para escolher o ponto.

`AnimatedSize` (260 ms) interpola a **largura**; `AnimatedSwitcher`
(200 ms) faz o cross-fade entre "valor atual" e "as três opções". Juntos,
o crescimento é contínuo em vez de um pulo.

### O `layoutBuilder` customizado

```dart
layoutBuilder: (currentChild, previousChildren) => Stack(
  alignment: Alignment.centerLeft,
  children: [...previousChildren, if (currentChild != null) currentChild],
),
```

O `layoutBuilder` padrão do `AnimatedSwitcher` empilha os filhos durante
a transição, e o antigo continua contando para o tamanho — a seta
pularia. Com este, só o filho atual conta.

### As `ValueKey`

`_buildCurrentValue` e `_buildOptions` usam `ValueKey('collapsed')` e
`ValueKey('expanded')`. É o que sinaliza ao `AnimatedSwitcher` que o
filho mudou.

### Aperto de largura

"Ciclo de Maturação" + três opções + seta não cabem folgados num
aparelho de 360 dp. Três decisões respondem a isso:

- o label vive num `Flexible` com `TextOverflow.ellipsis` (nunca
  estoura);
- as opções usam fonte 13 e o label 14, mantendo a hierarquia;
- não há separadores `|` entre as opções — a selecionada já se distingue
  pelo fundo verde.

### A raiz é o `Material`, sem `Center`

Decisão explicada no código: com um `Center` na raiz, uma `GlobalKey`
pendurada de fora mediria a faixa inteira da tela, e o spotlight do
tutorial sombrearia área muito maior que o seletor. Quem centraliza é o
pai.

### Estado

`_expanded` é estado puramente de UI e vive aqui. O valor persistente do
ciclo continua no `CropCycleService`.

`_pickCycle` tem dois efeitos: grava no service e colapsa a pílula.

A seta faz meia volta (`AnimatedRotation`, `turns: 0.5`) quando
expandido.

---

## `opacity_slider.dart` — 107 linhas

Slider com trilho em gradiente. `StatelessWidget`.

```dart
final double value;
final ValueChanged<double> onChanged;
final Color color;       // default AppColors.green
final bool showLabel;    // default true
```

### O truque

Dois widgets num `Stack`:

1. Um `Container` decorativo de 8 px de altura com um `LinearGradient`
   de transparente até a cor cheia.
2. Um `Slider` real por cima, com `SliderTheme` deixando
   `activeTrackColor` e `inactiveTrackColor` transparentes.

O Material cuida só do thumb e do gesto de arrastar. O resultado é que o
gradiente aparece **inteiro**, em vez de ser cortado no meio como no
slider padrão, que colore apenas o lado ativo.

O trilho é uma pré-visualização honesta do que o slider controla: o
mesmo verde das células.

`showLabel: false` é usado no modo fullscreen, onde o slider flutua sobre
o mapa e não precisa de legenda.

---

## `partner_logos.dart` — 103 linhas

Marcas EPAMIG e UFV lado a lado. `StatelessWidget`. Usada na splash e na
tela "Sobre".

Existe como widget único para que as duas apareçam sempre com o mesmo
alinhamento e proporção — logo institucional é a peça que mais sofre
quando cada tela resolve o próprio tamanho.

Envolto em `Semantics(label: 'Instituições parceiras: EPAMIG e UFV')`,
com `excludeFromSemantics: true` nas imagens.

### O dimensionamento por área ótica

```dart
static const double _fatorEpamig = 0.60;   // = sqrt(1,27 / 3,49)
```

As duas têm proporções muito diferentes: a UFV é quase quadrada (1,27:1)
e a EPAMIG é um logotipo deitado (3,49:1). Nesse caso **igualar a altura
não equilibra** — a deitada fica com mais do que o dobro da área e domina
a linha; igualar a largura inverte o problema.

A regra é igualar a **área ótica**: para área alvo `A` e proporção `r`, a
altura é `sqrt(A / r)`. Daí o fator 0,60.

O espaçamento entre elas é `altura * 0.55` — proporcional, porque
aumentar as marcas sem aumentar o respiro as faz parecer coladas.

### As correções nos arquivos SVG

O dartdoc registra o trabalho feito nos arquivos, que vale conhecer
antes de trocar qualquer um deles:

**EPAMIG** — as cores viviam num bloco `<style>` CSS com classes
(`.fil0`..`.fil4`), formato que o CorelDRAW gera. O `flutter_svg` **não
aplica CSS por classe**, então a marca aparecia inteiramente preta (preto
é o `fill` padrão de quem não recebeu cor). As declarações foram movidas
para atributos `fill=` inline.

> **Regra prática registrada no código**: neste projeto, SVG só é
> confiável com `fill=` inline.

Além disso, o arquivo vinha num canvas quadrado com a arte ocupando 24%
da altura — o `viewBox` foi recortado até a arte antes de o cálculo de
proporção significar alguma coisa.

**UFV** — três problemas: um path quase branco (#fdfdfd) cobrindo o
canvas inteiro (que apareceria como retângulo branco sobre a splash
bege); 738 subcaminhos fantasma no path dourado, restos do anti-aliasing
da imagem original vetorizada automaticamente; e 146 KB de peso, que
caiu para 21 KB depois das correções.

---

## `searchbar_widget.dart` — 49 linhas

Componente reutilizável de barra de busca com lista de sugestões.

**⚠ Não é montado por nenhuma tela.** A `MapScreen` constrói a própria
barra inline, em `_buildTopBar()`, porque precisa de coisas que este
widget não oferece: `TextEditingController` externo, botão de limpar,
`onTapOutside`, altura máxima do dropdown, e a `GlobalKey` no card.

Não está marcado `@Deprecated`, mas está órfão. Ver doc 12.

---

## `onboarding_overlay.dart` — 875 linhas ⭐

O motor do tutorial. É o segundo maior arquivo do app.

### O que faz

Escurece a tela inteira e abre um "buraco" (spotlight) em volta de um
elemento real da interface, com o texto explicativo sobre a sombra.
Setas embaixo navegam; um botão discreto pula tudo.

### Por que sem cartão branco

Um card opaco no meio da tela competiria com o elemento destacado — dois
blocos claros disputando atenção sobre o mesmo fundo escuro. Sem o card,
o único ponto claro é o spotlight, e o texto (branco sobre a sombra) fica
como legenda dele.

Para o texto sobreviver a qualquer coisa que apareça pelo buraco, ele
ganha um degradê radial local (`_TextScrim`) em vez de caixa sólida:
escurece só o suficiente, sem borda visível.

### `OnboardingStep`

```dart
final GlobalKey? targetKey;   // null = passo sem destaque
final String title;
final String description;
final bool circular;          // recorte redondo
final double? maxSize;        // teto do recorte, em px lógicos
final double padding;         // folga em volta do alvo (default 8)
final int introducedIn;       // versão em que o passo entrou (default 1)
```

`maxSize` existe por causa do mapa: destacar o `RenderBox` inteiro dele
abriria um buraco do tamanho da tela e o spotlight não destacaria nada.

`padding` menor é usado em alvos baixos e largos, como a pílula do ciclo,
para a sombra não sobrar em volta.

### `showOnboarding(...)` — a entrada pública

```dart
final novos = steps.where((s) => s.introducedIn > sinceVersion).toList();
if (novos.isEmpty) {
  onFinish();                       // avança a sentinela assim mesmo
  return Future<void>.value();      // e nem empilha a rota
}
return Navigator.of(context).push(PageRouteBuilder<void>(
  opaque: false,                    // a tela de baixo continua pintada
  barrierDismissible: false,
  ...
));
```

`opaque: false` é o que faz o spotlight funcionar: a tela de baixo
continua montada e renderizada — é ela que aparece pelo buraco.

### Como o overlay encontra os elementos

```dart
Rect? _rectFor(OnboardingStep step) {
  final ctx = step.targetKey?.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;

  var rect = box.localToGlobal(Offset.zero) & box.size;

  // teto de tamanho: encolhe para o centro
  if (max != null && (rect.width > max || rect.height > max)) {
    rect = Rect.fromCenter(center: rect.center, width: ..., height: ...);
  }

  rect = rect.inflate(step.padding);
  return rect.intersect(Offset.zero & MediaQuery.sizeOf(context));  // clamp
}
```

O `intersect` com a tela mantém visível o buraco de alvos colados na
borda (FAB, ícone da AppBar).

Passos cujo alvo não está montado são **descartados na montagem**:

```dart
final visible = widget.steps
    .where((s) => s.targetKey == null || _rectFor(s) != null)
    .toList();
```

É o que faz o tutorial se adaptar ao que está de fato na tela — a barra
de busca some no modo offline, e o passo dela simplesmente não aparece.

### Buraco de tamanho zero

```dart
Rect _holeFor(OnboardingStep step) {
  return _rectFor(step) ??
      Rect.fromCenter(center: screenCenter, width: 0, height: 0);
}
```

Passos sem alvo (abertura e encerramento) **não** viram "sem buraco":
viram um buraco de tamanho zero no centro. Isso mantém **um único**
`TweenAnimationBuilder` vivo do primeiro ao último passo, e é o que faz o
foco abrir e fechar animado nas pontas.

Antes, alternar entre "sem recorte" e "com recorte" trocava o widget de
lugar na árvore e a animação só começava do passo 2.

### A coreografia da troca de dica

```
0 ─────── 220ms ─────── 480ms ─────── 700ms
│ texto sai │                          │
│      foco viaja (0 → 480)            │
│              │ texto novo entra      │
```

```dart
static const Duration _morph = Duration(milliseconds: 480);
static const Curve _morphCurve = Curves.easeInOutCubic;
static const Duration _textSwap = Duration(milliseconds: 700);
static const Curve _textInCurve  = Interval(0.65, 1.0, curve: Curves.easeOut);
static const Curve _textOutCurve = Interval(0.7,  1.0, curve: Curves.easeIn);
```

Um controller único de 700 ms com `Interval` nas curvas: o texto sai nos
primeiros instantes e entra só depois de 65% do caminho. **É assim que se
escalona sem `Future.delayed`** — o atraso vira parte da curva, então
nada dessincroniza se um frame atrasar.

Sem isso, o texto novo aparecia enquanto o foco ainda estava viajando e
as duas animações pareciam brigar.

### `_ensureVisible` — rolar antes de acender

```dart
await Scrollable.ensureVisible(ctx, duration: 320ms, curve: easeInOut, alignment: 0.5);
```

Necessário na tela de análise, que é um `SingleChildScrollView` com
metade dos alvos fora da viewport. A rolagem acontece **antes** de trocar
o passo: se fosse depois, o buraco animaria até a posição antiga do alvo
e só então corrigiria, dando um solavanco.

`alignment: 0.5` centraliza o alvo, deixando espaço dos dois lados para o
texto.

É no-op quando não há `Scrollable` ancestral (caso da `MapScreen`), então
não precisa de guarda.

### `_SpotlightPainter`

```dart
canvas.drawPath(
  Path.combine(PathOperation.difference, screenPath, holePath),
  scrim,   // preto a 78%
);
```

`PathOperation.difference` = tela **menos** buraco. É recorte de verdade:
o que está embaixo aparece nítido, sem véu por cima.

Depois, três acabamentos:

1. **Halo** — um stroke de 18 px borrado (`MaskFilter.blur`) em branco a
   16%, dentro de um `saveLayer`. Dá sensação de luz vindo do elemento e
   adoça a passagem do claro para o escuro; sem ele a borda fica dura
   como recorte de papel.
2. **`BlendMode.clear`** sobre o buraco — recorta o halo que invadiu o
   miolo, para o elemento destacado aparecer limpo.
3. **Fio claro** de 1,5 px branco a 55% exatamente na borda — define o
   limite do foco quando o elemento destacado também é claro (a pílula
   branca do ciclo, o card da busca).

O raio: `hole.longestSide / 2` quando `circular` (satura o arredondamento
e o `RRect` vira círculo ou stadium), senão 18. Uma forma só é o que
permite o buraco **morfar** entre passos.

### `_buildContent` — posicionamento em três tentativas

```dart
const needed = 290.0;   // altura típica do bloco de texto + controles

if (spaceBelow >= needed) → abaixo do recorte
else if (spaceAbove >= needed) → acima do recorte
else → ancorado no rodapé
```

A terceira tentativa é usada quando o buraco fica no meio da tela e não
sobra altura de nenhum lado — o caso do passo do mapa em aparelhos
baixos. Aí o texto pode encostar no recorte, e é por isso que ele tem
scrim próprio.

Sem essa etapa, o bloco era empurrado para fora da tela e o `Stack`
simplesmente cortava os botões.

Passo sem alvo (buraco vazio) é centralizado.

### `_StepContent` — a adaptação a um passo só

Quando o roteiro filtrado tem **um único passo** (o caso "recurso novo
numa atualização"), três coisas mudam:

| Elemento | Com vários passos | Com um passo |
|----------|-------------------|--------------|
| contador | "2 de 7" | "NOVIDADE" |
| bolinhas de progresso | aparecem | escondidas |
| botão voltar | aparece (apagado no 1º) | escondido |
| rótulo do botão | "Próximo" / "Começar a usar" | "Entendi" |
| "Não desejo fazer o tutorial" | aparece | escondido |

O raciocínio está no código: "Começar a usar" soaria como se o usuário
tivesse acabado de conhecer o app; e com um passo só, "pular" e "Entendi"
fariam a mesma coisa, e duas saídas idênticas só confundem.

### Um caminho único de saída

```dart
void _close() {
  widget.onFinish();
  Navigator.of(context).pop();
}
```

Concluir, pular e o botão físico de voltar (via `PopScope`) caem todos
aqui — assim `onFinish` nunca deixa de rodar e o tutorial não reaparece
na próxima abertura. Pular é decisão do usuário e é respeitada.

Há ainda um `GestureDetector` opaco cobrindo a tela, que absorve toques
na área escura para o usuário não interagir com a tela de baixo por
acidente durante o tutorial.

---

## `onboarding_service.dart` — 152 linhas

O par do overlay: responde "o usuário já viu este tutorial?".

### Os fluxos

```dart
enum OnboardingFlow {
  map('done', 1),
  analysis('analysis', 1);

  final String id;    // vira sufixo do arquivo: .onboarding_done
  final int version;  // versão atual do roteiro
}
```

> **Não renomeie ids já publicados**: mudar o id equivale a apagar a
> sentinela, e o tutorial reaparece inteiro para quem já tinha visto.

`map` mantém o id histórico `done` — era o nome do arquivo quando só
existia um tutorial.

### O mecanismo de versão

O tutorial não é apenas "primeira abertura": ele também precisa
**apresentar recurso novo para usuário antigo**. Quem instalou em janeiro
e já viu o tutorial não deve ficar sem saber que existe um botão novo em
março.

A sentinela guarda a versão vista. Se a `version` do fluxo for maior, o
tutorial roda de novo mostrando **só os passos com `introducedIn` maior
que a versão vista**. Usuário novo (versão 0) recebe tudo.

> **Ao adicionar uma feature numa tela**: crie o `OnboardingStep` com
> `introducedIn: <nova versão>` e incremente a `version` do fluxo. São as
> duas linhas que fazem o recurso se anunciar sozinho.

### `seenVersion(flow)` e a política de falha

```dart
try {
  if (!await file.exists()) { value = 0; }
  else {
    final raw = (await file.readAsString()).trim();
    value = int.tryParse(raw) ?? 1;      // sentinela vazia = formato antigo
  }
} catch (e) {
  value = flow.version;                  // falha de I/O = "já viu tudo"
}
```

Dois detalhes:

- Sentinela **vazia** (formato antigo, de quando só existia "viu/não
  viu") conta como versão 1 — quem já tinha visto não recebe o tutorial
  de novo por causa da migração.
- Falha de I/O devolve a versão atual, ou seja "já viu tudo": em caso de
  dúvida, não incomodar. Um veterano tomando tutorial na cara por erro de
  disco é pior que um novato sem tutorial.

Há um `debugPrint` na primeira leitura de cada fluxo, que é a resposta
para "por que o tutorial não apareceu?".

O valor é cacheado em memória por fluxo — as telas consultam no boot e a
checagem não toca o disco de novo na mesma sessão.

### `markSeen(flow)`

Atualiza o cache em memória **antes** do `await`, de forma que mesmo que
a gravação falhe o tutorial não reapareça no meio da sessão.

### `reset` / `resetAll`

Apagam as sentinelas. `resetAll` é o que o botão de debug da tela "Sobre"
chama.

---

## Widgets desativados

Detalhes em [doc 13](13-codigo-desativado.md).

| Arquivo | Estado |
|---------|--------|
| `app_drawer.dart` | `@Deprecated` — os quatro itens iam para a mesma tela e dependem de login |
| `crop_selection_sheet.dart` | `@deprecated` — seleção de cultura (milho/café/feijão) |
| `points_plot.dart` | `@Deprecated` — plot em canvas puro, anterior ao `flutter_map` |
