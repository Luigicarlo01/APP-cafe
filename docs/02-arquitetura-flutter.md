# 02 — Arquitetura do Flutter

Este documento explica **como** o código do app está organizado e
**quais padrões** ele usa. Os documentos 03 a 08 descrevem cada arquivo.

---

## Estrutura de pastas

```
front_end/lib/
├── main.dart                      entrypoint + tema global
│
├── models/                        estruturas de dados puras
│   ├── bounding_box.dart          retângulo geográfico (chave do cache)
│   └── genotype_point.dart        legado (ver doc 13)
│
├── screens/                       telas completas (rotas do Navigator)
│   ├── splash_screen.dart         abertura + boot
│   ├── map_screen.dart            tela inicial  ⭐ 961 linhas
│   ├── analysis_screen.dart       resultado da análise  ⭐ 478 linhas
│   ├── history_screen.dart        regiões salvas no aparelho
│   ├── about_screen.dart          sobre / créditos / versão
│   └── login_screen.dart          @Deprecated
│
├── controllers/                   estado de tela (ChangeNotifier)
│   ├── map_controller_logic.dart  ponto selecionado + validação em MG
│   ├── search_controller.dart     debounce e sugestões da busca
│   └── analysis_controller.dart   célula e cultivar selecionados
│
├── services/                      regra de negócio e I/O (singletons)
│   ├── analysis_service.dart      ⭐ 684 linhas — o centro do app
│   ├── api_config.dart            ⚠ URLs e chave hardcoded
│   ├── app_bootstrap.dart         a inicialização pesada
│   ├── app_mode.dart              online / offline
│   ├── cultivar_info_service.dart ficha técnica (asset)
│   ├── crop_cycle_service.dart    ciclo de maturação
│   ├── mg_shape_service.dart      polígono de MG
│   ├── location_service.dart      GPS
│   ├── onboarding_service.dart    "já viu o tutorial?"
│   ├── google_places_service.dart busca de cidades
│   ├── google_geocoding_service.dart   @Deprecated
│   ├── location_search_service.dart    @Deprecated (Nominatim)
│   └── cache/                     subsistema de cache — ver doc 06
│       ├── region_database.dart         schema Drift
│       ├── region_database.g.dart       GERADO — não editar
│       ├── region_cache_service.dart    ⭐ 451 linhas — quota, TTL, eviction
│       ├── cache_paths.dart             onde fica cada coisa em disco
│       ├── base_map_service.dart        download do mapa base de MG
│       ├── cached_region_tile_provider.dart  TileProvider cache-first
│       ├── tile_math.dart               matemática slippy-map
│       └── tile_downloader.dart         @Deprecated
│
├── widgets/                       componentes de UI
│   ├── map_widget.dart            mapa da tela inicial
│   ├── genotype_plot.dart         mapa da análise (células + realce)
│   ├── genotype_detail_card.dart  ficha do cultivar
│   ├── genotypes_list.dart        chips horizontais de cultivar
│   ├── cycle_selection_picker.dart pílula do ciclo de maturação
│   ├── opacity_slider.dart        slider com trilho em gradiente
│   ├── onboarding_overlay.dart    ⭐ 875 linhas — motor do tutorial
│   ├── partner_logos.dart         marcas EPAMIG + UFV
│   ├── searchbar_widget.dart      não montado por nenhuma tela
│   ├── app_drawer.dart            @Deprecated
│   ├── crop_selection_sheet.dart  @Deprecated
│   └── points_plot.dart           @Deprecated
│
└── utils/
    ├── app_colors.dart            paleta única
    ├── genotype_color_manager.dart @Deprecated
    └── geojson_cache_manager.dart  órfão (ver doc 13)
```

---

## As quatro camadas

```
          ┌──────────────────────────────────────────┐
          │  screens/  +  widgets/                   │  desenha
          │  StatefulWidget, setState                │
          └────────────┬─────────────────────────────┘
                       │ lê estado, chama métodos
          ┌────────────▼─────────────────────────────┐
          │  controllers/                            │  estado de tela
          │  ChangeNotifier, instância por tela      │
          └────────────┬─────────────────────────────┘
                       │
          ┌────────────▼─────────────────────────────┐
          │  services/                               │  regra + I/O
          │  singletons, alguns ChangeNotifier       │
          └────────────┬─────────────────────────────┘
                       │
          ┌────────────▼─────────────────────────────┐
          │  models/   Drift   disco   rede          │
          └──────────────────────────────────────────┘
```

