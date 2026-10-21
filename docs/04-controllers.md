# 04 — Controllers

Três `ChangeNotifier`. Diferente dos services, **não são singletons**:
cada tela cria a própria instância e dá `dispose()` nela.

---

## `controllers/map_controller_logic.dart` — 107 linhas

Estado do ponto selecionado na tela inicial, mais toda a validação
geográfica.

### Estado

```dart
final LocationService _locationService = LocationService();
final MapController mapController = MapController();   // do flutter_map
LatLng? selectedPoint;
```

O `MapController` do `flutter_map` vive aqui e não na tela, de forma que
quem move a câmera é a lógica, não o widget.

### O bounding box de MG

```dart
static final LatLngBounds mgBounds = LatLngBounds(
  LatLng(-22.92, -51.05),
  LatLng(-14.23, -39.85),
);
```

`static`, o que faz dele a fonte única desse retângulo no app inteiro.
É consumido em três lugares:

- Aqui, como primeiro filtro de `isValidPoint`.
- `MapWidget`, como `CameraConstraint.containCenter`.
- `BaseMapService._mgBoundingBox()`, que o converte em `BoundingBox`
  para calcular a grade de tiles do download.

### `isValidPoint(LatLng)` — validação em dois estágios

```dart
bool isValidPoint(LatLng point) {
  if (!mgBounds.contains(point)) return false;      // 1. filtro barato
  final shape = MgShapeService().shape;
  if (shape.isEmpty) return true;                   // 2. fail-open
  return _isPointInPolygon(point, shape);           // 3. ray casting
}
```

O retângulo é o filtro barato; o polígono real de MG (carregado de
`assets/mg.geojson` no boot) é o filtro preciso. Se o shape não
carregou, a função **aceita** o ponto em vez de recusar — falha aberta,
para não travar o app inteiro por causa de um asset.

`_isPointInPolygon` é ray casting clássico: traça um raio horizontal e
conta interseções com as arestas; ímpar = dentro. O `% n` no índice
fecha o polígono ligando o último ponto ao primeiro.

> A mesma técnica aparece em `GridCell.containsPoint`
> ([doc 05](05-services.md)), com a diferença de que lá os pontos são
> `Offset` com `dx = lng`.

### Os três caminhos de seleção

Todos convergem para o mesmo par de efeitos — `setPoint()` e
`mapController.move(point, 15)` — e todos recebem um callback
`onInvalid` que a tela usa para mostrar o `SnackBar`:

| Método | Origem | Particularidade |
|--------|--------|-----------------|
| `onMapTap(point, onInvalid:)` | toque no mapa | o mais direto |
| `onCitySelected(city, onInvalid:, onSuccess:)` | sugestão da busca | faz `double.tryParse` de `city['lat']`/`['lon']` e desiste com `debugPrint` se der `null` |
| `goToCurrentLocation(onInvalid:)` | FAB de GPS | `await` no `LocationService`; se voltar `null` (permissão negada ou GPS desligado), retorna em silêncio |

O zoom 15 é constante nos três — é o nível em que dá para reconhecer
talhões.

O `onSuccess` de `onCitySelected` hoje é uma lambda vazia na
`MapScreen`: o dropdown e o teclado já foram fechados no início do
`onTap`, antes do `await`.

---

## `controllers/search_controller.dart` — 152 linhas

Nome da classe: `CitySearchController`. **Não faz busca** — orquestra
debounce, estado e resolução.

### Fluxo completo

```
1. usuário digita "vic"
2. onSearchChanged("vic")     → inicia debounce de 400 ms
3. usuário digita "vico"      → cancela o timer anterior, cria outro
4. 400 ms sem digitar         → _search("vico") → POST Autocomplete
5. sugestões chegam           → notifyListeners → lista redesenha
6. usuário toca "Viçosa, MG"  → resolveSuggestion(item)
7. GET Place Details          → {name, lat, lon}
8. widget passa para MapControllerLogic.onCitySelected
```

### Debounce

```dart
void onSearchChanged(String query) {
  if (_debounce?.isActive ?? false) _debounce!.cancel();

  if (query.trim().isEmpty) {
    suggestions = [];
    _searchService.endSession();
    notifyListeners();
    return;
  }

  _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
}
```

400 ms é o compromisso declarado entre latência percebida (abaixo de
500 ms parece responsivo) e custo por chamada ao Google.

