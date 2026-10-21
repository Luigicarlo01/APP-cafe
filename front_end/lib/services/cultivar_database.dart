import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cópia SQLite offline da exportação MySQL. Independente do cache com TTL.
/// As consultas rodam em um isolate; o arquivo nunca é modificado pelas telas.
class CultivarDatabase {
  static final instance = CultivarDatabase();
  static const manifestAsset = 'assets/data/manifest.json';

  final AssetBundle _bundle;
  final Future<Directory> Function() _storageDirectory;
  Future<QueryExecutor>? _opening;
  Future<Map<int, Map<String, dynamic>>>? _rankings;
  bool _closed = false;

  CultivarDatabase({
    AssetBundle? bundle,
    Future<Directory> Function()? storageDirectory,
  }) : _bundle = bundle ?? rootBundle,
       _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  Future<void> ready() async {
    await _executor();
  }

  Future<QueryExecutor> _executor() async {
    if (_closed) throw StateError('Banco local fechado.');
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<QueryExecutor> _open() async {
    final manifest =
        jsonDecode(await _bundle.loadString(manifestAsset))
            as Map<String, dynamic>;
    final checksum = manifest['database_sha256'] as String;
    if (manifest['schema_version'] != 1 ||
        manifest['format'] != 'cultivar-sqlite-wkb-v1' ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      throw const FormatException('Versão do banco local incompatível.');
    }
    final directory = Directory(
      p.join((await _storageDirectory()).path, 'cultivar_data'),
    );
    await directory.create(recursive: true);
    // Outra versão do APK recebe outro nome: não sobrescreve o banco anterior.
    final target = File(
      p.join(directory.path, 'cultivar_${checksum.substring(0, 20)}.sqlite'),
    );
    if (!await target.exists()) {
      final packed = await _bundle.load(manifest['asset'] as String);
      final bytes = packed.buffer.asUint8List(
        packed.offsetInBytes,
        packed.lengthInBytes,
      );
      final packedHash = await sha256.bind(_chunks(bytes)).first;
      if (packedHash.toString() != manifest['compressed_sha256']) {
        throw const FormatException('Pacote de dados locais incompleto.');
      }
      final staged = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
      );
      try {
        // Entrada em blocos evita manter o banco inteiro descompactado na RAM.
        await _chunks(bytes).transform(gzip.decoder).pipe(staged.openWrite());
        if (await staged.length() != manifest['database_bytes'] ||
            (await sha256.bind(staged.openRead()).first).toString() !=
                checksum) {
          throw const FormatException('Falha ao conferir os dados locais.');
        }
        await staged.rename(target.path);
      } catch (_) {
        if (await staged.exists()) await staged.delete();
        rethrow;
      }
    }
    final executor = NativeDatabase.createInBackground(
      target,
      enableMigrations: false,
      setup: (database) => database.execute('PRAGMA query_only=ON'),
    );
    try {
      await executor.ensureOpen(_SnapshotUser());
      final metadata = await executor.runSelect(
        'SELECT chave,valor FROM cultivar_metadata',
        [],
      );
      final values = {for (final row in metadata) row['chave']: row['valor']};
      if (values['format'] != manifest['format'] ||
          values['source_sql_sha256'] != manifest['source_sql_sha256']) {
        throw const FormatException(
          'Banco local diferente da versão do aplicativo.',
        );
      }
      return executor;
    } catch (_) {
      await executor.close();
      rethrow;
    }
  }

  static Stream<List<int>> _chunks(Uint8List bytes) async* {
    const size = 64 * 1024;
    for (var offset = 0; offset < bytes.length; offset += size) {
      final end = offset + size < bytes.length ? offset + size : bytes.length;
      yield Uint8List.sublistView(bytes, offset, end);
    }
  }

  Future<List<Map<String, dynamic>>> municipalities(int year) async {
    final rows = await (await _executor()).runSelect(
      '''
      SELECT m.codigo,m.nome,a.arquivo,a.min_lon,a.min_lat,a.max_lon,a.max_lat,
             a.centro_lon,a.centro_lat
      FROM cultivar_municipios m
      JOIN cultivar_arquivos a ON a.municipio_codigo=m.codigo
      WHERE a.ano=? ORDER BY m.nome
    ''',
      [year],
    );
    return rows
        .map(
          (row) => <String, dynamic>{
            'code': row['codigo'],
            'name': row['nome'],
            'asset': 'assets/${row['arquivo']}',
            'bbox': [
              row['min_lon'],
              row['min_lat'],
              row['max_lon'],
              row['max_lat'],
            ],
            'center': [row['centro_lon'], row['centro_lat']],
          },
        )
        .toList(growable: false);
  }

  Future<Uint8List> boundary(String assetPath) async {
    final rows = await (await _executor()).runSelect(
      '''
      SELECT f.geometria FROM cultivar_feicoes f
      JOIN cultivar_arquivos a ON a.id=f.arquivo_id
      WHERE a.arquivo=? AND f.tipo='municipio'
    ''',
      [p.basename(assetPath)],
    );
    if (rows.length != 1) {
      throw const FormatException('Limite municipal ausente no banco.');
    }
    return rows.single['geometria'] as Uint8List;
  }

  Future<Map<int, Map<String, dynamic>>> _loadRankings() async {
    final rows = await (await _executor()).runSelect(
      'SELECT id,propriedades_json FROM cultivar_rankings',
      [],
    );
    return {
      for (final row in rows)
        row['id'] as int:
            jsonDecode(row['propriedades_json'] as String)
                as Map<String, dynamic>,
    };
  }

  Future<Map<String, Object>> region(String assetPath) async {
    final rows = await (await _executor()).runSelect(
      '''
      SELECT f.geometria,f.ranking_id FROM cultivar_feicoes f
      JOIN cultivar_arquivos a ON a.id=f.arquivo_id
      WHERE a.arquivo=? AND f.tipo='grid' ORDER BY f.indice
    ''',
      [p.basename(assetPath)],
    );
    return {
      'features': rows,
      'rankings': await (_rankings ??= _loadRankings()),
    };
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final pending = _opening;
    if (pending != null) {
      try {
        await (await pending).close();
      } catch (_) {
        /* abertura já falhou */
      }
    }
  }
}

class _SnapshotUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
