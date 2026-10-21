# 03 — Entrypoint e telas

---

## `main.dart` — 125 linhas

**Responsabilidade**: subir a árvore de widgets e definir o tema global.

Faz três coisas e nada mais:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}
```

`ensureInitialized()` é obrigatório antes de qualquer API que dependa do
binding (leitura de assets, `path_provider`). Na prática, como o
`bootstrapApp()` roda *depois* do `runApp`, o binding já estaria pronto
— a chamada explícita documenta a dependência.

### Por que o boot saiu daqui

Historicamente `main()` era `async` e dava `await` em toda a
inicialização antes do `runApp`. Funcionava, mas durante essa espera o
usuário via tela branca: o Flutter só tem o que desenhar depois do
`runApp`. Hoje o `runApp` acontece imediatamente e a `SplashScreen`
chama `bootstrapApp()`. O tempo total é o mesmo; a diferença é o que
ocupa esse tempo.

A função de boot vive em `services/app_bootstrap.dart` e não aqui para
evitar o import circular `main → splash → main`.

### `MyApp` — o tema global

`StatelessWidget` que devolve um `MaterialApp` com
`debugShowCheckedModeBanner: false` e um `ThemeData` que define:

| Item | Valor |
|------|-------|
| `primaryColor` | `AppColors.green` (`0xFF02890A`) |
| `colorScheme` | `ColorScheme.fromSeed(seedColor: AppColors.green)` |
| `textSelectionTheme` | cursor verde, seleção verde translúcida |
| `inputDecorationTheme` | borda padrão, borda verde de 2px no foco, vermelha no erro, label flutuante verde |
| `filledButtonTheme` | fundo verde, texto branco, raio 5 |
| `home` | `const SplashScreen()` |

`ColorScheme.fromSeed` gera a paleta completa (primary, secondary,
surface, error…) a partir de uma cor só, o que alinha AppBar, ripple de
toque e demais componentes Material automaticamente.

---

## `screens/splash_screen.dart` — 134 linhas

**Rota inicial.** `StatefulWidget`.

### Por que existe

Quatro coisas precisam carregar antes da primeira tela ser útil: o
polígono de MG, a ficha dos cultivares, o estado da conexão e a limpeza
do cache expirado. Essa espera antes era tela branca; agora é a marca do
app mais as instituições parceiras.

É também o lugar convencional para crédito institucional — aparece em
toda abertura, some sozinho e não ocupa espaço permanente na interface.

### Tempo mínimo em tela

```dart
static const Duration _minimo = Duration(milliseconds: 1400);

await Future.wait([
  bootstrapApp(),
  Future<void>.delayed(_minimo),
]);
```

`Future.wait` faz os dois em paralelo, então o total é o **maior** dos
dois e não a soma — o mínimo não atrasa quem já demorou. Sem ele, um
aparelho rápido com cache quente mostraria a splash por 200 ms, um flash
que parece defeito.

### Transição

```dart
Navigator.of(context).pushReplacement(
  PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, __, ___) => const MapScreen(),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);
