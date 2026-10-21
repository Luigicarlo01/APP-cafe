import 'package:flutter/foundation.dart';

import 'mg_shape_service.dart';
import 'cultivar_info_service.dart';
import 'app_mode.dart';
import 'cache/region_cache_service.dart';
import 'cultivar_database.dart';

/// Roda a inicializacao pesada do app. Chamada pela SplashScreen.
///
/// Ordem: SQLite -> MgShape -> CultivarInfo -> AppMode -> RegionCache.prune.
Future<void> bootstrapApp() async {
  // Prepara a cópia SQLite antes da pesquisa/GPS. Nas próximas aberturas,
  // reutiliza o arquivo instalado sem descompactá-lo novamente.
  await CultivarDatabase.instance.ready();
  // Poligono de MG usado como mascara no primeiro frame do mapa.
  await MgShapeService().load();

  // Ficha dos cultivares lida direto pelo card da AnalysisScreen.
  await CultivarInfoService().load();

  // Estado inicial de conectividade + assinatura do stream.
  // Bloqueante para nao piscar de "online" para "offline" no primeiro build.
  await AppMode().init();

  // Prune do cache regional. Falha aqui nao deve travar o boot.
  try {
    await RegionCacheService().pruneExpired();
    await RegionCacheService().debugDump();
  } catch (e) {
    debugPrint('Falha ao inicializar cache: $e');
  }
}
