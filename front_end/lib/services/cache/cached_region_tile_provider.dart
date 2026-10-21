import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'cache_paths.dart';

/// Nossa impl de `TileProvider`. O `flutter_map` chama `getImage` pra
/// cada tile visível; nós devolvemos um `ImageProvider` que sabe achar
/// o tile via cache-first.
///
/// Nome ainda tem "Region" por herança histórica (antes ele conhecia
/// `regionId` pra ler pastas por região). Hoje é agnóstico — só usa
/// o mapa base global.
class CachedRegionTileProvider extends TileProvider {
  /// Cliente HTTP mantido vivo entre chamadas. Reuso de conexão é
  /// importante — abrir/fechar TCP a cada tile seria lento.
  final http.Client _client;

  /// Se ninguém passar um cliente, criamos um interno. Alternativa é
  /// injetar (útil pra testes).
  ///
  /// `super.headers`: repassa pro construtor da super classe. O
  /// `TileProvider` guarda `headers` (ex: User-Agent) e o flutter_map
  /// espera essa API.
  CachedRegionTileProvider({
    http.Client? client,
    super.headers,
  }) : _client = client ?? http.Client();

  /// Chamado pelo flutter_map pra cada tile. Retornamos um
  /// `ImageProvider` custom (`_CachedTileImage` abaixo).
  ///
  /// `coordinates.z/x/y`: o tile pedido.
  /// `options.urlTemplate`: a URL configurada no `TileLayer` do widget
  /// (ex: `.../{z}/{x}/{y}.png`).
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      urlTemplate: options.urlTemplate ?? '',
      subdomains: options.subdomains,
      headers: headers,
      client: _client,
    );
  }

  /// Fecha o `http.Client` quando o provider é descartado. Sem isso,
  /// vazamos sockets TCP.
  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// `ImageProvider` custom que sabe: (1) ler PNG do disco, ou (2)
/// baixar da rede. Herda de `ImageProvider<_CachedTileImage>` — o
/// tipo genérico é a "chave" usada pra cache do próprio Flutter (não
/// confundir com nosso cache de arquivos).
///
/// `const` constructor porque somos imutáveis (todos os campos `final`).
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  final int z;
  final int x;
  final int y;
  final String urlTemplate;
  final List<String> subdomains;
  final Map<String, String> headers;
  final http.Client client;

  const _CachedTileImage({
    required this.z,
    required this.x,
    required this.y,
    required this.urlTemplate,
    required this.subdomains,
    required this.headers,
    required this.client,
  });

  /// A "chave" que o Flutter usa pra deduplicar carregamentos. Se dois
  /// widgets pedirem o mesmo tile, ele reusa o resultado.
  ///
  /// `SynchronousFuture` = "já resolvido, retorna agora sem gap de
  /// frame". A chave é o próprio objeto (que tem `==` e `hashCode`
  /// customizados lá embaixo).
  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  /// Onde a mágica acontece. O Flutter chama isso quando precisa do
  /// bitmap decodificado. Retornamos um `StreamCompleter` que, por
  /// baixo, chama `_loadCodec` (que chama `_loadBytes`, que consulta
  /// disco/rede).
  @override
  ImageStreamCompleter loadImage(
      _CachedTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(decode),
      scale: 1.0,
      // debugLabel aparece nos devtools do Flutter, útil pra profiling.
      debugLabel: 'CachedTile z=$z x=$x y=$y',
    );
  }

  /// Adapta bytes brutos (PNG) em `ui.Codec` que o Flutter decodifica.
  ///
  /// `ui.ImmutableBuffer.fromUint8List` cria um buffer read-only sem
  /// cópia — barato mesmo pra tiles grandes.
  ///
  /// Se `_loadBytes` retornou null (não achou em lugar nenhum), a
  /// exceção sobe pro flutter_map, que decide: geralmente estica o
  /// tile do zoom anterior.
  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final bytes = await _loadBytes();
    if (bytes == null) {
      throw Exception('Falha ao obter tile z=$z x=$x y=$y');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  /// A cascata de fontes: disco → rede → null.
  Future<Uint8List?> _loadBytes() async {
    // Só zoom 6-10 dentro do bbox de MG estão aqui.
    final baseFile = await CachePaths.baseMapTileFile(z, x, y);
    if (await baseFile.exists()) {
      try {
        return await baseFile.readAsBytes();
      } catch (e) {
        // Arquivo existe mas leitura falhou (disco cheio, permissão etc).
        // Trata como miss e cai pra rede.
        debugPrint('[tiles] erro lendo base_map z=$z x=$x y=$y: $e');
      }
    }

    final url = _buildUrl();
    try {
      final resp = await client.get(Uri.parse(url), headers: headers);
      if (resp.statusCode != 200) {
        debugPrint('[tiles] HTTP ${resp.statusCode} z=$z x=$x y=$y');
        return null;
      }
      return resp.bodyBytes;
    } catch (e) {
      // Offline, DNS failure, timeout etc.
      debugPrint('[tiles] rede falhou z=$z x=$x y=$y: $e');
      return null;
    }
  }

  /// Monta a URL do tile substituindo `{z}`, `{x}`, `{y}` (e `{s}` se
  /// o template usar subdomínio).
  ///
  /// CartoDB tem 3 subdomínios (`a`, `b`, `c`) pra balanço de carga.
  /// A fórmula `(x + y) % 3` distribui de forma determinística — o
  /// mesmo tile sempre vai pro mesmo subdomínio, ajudando o cache HTTP.
  String _buildUrl() {
    var url = urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
    if (subdomains.isNotEmpty && url.contains('{s}')) {
      final index = (x + y) % subdomains.length;
      url = url.replaceAll('{s}', subdomains[index]);
    }
    return url;
  }

  // Dois `_CachedTileImage` são "iguais" se representam o mesmo tile

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage &&
      other.z == z &&
      other.x == x &&
      other.y == y &&
      other.urlTemplate == urlTemplate;

  @override
  int get hashCode => Object.hash(z, x, y, urlTemplate);
}