```

`pushReplacement` tira a splash da pilha: voltar da `MapScreen` fecha o
app em vez de reabrir a abertura. O `if (!mounted) return` antes do
push é obrigatório — houve `await`.

### Layout

Fundo `AppColors.bege`, não verde: as duas marcas institucionais são
coloridas (verde e vermelho na EPAMIG, texto escuro na UFV) e sobre o
verde do app ficariam sujas e fora do padrão institucional.

A `Column` usa `Expanded` com `flex` desiguais — 5 para o bloco central
(logo + spinner), 2 para o rodapé — deixando a marca acima do centro
geométrico, que é onde o olho procura.

---

## `screens/map_screen.dart` — 961 linhas ⭐

**A tela inicial do app.** `StatefulWidget`. O arquivo mais longo entre
as telas.

### O que o usuário vê

- Mapa de MG (`MapWidget` → `flutter_map`), ocupando a tela.
- AppBar com a logo Typica à esquerda; à direita o botão de download do
  mapa base e um menu `?`.
- Online: barra de busca de cidades + pílula de Ciclo de Maturação,
  flutuando sobre o mapa.
- Offline: badge vermelho "Modo offline" + pílula "Regiões salvas no
  aparelho".
- FAB verde de GPS no canto inferior direito.
- Quando há ponto selecionado: barra inferior "Confirmar localização".

### Os quatro notifiers observados

```dart
final MapControllerLogic _logic  = MapControllerLogic();  // da tela
final CitySearchController _search = CitySearchController(); // da tela
final BaseMapService _baseMap    = BaseMapService();  // global
final AppMode _mode              = AppMode();          // global
```

Mais o `TextEditingController` da busca, que também é `ChangeNotifier` —
escutado para mostrar/esconder o botão ✕ de limpar.

No `dispose`: remove os quatro listeners, depois dá `dispose()` apenas
em `_logic` e `_search`. Os globais continuam vivos.

### As cinco `GlobalKey` do tutorial

```dart
final GlobalKey _searchKey   = GlobalKey();  // card da busca
final GlobalKey _cycleKey    = GlobalKey();  // pílula do ciclo
final GlobalKey _mapKey      = GlobalKey();  // o mapa
final GlobalKey _gpsKey      = GlobalKey();  // FAB
final GlobalKey _downloadKey = GlobalKey();  // ícone da AppBar
```

Cada chave é pendurada no widget real. O overlay lê a geometria via
`RenderBox.localToGlobal`, então o recorte do spotlight acompanha o
layout de verdade — mexer no layout não quebra o tutorial.

A chave `_downloadKey` fica num `KeyedSubtree`, e não no widget direto,
porque `_buildBaseMapAction()` devolve tipos diferentes conforme o
estado (spinner ou `IconButton`). Pendurar a chave neles faria a chave
migrar entre elementos distintos; o `KeyedSubtree` dá um nó estável.

### Onboarding — `_maybeShowOnboarding()` e `_startOnboarding()`

Dispara sozinho em dois momentos:

1. Primeira abertura do app (nunca viu → roteiro inteiro).
2. Após atualização que trouxe recurso novo nesta tela (viu a versão
   anterior → só os passos novos).

```dart
final visto = await OnboardingService().seenVersion(OnboardingFlow.map);
if (visto >= OnboardingFlow.map.version) return;
_startOnboarding(sinceVersion: visto);
```

O botão "Rever tutorial" chama `_startOnboarding()` sem argumento, o que
usa `sinceVersion: 0` — roteiro inteiro, porque quem pede para rever
quer tudo.

O roteiro tem **7 passos**: boas-vindas (sem alvo), busca, ciclo, mapa
(circular, `maxSize: 160`), GPS (circular), download do mapa base, e
encerramento (sem alvo). Não é preciso condicionar a lista ao modo
offline: o overlay descarta passos cujo alvo não está montado, e a barra
de busca simplesmente não existe offline.

Roda em `addPostFrameCallback` porque antes do layout não há geometria
para recortar.

### Mapa base — os três estados do botão

`_buildBaseMapAction()` devolve um de três widgets:

| Estado | Widget |
|--------|--------|
| `isDownloading` | spinner com percentual ao lado, em texto branco |
| `isDownloaded` | `Icons.cloud_done` em verde claro |
| idle | `Icons.cloud_download_outlined` |

`_onBaseMapTap()` ramifica igual: durante download, ignora o toque (a
barra já mostra que algo acontece); se baixado, abre o diálogo de info;
senão, pede confirmação.

`_askConfirmBaseMapDownload()` calcula a estimativa na hora
(`estimateBytes()` / `estimateTiles()` — fórmula pura, barata) e mostra
"Vai baixar ~N tiles (~X MB)… Recomendado fazer com Wi-Fi".

`_showBaseMapInfoDialog()` mostra o que já está em disco e oferece
**"Baixar novamente"**, que faz `delete()` seguido de `download()`.
Existe porque um cache antigo pode ter buracos (rate-limit em versões
anteriores, tile server instável).

O `download()` é fire-and-forget: dispara e volta ao build; o
`ChangeNotifier` propaga o progresso.

### Validação do ponto

`_showInvalidLocationMessage()` mostra um `SnackBar` vermelho
"Selecione um ponto dentro de Minas Gerais". É passado como callback
`onInvalid` para os três caminhos de seleção (toque no mapa, cidade
escolhida na busca, GPS).

### `_confirmLocation()` — o preflight

```dart
showDialog(barrierDismissible: false, builder: (_) => _PreflightLoadingDialog());
try {
  await AnalysisService().load(lat: p.latitude, lng: p.longitude);
  Navigator.of(context, rootNavigator: true).pop();   // fecha o loading
  Navigator.push(... AnalysisScreen(selectedPoint: p, selectedCrop: ''));
} catch (e) {
  Navigator.of(context, rootNavigator: true).pop();
  await _showConnectionErrorDialog(e);
}
```

`rootNavigator: true` garante fechar o diálogo mesmo se um `Navigator`
aninhado surgir no meio.

Note que `selectedCrop` é passado como string vazia. O parâmetro
sobreviveu de quando havia seleção de cultura (milho / café / feijão) e
hoje não é lido por nada — ver [doc 13](13-codigo-desativado.md).

### `_showConnectionErrorDialog()` — a heurística

Distingue dois casos por inspeção da exceção:

```dart
final isConnectionIssue = error is! NoDataException ||
    msg.contains('Sem sinal') ||
    msg.contains('conexão') ||
    msg.contains('conectar');