Campo esvaziado também encerra a *session token* do Places — o que
importa para a cobrança, ver [05](05-services.md#googleplacesservice).

### Guarda de 3 caracteres

```dart
Future<void> _search(String query) async {
  if (query.trim().length < 3) return;
  ...
}
```

O Google aceita 1+ caractere, mas os resultados iniciais são ruído. O
comentário marca o limite como ajustável.

Erros são capturados e logados com `debugPrint`; a UI simplesmente não
mostra sugestões, em vez de quebrar.

### `resolveSuggestion()`

O Autocomplete devolve apenas `place_id`; as coordenadas exigem uma
segunda chamada (Place Details), que é a **etapa paga** — daí a
preferência por chamá-la só quando o usuário seleciona.

```dart
_isResolving = true;
notifyListeners();
try {
  return await _searchService.getPlaceDetails(placeId);
} finally {
  _isResolving = false;
}
```

O `finally` garante desligar a flag mesmo em exceção.

**⚠ Detalhe**: o `_isResolving = false` do `finally` **não** é seguido
de `notifyListeners()`. Hoje isso não tem efeito visível porque nenhuma
tela consome `isResolving` — o campo está preparado para um spinner que
ainda não existe. Se alguém plugar a UI, precisará adicionar a
notificação. Registrado no doc 12.

### `dispose()`

```dart
@override
void dispose() {
  _debounce?.cancel();
  super.dispose();
}
```

Cancelar o `Timer` pendente evita que ele chame `notifyListeners()` num
controller já descartado, o que é crash em release.

### Trocar de provedor de busca

O arquivo foi escrito para isso. A linha do serviço é única:

```dart
final GooglePlacesService _searchService = GooglePlacesService();
// final LocationSearchService _searchService = LocationSearchService();  // Nominatim
```

O contrato externo (`searchCity` devolvendo `[{name, place_id}]`) é
preservado pelas duas implementações.

---

## `controllers/analysis_controller.dart` — 153 linhas

Estado da tela de análise: qual célula está selecionada e qual cultivar
dentro dela.

### Estado

```dart
String? selectedGenotype;
String? errorMessage;
GridCell? _selectedCell;
bool isLoading = false;
```

Note que ele **não** guarda as células — elas vivem no
`AnalysisService`, que é singleton. O controller guarda apenas a
seleção.

### `load({required LatLng position})`

```dart
isLoading = true; errorMessage = null; notifyListeners();
try {
  await AnalysisService().load(lat: ..., lng: ...);
} on NoDataException catch (e) {
  errorMessage = e.message;              // mensagem amigável do service
} catch (e) {
  errorMessage = 'Erro ao carregar dados. Verifique sua conexão.';
}
isLoading = false;
_selectInitialCell(position);
notifyListeners();
```

Dois `catch` separados: `NoDataException` carrega uma mensagem pensada
para o usuário e é repassada como está; qualquer outra vira texto
genérico.

### `_selectInitialCell()` — por que existe

A tela **deve** abrir já analisando o ponto que o usuário confirmou; ele
não deveria precisar tocar em nada.

```dart
final geo = Offset(position.longitude, position.latitude);
final cell = AnalysisService().resolveCell(geo);
if (cell == null) return;   // grid vazio — errorMessage já explica

_selectedCell = cell;
selectedGenotype = cell.winner ??
    (cell.alternatives.isNotEmpty ? cell.alternatives.first : null);
```

Antes isto era `cellContaining(nearestCellCentroid(ponto))`: dois passos
que podiam falhar, e quando falhavam a tela abria vazia pedindo
"selecione um cultivar", ignorando o ponto recém-confirmado.
`resolveCell` tem fallback garantido — ver
[05 — resolveCell](05-services.md#resolvecell--o-ponto-central).

O `??` com `alternatives.first` cobre células sem vencedor.

### `updateSelectedGenotypeFromPosition(Offset geoPoint)`

Chamado no toque do mapa da análise. Usa o **mesmo** `resolveCell` da
abertura, de propósito: assim o realce no mapa e a lista de cultivares
nunca discordam sobre qual célula está selecionada.

### `selectedRanking` — a única lista da tela

```dart
List<String> get selectedRanking {
  final cell = _selectedCell;
  if (cell == null) return [];
  return [
    if (cell.winner != null) cell.winner!,
    ...cell.alternatives,
  ];
}
```

O tamanho é definido pelo backend: top-3 vira 3 itens, top-5 vira 5,
sem tocar numa linha aqui.

Célula sem `winner` entra só com as alternativas. Antes o lugar do
vencedor virava um chip escrito "N/A" — um cultivar fantasma que o
usuário podia tocar e que não existe.

### `winners` — getter sobrevivente

```dart
List<String> get winners => AnalysisService().winners;
```

Alimentava a antiga seção "Legenda" (vencedores do município inteiro).
Hoje nenhuma tela consome; o getter fica porque o dado continua vindo do
backend e é útil para debug.

### Favoritos — desativado

Um `Set<String> _favoritedKeys` em memória, com
`isSelectedFavorited` / `toggleFavoriteSelected`, ambos `@Deprecated`.

A chave é `"centroid.dx_centroid.dy_genotype"` — amarrada à célula, e
não só ao nome do genótipo, porque o mesmo genótipo aparece em várias
células; o que o usuário favorita é "essa localização com esse
cultivar".

Desligado porque o `Set` vive só em memória e some quando o app fecha.
Prometer "favoritar" e perder tudo no próximo boot é pior que não
oferecer. O dartdoc lista os três passos para reativar — ver
[doc 13](13-codigo-desativado.md).
