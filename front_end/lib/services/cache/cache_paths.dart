import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Utilitário estático (todos os métodos são `static`). Não precisa
/// instanciar — chame direto: `CachePaths.regionFile(3)`.
class CachePaths {
  // Constantes privadas — se mudarem, o layout de disco muda inteiro.

  /// Onde os `.geojson` cacheados por região vivem
  /// (`<AppDocs>/region_cache/`).
  static const String _regionDirName = 'region_cache';

  /// **Legado**: tiles por região viviam aqui
  /// (`<AppDocs>/region_tiles/<id>/z/x/y.png`).
  /// Hoje não é mais populado (TileDownloader foi deprecated), mas
  /// pastas antigas de testes anteriores podem existir. Manter o nome
  /// aqui pra o dia que decidirmos escrever um "prune" que apague tudo.
  static const String _tilesDirName = 'region_tiles';

  /// Mapa base pré-carregado — `<AppDocs>/base_map/z/x/y.png`.
  static const String _baseMapDirName = 'base_map';

  /// Arquivo SQLite do Drift — `<AppDocs>/region_cache.db`.
  static const String _dbFileName = 'region_cache.db';

  /// Prefixo das sentinelas de onboarding — `<AppDocs>/.onboarding_*`.
  /// Existe = usuário já viu (ou pulou) aquele tutorial.
  static const String _onboardingPrefix = '.onboarding_';


  /// Retorna (e cria se necessário) o diretório onde os `.geojson`
  /// cacheados ficam.
  ///
  /// `recursive: true` no `create` significa que se o pai também não
  /// existir, ele é criado. Não deveria acontecer (AppDocs sempre existe),
  /// mas é defensivo.
  static Future<Directory> regionCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _regionDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Caminho absoluto do arquivo `.geojson` de uma linha do cache.
  ///
  /// Convenção: o nome é o `id` autoincremento do banco. Isso garante
  /// unicidade sem precisar sanitizar strings de municípios.
  static Future<File> regionFile(int id) async {
    final dir = await regionCacheDir();
    return File(p.join(dir.path, '$id.geojson'));
  }


  /// Diretório dos tiles antigamente baixados por região. Preservado só
  /// pra que `RegionCacheService._deleteRow` consiga apagar pastas
  /// órfãs de testes anteriores.
  static Future<Directory> regionTilesDir(int id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _tilesDirName, '$id'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Path de um tile específico dentro da pasta da região (legado).
  static Future<File> tileFile(int regionId, int z, int x, int y) async {
    final dir = await regionTilesDir(regionId);
    final zoomDir = Directory(p.join(dir.path, '$z', '$x'));
    if (!await zoomDir.exists()) {
      await zoomDir.create(recursive: true);
    }
    return File(p.join(zoomDir.path, '$y.png'));
  }


  /// Caminho do arquivo SQLite. O Drift abre esse arquivo no primeiro
  /// acesso (`LazyDatabase` em `region_database.dart`).
  static Future<File> databaseFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _dbFileName));
  }


  /// Arquivo-sentinela de um tutorial.
  ///
  /// Um arquivo por fluxo (`flowId`): a tela inicial e a tela de análise
  /// têm tutoriais independentes, e quem já viu um não deve perder o
  /// outro. `flowId` vem do enum `OnboardingFlow`.
  ///
  /// Mesma técnica do `.complete` do mapa base: a EXISTÊNCIA do arquivo
  /// é o dado — não há conteúdo pra ler. Fica em AppDocs (não em cache)
  /// pra sobreviver a limpeza do SO; caso contrário o tutorial voltaria
  /// a aparecer do nada pra quem já usou o app.
  ///
  /// Escolhi arquivo em vez de `shared_preferences` pra não adicionar
  /// dependência nova — `path_provider` já está no projeto e o app já
  /// usa esse padrão de sentinela.
  static Future<File> onboardingFlagFile(String flowId) async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, '$_onboardingPrefix$flowId'));
  }


  /// Diretório do mapa base. Vive fora do `region_cache/` porque não
  /// participa da eviction — é infraestrutura curada.
  static Future<Directory> baseMapDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _baseMapDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Caminho de um tile do mapa base. Estrutura de pastas por zoom/x
  /// pra não estourar limite de arquivos por diretório em sistemas de
  /// arquivos antigos (algumas FS têm limite ~10k arquivos por dir).
  static Future<File> baseMapTileFile(int z, int x, int y) async {
    final dir = await baseMapDir();
    final zoomDir = Directory(p.join(dir.path, '$z', '$x'));
    if (!await zoomDir.exists()) {
      await zoomDir.create(recursive: true);
    }
    return File(p.join(zoomDir.path, '$y.png'));
  }
}
