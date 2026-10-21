# 13 — Código desativado

O projeto não apaga código morto: marca com `@Deprecated`, escreve no
dartdoc **por que** foi desligado e **como reativar**, e mantém o
arquivo.

Esta é a lista completa, com o caminho de volta de cada item.

---

## Telas e navegação

### `screens/login_screen.dart` — @Deprecated

**Por quê**: não há backend de autenticação. Os `validator` nunca foram
ligados a um `Form`, e o botão "Entrar" apenas empurrava a `MapScreen` —
uma etapa vazia obrigatória antes de usar o app.

**Para reativar**:
1. `home: const LoginScreen()` no `main.dart`.
2. Ligar os `validator`s a um `Form` + `GlobalKey<FormState>`.
3. Trocar o `Navigator.push` do "Entrar" por chamada de autenticação.

Há dois `TODO` no arquivo: `ForgotPasswordScreen` e tela de cadastro.

### `widgets/app_drawer.dart` — @Deprecated

**Por quê**: os quatro itens do menu ("Conta", "Meu Formulário", "Locais
Favoritados", "Histórico de acessos") **navegavam todos para a mesma
`HistoryScreen`** — confirmado na leitura: os quatro `onTap` são
idênticos, `Navigator.pop` seguido de `push(HistoryScreen)`. O menu
prometia quatro destinos e entregava um. E as features por trás dependem
de login.

Tem ainda um rodapé com a versão via `PackageInfo.fromPlatform()`, no
mesmo padrão que a tela "Sobre" usa hoje.

Com a remoção, o `MapScreen` deixou de declarar `drawer:` e o hambúrguer
sumiu da AppBar.

**Efeito colateral**: a `HistoryScreen` ficou sem porta de entrada, e é
por isso que ela hoje é acessada pela pílula do modo offline e pelo
diálogo de erro de conexão.

**Para reativar**: `drawer: const AppDrawer()` no `Scaffold` da
`MapScreen` e apontar cada `ListTile` para a sua tela real.

Nota de implementação preservada no arquivo: usa `Container` em vez de
`DrawerHeader` porque o esquema de const-propagation do `DrawerHeader`
às vezes conflita com children não-const e faz o analyzer reportar erros
confusos.

---

## Mapa monocromático — o que caiu junto

Três itens saíram da mesma decisão: pintar todas as células do mesmo
verde, porque com ~12 genótipos as cores ficavam indistinguíveis no
celular sob sol.

### `utils/genotype_color_manager.dart` — @Deprecated

Dicionário genótipo → cor lido de `assets/colors_2026.json`. O
`bootstrapApp` deixou de chamar `load()`.

**Para reativar**: voltar a chamar `GenotypeColorManager().load()` no
boot. O JSON continua sendo gerado pelo `color_generator.R`.

### `AnalysisService.buildPoints(Map<String, Color>)` — @Deprecated

Convertia `cells` em `List<GenotypePoint>` para o `PointsPlot` desenhar
markers coloridos. Sem chamadores.

### `widgets/points_plot.dart` — @Deprecated

Plot de pontos em canvas puro — o primeiro desenho da análise, anterior
ao `GenotypePlot` sobre `flutter_map`. Desenha os pontos com
`CustomPaint` e um marker arrastável de três círculos concêntricos
(sombra, anel branco, miolo verde).

Mantido como referência do cálculo de projeção geo → pixel:

```dart
Offset _toPixel(Offset geo) {
  final x = (geo.dx - _minX) * _scaleFactor + _offsetX;
  final y = _canvasHeight - ((geo.dy - _minY) * _scaleFactor + _offsetY);
  return Offset(x, y);
}
```

É projeção **equirretangular** (linear nos dois eixos, com um único
`_scaleFactor` que preserva proporção), não Web Mercator — aceitável na
escala de um município, e o que tornaria o widget útil para um mini-mapa
sem tiles.

Dois detalhes a saber antes de reaproveitá-lo:

- **É o único código que ainda chama `AnalysisService.nearestCellCentroid`**
  (linha 103), e também usa `cellContaining` para rejeitar marcadores
  fora do grid.
- `_PointsPainter.shouldRepaint` compara `List` por identidade
  (`oldDelegate.points != points`), o que é sempre verdadeiro para uma
  lista recriada no `build` — ou seja, repinta a cada frame.

### `models/genotype_point.dart` — legado, sem anotação

Não está marcado `@Deprecated`, mas seu único produtor
(`buildPoints`) e seu único consumidor (`PointsPlot`) estão.

---

## Busca de localização

### `services/location_search_service.dart` — @Deprecated

Busca via **Nominatim** (OpenStreetMap), substituída pelo Google Places.

O `CitySearchController` foi escrito para a troca ser uma linha:

```dart
final GooglePlacesService _searchService = GooglePlacesService();
// final LocationSearchService _searchService = LocationSearchService();
```

O contrato externo (`searchCity` devolvendo `[{name, place_id}]`) é
preservado pelas duas implementações — embora o Nominatim devolva
coordenadas direto, sem precisar do segundo request.

Detalhe: a implementação Nominatim envia um `User-Agent` com e-mail de
contato, exigido pela política de uso do serviço.

### `services/google_geocoding_service.dart` — @Deprecated

Reverse geocoding: coordenada → endereço legível. Deixou de ser
consumido — a tela mostra o nome do município vindo do backend, que já é
o dado certo.

### `widgets/searchbar_widget.dart` — órfão, sem anotação

Componente reutilizável de barra de busca. **Não é montado por nenhuma
tela**: a `MapScreen` constrói a própria barra inline, porque precisa de
`TextEditingController` externo, botão de limpar, `onTapOutside`, altura
máxima do dropdown e a `GlobalKey` no card.

---

## Cache

### `services/cache/tile_downloader.dart` — @Deprecated

Baixava tiles adaptativos **por região**: escolhia, via
`TileMath.pickMaxZoom`, o maior zoom que coubesse numa quota de 30 MB por
região, e gravava em `region_tiles/<id>/z/x/y.png`.

**Por quê**: o `flutter_map` escala o tile de zoom 10 quando o usuário
passa disso, então o mapa base pré-baixado basta. Um downloader por
região seria redundância cara.

**Rastros que ficaram**:

| Rastro | Onde |
|--------|------|
| Colunas `tilesBytes` e `tilesMaxZoom` (sempre 0/null) | tabela `CachedRegions` |
| `RegionDatabase.updateTilesInfo()` | sem chamador |
| `RegionCacheService.enforceQuota()` | sem chamador |
| `CachePaths.regionTilesDir()` / `tileFile()` | usados só por `_deleteRow`, para apagar pastas órfãs |
| `TileMath.pickMaxZoom()` | sem chamador |
| `totalBytes` somando `fileSizeBytes + tilesBytes` | a segunda parcela é sempre 0 |

As colunas permanecem para evitar uma nova migração de schema.

### `utils/geojson_cache_manager.dart` — **órfão sem anotação**

Uma implementação anterior e **completa** de cache de GeoJSON, com API
mais rica que a atual em alguns pontos:

| Método | O que faz |
|--------|-----------|
| `init()` | carrega o índice e roda a limpeza |
| `read` / `write` | lê e grava por nome de município |
| `pin` / `unpin` | marca uma entrada como **nunca expirável** |
| `delete` / `clearAll({includePinned})` | remoção manual |
| `runCleanup()` | remove expirados, devolve a contagem |
| `entries()` | lista ordenada por último acesso — "útil para exibir na UI" |
| `totalSizeBytes()` | ocupação total |

O índice vive em memória (`Map<String, CacheEntry>`) e é serializado num
`_index.json` ao lado dos arquivos. TTL de 7 dias desde `lastAccessed`,
com `pinned` imune.

**Por que foi substituída** — o `RegionCacheService` + Drift ganha em
quatro pontos:

1. **Consulta espacial por bbox.** Esta é chaveada por nome de
   município, então só acha o que você já sabe nomear.
2. **Quota em bytes com eviction por uso.** Aqui só existe TTL.
3. **Contagem de acessos**, que ordena a eviction.
4. **O diretório.** Esta usa `getApplicationCacheDirectory()` — a pasta
   que o sistema operacional pode limpar quando quiser. É exatamente o
   erro contra o qual o `cache_paths.dart` adverte no cabeçalho, e que
   levou o cache novo a usar `getApplicationDocumentsDirectory()`. Cache
   apagado pelo SO significa modo offline quebrado em campo.

**É o único caso de código morto sem qualquer sinalização** — não está
`@Deprecated` e não é importado por nenhum arquivo.

> Se os favoritos voltarem (ver adiante), o conceito de `pinned` daqui é
> a modelagem mais próxima do que se quer: região que o usuário marca e
> que a eviction nunca toca.

---

## Favoritos

### `AnalysisController.isSelectedFavorited` / `toggleFavoriteSelected` — @Deprecated

O botão de favoritar vivia no canto superior direito do mapa da análise
(nos dois modos) e tinha um passo próprio no tutorial. Ambos foram
removidos.

**Por quê**: o `Set<String> _favoritedKeys` vive só em memória e some
quando o app fecha. Prometer "favoritar" e perder tudo no próximo boot é
pior que não oferecer.

**Para reativar** (os três passos estão no código):
1. Criar a tabela Drift — chave = célula + cultivar.
2. Trocar o `Set` por queries, **mantendo a interface pública** — assim
   a UI antiga volta sem alteração.
3. Recolocar o botão na `AnalysisScreen` e o passo no tutorial.

A chave é `"centroid.dx_centroid.dy_genotype"`, amarrada à célula e não
só ao nome: o mesmo genótipo aparece em várias células, e o que o usuário
favorita é "essa localização com esse cultivar".

---

## Seleção de cultura

### `widgets/crop_selection_sheet.dart` — @deprecated

Bottom sheet com um `GridView` de duas colunas e três culturas
(Milho 🌽, Café ☕, Feijão 🫘), cada uma num cartão selecionável, e um
botão "Continuar" que só habilita depois da escolha e empurra a
`AnalysisScreen` passando o `selectedCrop`. O app trata apenas café.

Dois detalhes:

- Usa o `@deprecated` minúsculo (a constante antiga do Dart), sem
  mensagem — é o único assim no projeto.
- Pinta com `Color.fromARGB(255, 2, 141, 6)` = **`#028D06`**, que **não
  é** o verde da marca (`#02890A`). Um segundo verde, quase igual,
  nascido antes de `AppColors` existir.

**Rastro**: o parâmetro `selectedCrop` do `AnalysisScreen`, que continua
obrigatório e não é lido por nada. A `MapScreen` passa `''` e a
`HistoryScreen` passa `'Café'`.

---

## Getters e métodos sem consumidor

Não estão deprecados; existem e funcionam, mas ninguém chama.

| Símbolo | Arquivo | Observação |
|---------|---------|------------|
| `AnalysisController.winners` | `analysis_controller.dart` | alimentava a "Legenda"; mantido para debug |
| `AnalysisService.nearestCellCentroid` | `analysis_service.dart` | **tem um chamador**: o `PointsPlot` deprecado (linha 103). Sem consumidor ativo |
| `RegionCacheService.clear()` | `region_cache_service.dart` | seria o "limpar cache" de uma tela de configurações |
| `RegionCacheService.totalBytes()` | idem | delegator |
| `AppMode.forceCheck()` | `app_mode.dart` | releitura manual após voltar do background |
| `GooglePlacesService.forwardGeocode()` | `google_places_service.dart` | fallback endereço → coordenada |
| `GooglePlacesService.startNewSession()` | idem | a criação lazy do token cobre o caso |
| `CitySearchController.isResolving` | `search_controller.dart` | preparado para um spinner que não existe |
| `BoundingBox.toJson()` | `bounding_box.dart` | debug e testes |
| `OnboardingService.reset(flow)` | `onboarding_service.dart` | só `resetAll` é chamado |

---

## Assets sem consumidor

| Arquivo | Situação |
|---------|----------|
| `assets/colors_2026.json` | lido apenas pelo `GenotypeColorManager` deprecado |
| `assets/esmeraldas.geojson` | resíduo de teste inicial |
| `assets/typica_logo.svg` | versão com borda; o app usa a sem borda |
| `assets/logo_ufv.png` | extração do PNG embutido na primeira versão do "SVG" da UFV. O `partner_logos.dart` anota: "pode ser apagado" |

---

## Resumo

| Categoria | Quantidade |
|-----------|-----------|
| Arquivos inteiros `@Deprecated` | 8 |
| Símbolos `@Deprecated` dentro de arquivos ativos | 4 |
| Arquivos órfãos **sem** anotação | 3 (`geojson_cache_manager`, `searchbar_widget`, `genotype_point`) |
| Métodos públicos sem chamador ativo | 10 |
| Assets sem consumidor | 4 |

A prática de deprecar em vez de apagar é deliberada e está bem
documentada no próprio código — cada arquivo explica a decisão e o
caminho de volta. O único ponto a corrigir são os três órfãos sem
anotação, que hoje não avisam nada a quem os encontra.
