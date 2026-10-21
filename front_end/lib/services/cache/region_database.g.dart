// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'region_database.dart';

// ignore_for_file: type=lint
class $CachedRegionsTable extends CachedRegions
    with TableInfo<$CachedRegionsTable, CachedRegionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedRegionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _municipioMeta = const VerificationMeta(
    'municipio',
  );
  @override
  late final GeneratedColumn<String> municipio = GeneratedColumn<String>(
    'municipio',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minLatMeta = const VerificationMeta('minLat');
  @override
  late final GeneratedColumn<double> minLat = GeneratedColumn<double>(
    'min_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxLatMeta = const VerificationMeta('maxLat');
  @override
  late final GeneratedColumn<double> maxLat = GeneratedColumn<double>(
    'max_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minLonMeta = const VerificationMeta('minLon');
  @override
  late final GeneratedColumn<double> minLon = GeneratedColumn<double>(
    'min_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxLonMeta = const VerificationMeta('maxLon');
  @override
  late final GeneratedColumn<double> maxLon = GeneratedColumn<double>(
    'max_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAccessAtMeta = const VerificationMeta(
    'lastAccessAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAccessAt = GeneratedColumn<DateTime>(
    'last_access_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accessCountMeta = const VerificationMeta(
    'accessCount',
  );
  @override
  late final GeneratedColumn<int> accessCount = GeneratedColumn<int>(
    'access_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
    'metadata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tilesBytesMeta = const VerificationMeta(
    'tilesBytes',
  );
  @override
  late final GeneratedColumn<int> tilesBytes = GeneratedColumn<int>(
    'tiles_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tilesMaxZoomMeta = const VerificationMeta(
    'tilesMaxZoom',
  );
  @override
  late final GeneratedColumn<int> tilesMaxZoom = GeneratedColumn<int>(
    'tiles_max_zoom',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    municipio,
    minLat,
    maxLat,
    minLon,
    maxLon,
    filePath,
    fileSizeBytes,
    createdAt,
    lastAccessAt,
    accessCount,
    metadata,
    tilesBytes,
    tilesMaxZoom,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_regions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedRegionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('municipio')) {
      context.handle(
        _municipioMeta,
        municipio.isAcceptableOrUnknown(data['municipio']!, _municipioMeta),
      );
    } else if (isInserting) {
      context.missing(_municipioMeta);
    }
    if (data.containsKey('min_lat')) {
      context.handle(
        _minLatMeta,
        minLat.isAcceptableOrUnknown(data['min_lat']!, _minLatMeta),
      );
    } else if (isInserting) {
      context.missing(_minLatMeta);
    }
    if (data.containsKey('max_lat')) {
      context.handle(
        _maxLatMeta,
        maxLat.isAcceptableOrUnknown(data['max_lat']!, _maxLatMeta),
      );
    } else if (isInserting) {
      context.missing(_maxLatMeta);
    }
    if (data.containsKey('min_lon')) {
      context.handle(
        _minLonMeta,
        minLon.isAcceptableOrUnknown(data['min_lon']!, _minLonMeta),
      );
    } else if (isInserting) {
      context.missing(_minLonMeta);
    }
    if (data.containsKey('max_lon')) {
      context.handle(
        _maxLonMeta,
        maxLon.isAcceptableOrUnknown(data['max_lon']!, _maxLonMeta),
      );
    } else if (isInserting) {
      context.missing(_maxLonMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fileSizeBytesMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_access_at')) {
      context.handle(
        _lastAccessAtMeta,
        lastAccessAt.isAcceptableOrUnknown(
          data['last_access_at']!,
          _lastAccessAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessAtMeta);
    }
    if (data.containsKey('access_count')) {
      context.handle(
        _accessCountMeta,
        accessCount.isAcceptableOrUnknown(
          data['access_count']!,
          _accessCountMeta,
        ),
      );
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    }
    if (data.containsKey('tiles_bytes')) {
      context.handle(
        _tilesBytesMeta,
        tilesBytes.isAcceptableOrUnknown(data['tiles_bytes']!, _tilesBytesMeta),
      );
    }
    if (data.containsKey('tiles_max_zoom')) {
      context.handle(
        _tilesMaxZoomMeta,
        tilesMaxZoom.isAcceptableOrUnknown(
          data['tiles_max_zoom']!,
          _tilesMaxZoomMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedRegionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedRegionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      municipio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}municipio'],
      )!,
      minLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_lat'],
      )!,
      maxLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_lat'],
      )!,
      minLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_lon'],
      )!,
      maxLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_lon'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastAccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_access_at'],
      )!,
      accessCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}access_count'],
      )!,
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata'],
      ),
      tilesBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tiles_bytes'],
      )!,
      tilesMaxZoom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tiles_max_zoom'],
      ),
    );
  }

  @override
  $CachedRegionsTable createAlias(String alias) {
    return $CachedRegionsTable(attachedDatabase, alias);
  }
}