A regra que o código segue: **UI não fala com rede nem com disco**.
Sempre passa por um service. A exceção é a `HistoryScreen`, que consulta
o Drift diretamente (`RegionDatabase.instance`) — anotado como dívida no
doc 12.

---

## Padrões usados

### Singleton via factory constructor

Quase todo service segue esta forma:

```dart
class AppMode extends ChangeNotifier {
  static final AppMode _instance = AppMode._();
  factory AppMode() => _instance;
  AppMode._();
}
```

O efeito é que `AppMode()` em qualquer lugar do código devolve a **mesma
instância**. Não há injeção de dependência, nem Provider, nem GetIt.

**Consequência prática**: o estado da análise atual é global. Se o
usuário voltar ao mapa e escolher outro município, o `AnalysisService`
zera tudo (`_reset()`) antes de carregar o novo — não há duas análises
vivas ao mesmo tempo.

**Consequência para testes**: services não são mockáveis sem refatorar.
É o principal custo desta escolha, registrado no doc 12.

### ChangeNotifier + setState

Não há gerenciador de estado. O padrão é:

```dart
// no initState da tela
_modeListener = () => setState(() {});
_mode.addListener(_modeListener);

// no dispose
_mode.removeListener(_modeListener);
```

Dois detalhes que o código trata com cuidado e que valem entender:

1. **Um listener por fonte, guardado em campo.** A `MapScreen` escuta
   quatro notifiers e declara quatro `VoidCallback` distintos, mesmo
   sendo todos `() => setState(() {})`. Motivo: `removeListener` compara
   por identidade. Registrar a mesma lambda quatro vezes removeria só
   uma no `dispose`, vazando três.

2. **Singletons globais não sofrem `dispose` na tela.** A `MapScreen`
   dá `dispose()` em `_logic` e `_search` (que são dela), mas apenas
   remove os listeners de `_baseMap` e `_mode` (que são globais e vivem
   o app inteiro).

### Serviços que notificam vs. serviços que não notificam

| Notificam (`ChangeNotifier`) | Não notificam |
|------------------------------|---------------|
| `AppMode` | `AnalysisService` |
| `BaseMapService` | `CultivarInfoService` |
| `CropCycleService` | `MgShapeService` |
| | `RegionCacheService` |
| | `OnboardingService` |

`AnalysisService` é o caso interessante: ele **não** é `ChangeNotifier`
de propósito. A tela dispara `load()` no `initState` e usa o resultado
quando o `Future` volta; não há atualização contínua a reagir. Quem
notifica ali é o `AnalysisController`, que envolve a chamada.

### Trabalho pesado em isolate

O parse do GeoJSON roda em `compute(_parseCellsIsolate, jsonString)`.
Isso exige que a função seja **top-level** (fora de qualquer classe),
porque `compute` serializa a função para enviar ao isolate e métodos de
instância carregam o `this`, que não é serializável.

O mesmo princípio aparece no Drift: `NativeDatabase.createInBackground`
roda o SQLite em isolate separado.

---

## Convenções que não são óbvias

### `Offset` como coordenada geográfica: `dx = longitude`, `dy = latitude`

`GridCell.points` é uma `List<Offset>`, não `List<LatLng>`. A convenção
é `dx = lng`, `dy = lat` — que é a ordem do GeoJSON, e a inversa da do
`LatLng` do `latlong2`.

Onde isso importa: **toda conversão para desenhar no mapa inverte**.

```dart
// analysis_service.dart, polygonsFor()
points: cell.points.map((o) => LatLng(o.dy, o.dx)).toList()
//                                     ^lat  ^lng
```

E toda entrada vinda do mapa converte no sentido oposto:

```dart
// analysis_controller.dart
final geo = Offset(position.longitude, position.latitude);
```

A escolha do `Offset` (uma classe pensada para pixels) veio de operações
vetoriais baratas — soma de centroides, distância euclidiana. O
comentário no topo do `analysis_service.dart` registra que a convenção é
confusa e pede atenção.

### Áreas em graus², não em km²

`BoundingBox.area` e a ordenação de `findContaining` usam graus²
(`(maxLat-minLat) * (maxLon-minLon)`). Isso está **correto de
propósito**: a métrica só serve como desempate entre bounding boxes que
contêm o mesmo ponto, e a ordem relativa é a mesma em graus² ou km².