```

- **Problema de conexão** → ícone `cloud_off` vermelho, texto sugerindo
  verificar a internet, e um botão "Ver histórico" que leva à
  `HistoryScreen` (o usuário pode já ter aquela região salva).
- **Região sem dados** (404 do backend) → ícone `info_outline` laranja,
  sem sugerir histórico, porque não faria sentido.

**⚠** A heurística depende de casar substrings da mensagem de erro.
Trocar o texto de uma exceção em `analysis_service.dart` muda o
comportamento deste diálogo silenciosamente. Uma refatoração melhor
seria um campo `kind` na `NoDataException` — registrado no doc 12.

### `_buildTopBar()` — busca e ciclo

Renderizado apenas quando `_mode.isOnline`. Estrutura:

1. `Material` branco (elevation 6, raio 16) com a `GlobalKey` da busca —
   a chave fica no card inteiro, não só no `TextField`, porque é o card
   que o tutorial destaca.
2. Dentro dele: o `TextField` e, se houver sugestões, um `Divider` e um
   `ListView.separated` com altura máxima de 250 (vira scroll interno
   acima disso, para não empurrar o mapa para fora da tela).
3. `SizedBox(height: 12)`.
4. `CycleSelectionPicker` solto, com a própria pílula branca.

Detalhes do `TextField`:

- `onTapOutside` chama `unfocus()`. Sem isso, o cursor ficava piscando
  para sempre depois do primeiro tap e o teclado reabria toda vez que a
  tela recuperava foco.
- `suffixIcon` só aparece com texto: limpa o campo, limpa as sugestões
  **e** tira o foco — "limpar" é semanticamente "cancelar a busca".
- `onChanged: _search.onSearchChanged` — o debounce vive no controller.

No `onTap` de uma sugestão, três coisas acontecem **antes** do `await`,
como feedback imediato: escreve o nome no campo, fecha o dropdown, tira
o foco. Só então chama `resolveSuggestion` (que faz o Place Details). Há
`if (!mounted) return` depois do `await`, e um `SnackBar` vermelho se o
Details falhar.

### `_buildOfflineBadge()` — e por que o histórico mora aí

Duas peças empilhadas: o badge vermelho informativo e, abaixo, uma
pílula branca "Regiões salvas no aparelho" que navega para a
`HistoryScreen`.

O comentário no código explica a decisão: sem o `AppDrawer` (deprecado),
a `HistoryScreen` ficou sem porta de entrada. Ela aparece no modo
offline porque é aí que ela deixa de ser conveniência e vira o único
caminho possível — sem sinal a busca some e só regiões baixadas abrem.
Online o atalho não aparece, para manter a tela inicial limpa.

### `_PreflightLoadingDialog`

Classe privada no fim do arquivo. `Dialog` branco, raio 16, com um
`CircularProgressIndicator` verde de 28 px e o texto "Buscando dados da
região...". Não é dismissível.

---

## `screens/analysis_screen.dart` — 478 linhas ⭐

**A tela de resultado.** `StatefulWidget`, recebe `selectedPoint`
(`LatLng`) e `selectedCrop` (`String`, não usado).

### Estado

```dart
final AnalysisController _controller = AnalysisController();
double _opacity = 0.7;          // compartilhado entre mapa e slider
bool _isMapFullscreen = false;  // ramifica o build inteiro
final GlobalKey _mapKey = GlobalKey();
bool _onboardingChecked = false;
```

O `_opacity` vive aqui, no state pai, e não dentro do `GenotypePlot`,
porque o `OpacitySlider` e o mapa precisam do mesmo valor.

### A `GlobalKey` do mapa tem dois papéis

Ela existe primeiro por um motivo técnico: ao alternar entre o modo
normal e o fullscreen, o `GenotypePlot` muda de lugar na árvore de
widgets. Sem a chave, o Flutter destrói e recria o `Element`, o que
recria o `MapController` e o cache interno de tiles — a tela ficaria
cinza até o próximo gesto. Com a chave, o `Element` é preservado.

Ela é usada **também** como alvo do tutorial, mas isso é secundário.

### Ciclo de carga

```dart
@override
void initState() {
  super.initState();
  _controller.addListener(_onControllerChanged);
  _controller.load(position: widget.selectedPoint);
}
```

`_onControllerChanged()` faz `setState(() {})` e, na primeira vez que os
dados chegam, avalia o tutorial. A trava `_onboardingChecked` existe
porque esse listener roda a cada `notifyListeners()` — ou seja, a cada
toque no mapa — e sem ela o tutorial tentaria abrir de novo.

As guardas antes de avaliar: `!isLoading` e `errorMessage == null`. Só
faz sentido destacar a lista de cultivares depois que ela existe; antes
disso as `GlobalKey`s não têm contexto e os passos seriam descartados.

### Onboarding da análise

Fluxo separado (`OnboardingFlow.analysis`, sentinela própria). Dispara
na **primeira vez que o usuário chega nesta tela**, mesmo que ele já use
o app há meses: a tela de análise é recurso novo para quem nunca abriu
uma, e o tutorial da tela inicial não cobre nada daqui.

Seis passos: introdução (sem alvo), mapa (circular, `maxSize: 150`),
lista de cultivares, card de detalhes, slider de opacidade, botão de
tela cheia.

Não roda em fullscreen (`if (!mounted || _isMapFullscreen) return`) —
metade dos alvos não está montada nesse modo.

### Modo tela cheia

O `build` **ramifica cedo**:

```dart
if (_isMapFullscreen) {
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      setState(() => _isMapFullscreen = false);
    },
    child: Scaffold(body: Stack([...])),
  );
}
```

O `PopScope` intercepta o botão físico de voltar: em vez de sair da
tela, sai do fullscreen. O layout é minimal — mapa em `Positioned.fill`,
botão de voltar circular no topo (dentro de `SafeArea` e
`RepaintBoundary`, que isola o botão do painter do `FlutterMap` e evita
resíduo visual no pan), e o `OpacitySlider` sem label no rodapé.

### Modo normal

`AppBar` com título `'Análise de $titleText'`, onde:

```dart
final titleText = displayName ??
    (municipio != null ? _toTitleCase(municipio) : null);