class CachedRegionRow extends DataClass implements Insertable<CachedRegionRow> {
  final int id;
  final String municipio;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final String filePath;
  final int fileSizeBytes;
  final DateTime createdAt;
  final DateTime lastAccessAt;
  final int accessCount;

  /// JSON serializado com metadados (winners, etc.). Nullable para permitir
  /// legado.
  final String? metadata;

  /// v2 — bytes ocupados por tiles OSM baixados pra essa região.
  /// Zero se ainda não baixamos tiles.
  final int tilesBytes;

  /// v2 — zoom máximo que o download proativo alcançou (adaptativo por
  /// tamanho do bbox). `null` se ainda não baixamos.
  final int? tilesMaxZoom;
  const CachedRegionRow({
    required this.id,
    required this.municipio,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.filePath,
    required this.fileSizeBytes,
    required this.createdAt,
    required this.lastAccessAt,
    required this.accessCount,
    this.metadata,
    required this.tilesBytes,
    this.tilesMaxZoom,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['municipio'] = Variable<String>(municipio);
    map['min_lat'] = Variable<double>(minLat);
    map['max_lat'] = Variable<double>(maxLat);
    map['min_lon'] = Variable<double>(minLon);
    map['max_lon'] = Variable<double>(maxLon);
    map['file_path'] = Variable<String>(filePath);
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_access_at'] = Variable<DateTime>(lastAccessAt);
    map['access_count'] = Variable<int>(accessCount);
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    map['tiles_bytes'] = Variable<int>(tilesBytes);
    if (!nullToAbsent || tilesMaxZoom != null) {
      map['tiles_max_zoom'] = Variable<int>(tilesMaxZoom);
    }
    return map;
  }

  CachedRegionsCompanion toCompanion(bool nullToAbsent) {
    return CachedRegionsCompanion(
      id: Value(id),
      municipio: Value(municipio),
      minLat: Value(minLat),
      maxLat: Value(maxLat),
      minLon: Value(minLon),
      maxLon: Value(maxLon),
      filePath: Value(filePath),
      fileSizeBytes: Value(fileSizeBytes),
      createdAt: Value(createdAt),
      lastAccessAt: Value(lastAccessAt),
      accessCount: Value(accessCount),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
      tilesBytes: Value(tilesBytes),
      tilesMaxZoom: tilesMaxZoom == null && nullToAbsent
          ? const Value.absent()
          : Value(tilesMaxZoom),
    );
  }

  factory CachedRegionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedRegionRow(
      id: serializer.fromJson<int>(json['id']),
      municipio: serializer.fromJson<String>(json['municipio']),
      minLat: serializer.fromJson<double>(json['minLat']),
      maxLat: serializer.fromJson<double>(json['maxLat']),
      minLon: serializer.fromJson<double>(json['minLon']),
      maxLon: serializer.fromJson<double>(json['maxLon']),
      filePath: serializer.fromJson<String>(json['filePath']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAccessAt: serializer.fromJson<DateTime>(json['lastAccessAt']),
      accessCount: serializer.fromJson<int>(json['accessCount']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      tilesBytes: serializer.fromJson<int>(json['tilesBytes']),
      tilesMaxZoom: serializer.fromJson<int?>(json['tilesMaxZoom']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'municipio': serializer.toJson<String>(municipio),
      'minLat': serializer.toJson<double>(minLat),
      'maxLat': serializer.toJson<double>(maxLat),
      'minLon': serializer.toJson<double>(minLon),
      'maxLon': serializer.toJson<double>(maxLon),
      'filePath': serializer.toJson<String>(filePath),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAccessAt': serializer.toJson<DateTime>(lastAccessAt),
      'accessCount': serializer.toJson<int>(accessCount),
      'metadata': serializer.toJson<String?>(metadata),
      'tilesBytes': serializer.toJson<int>(tilesBytes),
      'tilesMaxZoom': serializer.toJson<int?>(tilesMaxZoom),
    };
  }

  CachedRegionRow copyWith({
    int? id,
    String? municipio,
    double? minLat,
    double? maxLat,
    double? minLon,
    double? maxLon,
    String? filePath,
    int? fileSizeBytes,
    DateTime? createdAt,
    DateTime? lastAccessAt,
    int? accessCount,
    Value<String?> metadata = const Value.absent(),
    int? tilesBytes,
    Value<int?> tilesMaxZoom = const Value.absent(),
  }) => CachedRegionRow(
    id: id ?? this.id,
    municipio: municipio ?? this.municipio,
    minLat: minLat ?? this.minLat,
    maxLat: maxLat ?? this.maxLat,
    minLon: minLon ?? this.minLon,
    maxLon: maxLon ?? this.maxLon,
    filePath: filePath ?? this.filePath,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    createdAt: createdAt ?? this.createdAt,
    lastAccessAt: lastAccessAt ?? this.lastAccessAt,
    accessCount: accessCount ?? this.accessCount,
    metadata: metadata.present ? metadata.value : this.metadata,
    tilesBytes: tilesBytes ?? this.tilesBytes,
    tilesMaxZoom: tilesMaxZoom.present ? tilesMaxZoom.value : this.tilesMaxZoom,
  );
  CachedRegionRow copyWithCompanion(CachedRegionsCompanion data) {
    return CachedRegionRow(
      id: data.id.present ? data.id.value : this.id,
      municipio: data.municipio.present ? data.municipio.value : this.municipio,
      minLat: data.minLat.present ? data.minLat.value : this.minLat,
      maxLat: data.maxLat.present ? data.maxLat.value : this.maxLat,
      minLon: data.minLon.present ? data.minLon.value : this.minLon,
      maxLon: data.maxLon.present ? data.maxLon.value : this.maxLon,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAccessAt: data.lastAccessAt.present
          ? data.lastAccessAt.value
          : this.lastAccessAt,
      accessCount: data.accessCount.present
          ? data.accessCount.value
          : this.accessCount,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      tilesBytes: data.tilesBytes.present
          ? data.tilesBytes.value
          : this.tilesBytes,
      tilesMaxZoom: data.tilesMaxZoom.present
          ? data.tilesMaxZoom.value
          : this.tilesMaxZoom,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedRegionRow(')
          ..write('id: $id, ')
          ..write('municipio: $municipio, ')
          ..write('minLat: $minLat, ')
          ..write('maxLat: $maxLat, ')
          ..write('minLon: $minLon, ')
          ..write('maxLon: $maxLon, ')
          ..write('filePath: $filePath, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('accessCount: $accessCount, ')
          ..write('metadata: $metadata, ')
          ..write('tilesBytes: $tilesBytes, ')
          ..write('tilesMaxZoom: $tilesMaxZoom')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    municipio,
    minLat,
    maxLat,
    minLon,
    maxLon,
    filePath,
    fileSizeBytes,
    createdAt,
    lastAccessAt,
    accessCount,
    metadata,
    tilesBytes,
    tilesMaxZoom,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedRegionRow &&
          other.id == this.id &&
          other.municipio == this.municipio &&
          other.minLat == this.minLat &&
          other.maxLat == this.maxLat &&
          other.minLon == this.minLon &&
          other.maxLon == this.maxLon &&
          other.filePath == this.filePath &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.createdAt == this.createdAt &&
          other.lastAccessAt == this.lastAccessAt &&
          other.accessCount == this.accessCount &&
          other.metadata == this.metadata &&
          other.tilesBytes == this.tilesBytes &&
          other.tilesMaxZoom == this.tilesMaxZoom);
}

class CachedRegionsCompanion extends UpdateCompanion<CachedRegionRow> {
  final Value<int> id;
  final Value<String> municipio;
  final Value<double> minLat;
  final Value<double> maxLat;
  final Value<double> minLon;
  final Value<double> maxLon;
  final Value<String> filePath;
  final Value<int> fileSizeBytes;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastAccessAt;
  final Value<int> accessCount;
  final Value<String?> metadata;
  final Value<int> tilesBytes;
  final Value<int?> tilesMaxZoom;
  const CachedRegionsCompanion({
    this.id = const Value.absent(),
    this.municipio = const Value.absent(),
    this.minLat = const Value.absent(),
    this.maxLat = const Value.absent(),
    this.minLon = const Value.absent(),
    this.maxLon = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAccessAt = const Value.absent(),
    this.accessCount = const Value.absent(),
    this.metadata = const Value.absent(),
    this.tilesBytes = const Value.absent(),
    this.tilesMaxZoom = const Value.absent(),
  });
  CachedRegionsCompanion.insert({
    this.id = const Value.absent(),
    required String municipio,
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required String filePath,
    required int fileSizeBytes,
    required DateTime createdAt,
    required DateTime lastAccessAt,
    this.accessCount = const Value.absent(),
    this.metadata = const Value.absent(),
    this.tilesBytes = const Value.absent(),
    this.tilesMaxZoom = const Value.absent(),
  }) : municipio = Value(municipio),
       minLat = Value(minLat),
       maxLat = Value(maxLat),
       minLon = Value(minLon),
       maxLon = Value(maxLon),
       filePath = Value(filePath),
       fileSizeBytes = Value(fileSizeBytes),
       createdAt = Value(createdAt),
       lastAccessAt = Value(lastAccessAt);
  static Insertable<CachedRegionRow> custom({
    Expression<int>? id,
    Expression<String>? municipio,
    Expression<double>? minLat,
    Expression<double>? maxLat,
    Expression<double>? minLon,
    Expression<double>? maxLon,
    Expression<String>? filePath,
    Expression<int>? fileSizeBytes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAccessAt,
    Expression<int>? accessCount,
    Expression<String>? metadata,
    Expression<int>? tilesBytes,
    Expression<int>? tilesMaxZoom,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (municipio != null) 'municipio': municipio,
      if (minLat != null) 'min_lat': minLat,
      if (maxLat != null) 'max_lat': maxLat,
      if (minLon != null) 'min_lon': minLon,
      if (maxLon != null) 'max_lon': maxLon,
      if (filePath != null) 'file_path': filePath,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAccessAt != null) 'last_access_at': lastAccessAt,
      if (accessCount != null) 'access_count': accessCount,
      if (metadata != null) 'metadata': metadata,
      if (tilesBytes != null) 'tiles_bytes': tilesBytes,
      if (tilesMaxZoom != null) 'tiles_max_zoom': tilesMaxZoom,
    });
  }

  CachedRegionsCompanion copyWith({
    Value<int>? id,
    Value<String>? municipio,
    Value<double>? minLat,
    Value<double>? maxLat,
    Value<double>? minLon,
    Value<double>? maxLon,
    Value<String>? filePath,
    Value<int>? fileSizeBytes,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastAccessAt,
    Value<int>? accessCount,
    Value<String?>? metadata,
    Value<int>? tilesBytes,
    Value<int?>? tilesMaxZoom,
  }) {
    return CachedRegionsCompanion(
      id: id ?? this.id,
      municipio: municipio ?? this.municipio,
      minLat: minLat ?? this.minLat,
      maxLat: maxLat ?? this.maxLat,
      minLon: minLon ?? this.minLon,
      maxLon: maxLon ?? this.maxLon,
      filePath: filePath ?? this.filePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      createdAt: createdAt ?? this.createdAt,
      lastAccessAt: lastAccessAt ?? this.lastAccessAt,
      accessCount: accessCount ?? this.accessCount,
      metadata: metadata ?? this.metadata,
      tilesBytes: tilesBytes ?? this.tilesBytes,
      tilesMaxZoom: tilesMaxZoom ?? this.tilesMaxZoom,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (municipio.present) {
      map['municipio'] = Variable<String>(municipio.value);
    }
    if (minLat.present) {
      map['min_lat'] = Variable<double>(minLat.value);
    }
    if (maxLat.present) {
      map['max_lat'] = Variable<double>(maxLat.value);
    }
    if (minLon.present) {
      map['min_lon'] = Variable<double>(minLon.value);
    }
    if (maxLon.present) {
      map['max_lon'] = Variable<double>(maxLon.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAccessAt.present) {
      map['last_access_at'] = Variable<DateTime>(lastAccessAt.value);
    }
    if (accessCount.present) {
      map['access_count'] = Variable<int>(accessCount.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (tilesBytes.present) {
      map['tiles_bytes'] = Variable<int>(tilesBytes.value);
    }
    if (tilesMaxZoom.present) {
      map['tiles_max_zoom'] = Variable<int>(tilesMaxZoom.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedRegionsCompanion(')
          ..write('id: $id, ')
          ..write('municipio: $municipio, ')
          ..write('minLat: $minLat, ')
          ..write('maxLat: $maxLat, ')
          ..write('minLon: $minLon, ')
          ..write('maxLon: $maxLon, ')
          ..write('filePath: $filePath, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('accessCount: $accessCount, ')
          ..write('metadata: $metadata, ')
          ..write('tilesBytes: $tilesBytes, ')
          ..write('tilesMaxZoom: $tilesMaxZoom')
          ..write(')'))
        .toString();
  }
}

abstract class _$RegionDatabase extends GeneratedDatabase {
  _$RegionDatabase(QueryExecutor e) : super(e);
  $RegionDatabaseManager get managers => $RegionDatabaseManager(this);
  late final $CachedRegionsTable cachedRegions = $CachedRegionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cachedRegions];
}

typedef $$CachedRegionsTableCreateCompanionBuilder =
    CachedRegionsCompanion Function({
      Value<int> id,
      required String municipio,
      required double minLat,
      required double maxLat,
      required double minLon,
      required double maxLon,
      required String filePath,
      required int fileSizeBytes,
      required DateTime createdAt,
      required DateTime lastAccessAt,
      Value<int> accessCount,
      Value<String?> metadata,
      Value<int> tilesBytes,
      Value<int?> tilesMaxZoom,
    });
typedef $$CachedRegionsTableUpdateCompanionBuilder =
    CachedRegionsCompanion Function({
      Value<int> id,
      Value<String> municipio,
      Value<double> minLat,
      Value<double> maxLat,
      Value<double> minLon,
      Value<double> maxLon,
      Value<String> filePath,
      Value<int> fileSizeBytes,
      Value<DateTime> createdAt,
      Value<DateTime> lastAccessAt,
      Value<int> accessCount,
      Value<String?> metadata,
      Value<int> tilesBytes,
      Value<int?> tilesMaxZoom,
    });

class $$CachedRegionsTableFilterComposer
    extends Composer<_$RegionDatabase, $CachedRegionsTable> {
  $$CachedRegionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get municipio => $composableBuilder(
    column: $table.municipio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minLat => $composableBuilder(
    column: $table.minLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxLat => $composableBuilder(
    column: $table.maxLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minLon => $composableBuilder(
    column: $table.minLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxLon => $composableBuilder(
    column: $table.maxLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accessCount => $composableBuilder(
    column: $table.accessCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tilesBytes => $composableBuilder(
    column: $table.tilesBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tilesMaxZoom => $composableBuilder(
    column: $table.tilesMaxZoom,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedRegionsTableOrderingComposer
    extends Composer<_$RegionDatabase, $CachedRegionsTable> {
  $$CachedRegionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get municipio => $composableBuilder(
    column: $table.municipio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minLat => $composableBuilder(
    column: $table.minLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxLat => $composableBuilder(
    column: $table.maxLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minLon => $composableBuilder(
    column: $table.minLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxLon => $composableBuilder(
    column: $table.maxLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accessCount => $composableBuilder(
    column: $table.accessCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tilesBytes => $composableBuilder(
    column: $table.tilesBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tilesMaxZoom => $composableBuilder(
    column: $table.tilesMaxZoom,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedRegionsTableAnnotationComposer
    extends Composer<_$RegionDatabase, $CachedRegionsTable> {
  $$CachedRegionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get municipio =>
      $composableBuilder(column: $table.municipio, builder: (column) => column);

  GeneratedColumn<double> get minLat =>
      $composableBuilder(column: $table.minLat, builder: (column) => column);

  GeneratedColumn<double> get maxLat =>
      $composableBuilder(column: $table.maxLat, builder: (column) => column);

  GeneratedColumn<double> get minLon =>
      $composableBuilder(column: $table.minLon, builder: (column) => column);

  GeneratedColumn<double> get maxLon =>
      $composableBuilder(column: $table.maxLon, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accessCount => $composableBuilder(
    column: $table.accessCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<int> get tilesBytes => $composableBuilder(
    column: $table.tilesBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tilesMaxZoom => $composableBuilder(
    column: $table.tilesMaxZoom,
    builder: (column) => column,
  );
}

class $$CachedRegionsTableTableManager
    extends
        RootTableManager<
          _$RegionDatabase,
          $CachedRegionsTable,
          CachedRegionRow,
          $$CachedRegionsTableFilterComposer,
          $$CachedRegionsTableOrderingComposer,
          $$CachedRegionsTableAnnotationComposer,
          $$CachedRegionsTableCreateCompanionBuilder,
          $$CachedRegionsTableUpdateCompanionBuilder,
          (
            CachedRegionRow,
            BaseReferences<
              _$RegionDatabase,
              $CachedRegionsTable,
              CachedRegionRow
            >,
          ),
          CachedRegionRow,
          PrefetchHooks Function()
        > {
  $$CachedRegionsTableTableManager(
    _$RegionDatabase db,
    $CachedRegionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedRegionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedRegionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedRegionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> municipio = const Value.absent(),
                Value<double> minLat = const Value.absent(),
                Value<double> maxLat = const Value.absent(),
                Value<double> minLon = const Value.absent(),
                Value<double> maxLon = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int> fileSizeBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastAccessAt = const Value.absent(),
                Value<int> accessCount = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<int> tilesBytes = const Value.absent(),
                Value<int?> tilesMaxZoom = const Value.absent(),
              }) => CachedRegionsCompanion(
                id: id,
                municipio: municipio,
                minLat: minLat,
                maxLat: maxLat,
                minLon: minLon,
                maxLon: maxLon,
                filePath: filePath,
                fileSizeBytes: fileSizeBytes,
                createdAt: createdAt,
                lastAccessAt: lastAccessAt,
                accessCount: accessCount,
                metadata: metadata,
                tilesBytes: tilesBytes,
                tilesMaxZoom: tilesMaxZoom,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String municipio,
                required double minLat,
                required double maxLat,
                required double minLon,
                required double maxLon,
                required String filePath,
                required int fileSizeBytes,
                required DateTime createdAt,
                required DateTime lastAccessAt,
                Value<int> accessCount = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<int> tilesBytes = const Value.absent(),
                Value<int?> tilesMaxZoom = const Value.absent(),
              }) => CachedRegionsCompanion.insert(
                id: id,
                municipio: municipio,
                minLat: minLat,
                maxLat: maxLat,
                minLon: minLon,
                maxLon: maxLon,
                filePath: filePath,
                fileSizeBytes: fileSizeBytes,
                createdAt: createdAt,
                lastAccessAt: lastAccessAt,
                accessCount: accessCount,
                metadata: metadata,
                tilesBytes: tilesBytes,
                tilesMaxZoom: tilesMaxZoom,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedRegionsTableProcessedTableManager =
    ProcessedTableManager<
      _$RegionDatabase,
      $CachedRegionsTable,
      CachedRegionRow,
      $$CachedRegionsTableFilterComposer,
      $$CachedRegionsTableOrderingComposer,
      $$CachedRegionsTableAnnotationComposer,
      $$CachedRegionsTableCreateCompanionBuilder,
      $$CachedRegionsTableUpdateCompanionBuilder,
      (
        CachedRegionRow,
        BaseReferences<_$RegionDatabase, $CachedRegionsTable, CachedRegionRow>,
      ),
      CachedRegionRow,
      PrefetchHooks Function()
    >;

class $RegionDatabaseManager {
  final _$RegionDatabase _db;
  $RegionDatabaseManager(this._db);
  $$CachedRegionsTableTableManager get cachedRegions =>
      $$CachedRegionsTableTableManager(_db, _db.cachedRegions);
}