O mesmo vale para `nearestCell`, que compara distância euclidiana ao
quadrado em graus — sem `sqrt`, porque a raiz é cara e não muda a ordem.

### Sentinelas de arquivo em vez de `shared_preferences`

Três estados booleanos persistentes usam a existência (ou o conteúdo) de
um arquivo em `AppDocs` em vez de preferências:

| Estado | Arquivo |
|--------|---------|
| Mapa base baixado por inteiro | `base_map/.complete` |
| Tutorial da tela inicial visto | `.onboarding_done` |
| Tutorial da análise visto | `.onboarding_analysis` |

Motivo declarado no código: evitar uma dependência nova para guardar
dois bits, já que `path_provider` está no projeto. O arquivo do
onboarding guarda a **versão** do roteiro vista, não apenas "visto" —
ver [07 — onboarding](07-widgets.md).

### `AppDocs`, nunca `Temporary`

Todo cache do app vive em `getApplicationDocumentsDirectory()`. A pasta
de cache do sistema (`getTemporaryDirectory`) pode ser limpa pelo SO a
qualquer momento — o que quebraria o modo offline em campo, justamente
onde ele importa. Documentado em `cache_paths.dart`.

### Deprecação com arquivo preservado

O projeto não apaga código morto: marca com `@Deprecated`, escreve no
dartdoc **por que** foi desligado e **como reativar**, e mantém o
arquivo. Doze arquivos/símbolos estão nesse estado. Ver
[doc 13](13-codigo-desativado.md).

---

## Ciclo de vida completo de uma sessão

```
main()
 └─ WidgetsFlutterBinding.ensureInitialized()
 └─ runApp(MyApp)                       ← imediato, sem await
     └─ MaterialApp(theme, home: SplashScreen)
         └─ SplashScreen.initState → _abrir()
             └─ Future.wait([
                  bootstrapApp(),       ← carga pesada
                  delay(1400ms)         ← tempo mínimo em tela
                ])
             └─ pushReplacement(MapScreen)  ← fade de 350 ms

bootstrapApp()  (services/app_bootstrap.dart)
 1. MgShapeService().load()        lê assets/mg.geojson
 2. CultivarInfoService().load()   lê assets/cultivares.json
 3. AppMode().init()               lê conectividade + assina stream
 4. RegionCacheService().pruneExpired() + debugDump()   em try/catch

MapScreen
 ├─ escuta 4 notifiers
 ├─ BaseMapService().refreshStatus()   varre o disco (async)
 └─ postFrame → _maybeShowOnboarding()

toque no mapa → MapControllerLogic.onMapTap
 ├─ valida: dentro do bbox de MG? dentro do polígono (ray casting)?
 └─ move a câmera para zoom 15

"Confirmar localização" → MapScreen._confirmLocation
 ├─ dialog de loading não-dismissível
 ├─ AnalysisService().load(lat, lng)     ← preflight
 ├─ sucesso → push(AnalysisScreen)
 └─ falha  → dialog de erro, com atalho para o histórico

AnalysisScreen.initState
 └─ AnalysisController.load()
     └─ AnalysisService().load()   ← cache hit, sem rede
     └─ _selectInitialCell()       ← resolveCell do ponto confirmado
```

O **preflight** (carregar a análise *antes* de navegar) é uma decisão
deliberada: sem ele, a `AnalysisScreen` abriria e só então mostraria
erro de conexão, deixando o usuário numa tela vazia. Como o
`AnalysisService` é singleton e cache-first, a segunda chamada — feita
pelo controller já dentro da tela — bate no cache e não custa rede.

---

## O que o app **não** tem

Registrado aqui porque é a primeira pergunta de quem chega no código:

- **Sem autenticação.** A `LoginScreen` existe mas está deprecada; não
  há backend de auth.
- **Sem rotas nomeadas.** Navegação é `Navigator.push` com
  `MaterialPageRoute` construído na hora.
- **Sem gerenciador de estado.** `ChangeNotifier` + `setState`.
- **Sem injeção de dependência.** Singletons acessados diretamente.
- **Sem testes.** `test/widget_test.dart` é o template do `flutter
  create` e falharia se executado (procura um contador que não existe).
- **Sem internacionalização.** Todas as strings em português, inline.
- **Sem tema escuro.** Só o `ThemeData` claro do `main.dart`.