```

Enquanto o município ainda não chegou, o título é um
`CircularProgressIndicator` de 20×20 com `strokeWidth: 2` — sem o
`SizedBox`, um indicador sem constraint tenta ocupar tudo.

`_toTitleCase` é o fallback: remove o sufixo de ano com
`RegExp(r'_\d{4}$')` e capitaliza cada palavra separada por `_`.
`"VICOSA_2026"` → `"Vicosa"` (sem cedilha — por isso o `display_name`
do backend é preferido).

O corpo é um `SingleChildScrollView` com, em ordem:

1. `MaterialBanner` vermelho com "Tentar novamente", se
   `errorMessage != null`.
2. `SizedBox(height: 300)` com o `GenotypePlot` e o botão de tela cheia
   sobreposto (canto inferior direito).
3. `OpacitySlider`.
4. Título "Cultivares recomendados" + `GenotypeList`, **só se**
   `selectedRanking.isNotEmpty`.
5. `AnimatedContainer` com o `GenotypeDetailCard`, ou o texto
   "Selecione um cultivar…" se nada estiver selecionado.

Dois detalhes de layout deliberados:

- O `AnimatedContainer` **não tem altura fixa**, só
  `constraints: BoxConstraints(minHeight: 120)`. Como está dentro de um
  `SingleChildScrollView`, o pai não impõe teto de altura; deixar o card
  definir a própria altura evita overflow quando ele cresce.
- Não há subtítulo "em ordem de indicação" sob os cultivares. A versão
  anterior tinha, mas o backend não garante ordenação por recomendação —
  afirmar uma ordem que não existe induz o usuário a erro.

O estado "Selecione um cultivar" é raro por construção: o `load` já
resolve a célula do ponto que veio da `MapScreen`. Só aparece se o ponto
não cair em nenhuma célula do grid.

---

## `screens/history_screen.dart` — 403 linhas

**Histórico de acessos / regiões salvas no aparelho.** `StatefulWidget`.

### Como se chega aqui

1. Pílula "Regiões salvas no aparelho" no topo da `MapScreen` — só no
   modo offline. É a porta principal.
2. Botão "Ver histórico" no diálogo de erro de conexão.

Não há entrada no modo online. Decisão de manter a tela inicial limpa; o
`AppDrawer`, que antes levava aqui, está deprecado.

### De onde vem o dado

Direto da tabela `cachedRegions` do Drift, ordenada por `lastAccessAt
DESC`, limitada a 50:

```dart
Future<List<CachedRegionRow>> _loadHistory() {
  final db = RegionDatabase.instance;
  return (db.select(db.cachedRegions)
        ..orderBy([(r) => OrderingTerm(
              expression: r.lastAccessAt, mode: OrderingMode.desc)])
        ..limit(50))
      .get();
}
```

**Consequência importante**: toda linha aqui é uma região já baixada, e
portanto abrível sem internet. Não existe entrada de histórico "sem
cache" — se a região saiu na eviction ou no prune de TTL, ela some
daqui também. Isso é intencional: uma lista que oferecesse regiões
impossíveis de abrir offline seria pior que uma lista curta.

**⚠** É a única tela que fala com o Drift diretamente, sem passar pelo
`RegionCacheService`. Dívida registrada no doc 12.

### O `Future` guardado

```dart
late Future<List<CachedRegionRow>> _future;
// initState: _future = _loadHistory();
```

Criado uma vez e guardado num campo. Se ficasse inline no
`FutureBuilder`, cada rebuild — por exemplo, uma mudança de
conectividade — dispararia uma query nova e a lista piscaria.

### Estados da tela

| Situação | Widget |
|----------|--------|
| carregando | `CircularProgressIndicator` centralizado |
| erro | `_MessageState` com `Icons.error_outline` e texto sobre banco local |
| vazio | `_MessageState` com `Icons.travel_explore_outlined` explicando que confirmar uma localização salva a região |
| com dados | `_Header` + `ListView.separated` de `_RegionTile` |

### `_Header`

Muda de texto conforme o modo, porque a pergunta do usuário muda:

- Offline: "N regiões salvas no aparelho. Todas abrem sem internet."
- Online: "N regiões consultadas recentemente. Toque para abrir a
  análise de novo."

### `_RegionTile`

Título: `_displayName(row) ?? _toTitleCase(row.municipio)`. O
`_displayName` decodifica o JSON de `metadata` e lê `display_name`;
devolve `null` em linhas antigas ou se o JSON estiver corrompido.

Subtítulo: `_relativeDate(lastAccessAt)`, e `· N consultas` apenas se
`accessCount > 1` — "1 consulta" não informa nada que a data já não
diga.

`_relativeDate` é uma implementação manual em cascata, sem o pacote
`intl`:

| Diferença | Texto |
|-----------|-------|
| < 1 min | "Agora mesmo" |
| < 60 min | "Há N min" |
| < 24 h | "Há N hora(s)" |
| 1 dia | "Ontem" |
| < 30 dias | "Há N dias" |
| < 12 meses | "Há N mês(es)" |
| resto | "Há N ano(s)" |

A granularidade é proposital: ninguém precisa saber que foi "há 3 horas
e 12 minutos" — a pergunta é "isto é recente ou velho?".

Selo "Disponível offline" só aparece offline. Online ele seria ruído,
porque toda linha da tabela está em cache e o selo não distinguiria
nada.

### `_openRegion()`

```dart
final center = LatLng(
  (row.minLat + row.maxLat) / 2,
  (row.minLon + row.maxLon) / 2,
);
Navigator.push(... AnalysisScreen(selectedPoint: center, selectedCrop: 'Café'));
```

Abre a análise no **centro do bbox salvo**. É uma aproximação: o usuário
pode ter consultado a borda do município. Mas o bbox é tudo que o cache
guarda — as células individuais moram no `.geojson` e o ponto exato do
acesso não é registrado. O comentário no código sugere o caminho se isso
incomodar: gravar lat/lng do acesso numa coluna nova ou numa tabela
`access_log`.

---

## `screens/about_screen.dart` — 206 linhas

**"Sobre o app".** `StatelessWidget`. Acesso: menu `?` da AppBar da
`MapScreen` → "Sobre o app".

Casa permanente do crédito institucional — a splash mostra as marcas em
toda abertura, mas some sozinha em segundos.

Conteúdo, em `SingleChildScrollView` sobre fundo bege:

1. Logo Typica (SVG, 200 px) e uma frase de posicionamento.
2. Seção "Instituições parceiras" → `PartnerLogos(altura: 56)`.
3. Seção "Origem dos dados" — três parágrafos: recomendações vindas da
   análise agronômica sobre a malha IBGE; ficha do cultivar vinda dos
   ensaios de campo, sempre com ano e número de medições; mapa base do
   CARTO sobre dados OpenStreetMap.
4. Seção "Versão" — `FutureBuilder<PackageInfo>` com
   `PackageInfo.fromPlatform()`, mostrando `"${version} (build
   ${buildNumber})"`. Enquanto não há dado, devolve um
   `SizedBox(height: 20)` para a coluna não pular.
5. **Só em debug** (`if (kDebugMode)`): seção "Desenvolvimento" com o
   botão `_ResetTutoriais`, que chama `OnboardingService().resetAll()` e
   mostra um `SnackBar` de 5 segundos.

`kDebugMode` é constante de compilação, então o bloco inteiro some no
tree shaking em release — não fica botão escondido no app publicado.

O botão existe porque os tutoriais rodam uma vez e a sentinela em disco
sobrevive a `flutter run`, hot restart e reboot; só desinstalar apaga.
Isso é o comportamento certo para o usuário e um estorvo para quem
desenvolve.

Três widgets privados no fim: `_ResetTutoriais`, `_Secao` (título em
maiúsculas de baixo contraste entre dois `Divider`) e `_Paragrafo`.

---

## `screens/login_screen.dart` — 143 linhas — @Deprecated

Fora de uso. Não há backend de autenticação: os `validator` nunca foram
ligados a um `Form` e o botão "Entrar" apenas empurrava a `MapScreen`,
obrigando todo usuário a uma etapa vazia.

O arquivo fica no repositório com o layout pronto porque conta,
histórico por usuário e favoritos são features planejadas. O dartdoc
lista os três passos para reativar:

1. `home: const LoginScreen()` no `main.dart`.
2. Ligar os `validator`s a um `Form` + `GlobalKey<FormState>`.
3. Trocar o `Navigator.push` do "Entrar" por chamada de auth.

Detalhe de implementação preservado: o `SingleChildScrollView` existe
para o teclado não causar *bottom overflow*; dentro dele `Expanded` não
funciona, porque altura infinita não combina com "expandir para ocupar
espaço".
