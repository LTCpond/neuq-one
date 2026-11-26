// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'classroom_cache.dart';

// ignore_for_file: type=lint
class $ClassroomCacheEntriesTable extends ClassroomCacheEntries
    with TableInfo<$ClassroomCacheEntriesTable, ClassroomCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClassroomCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resourceMeta = const VerificationMeta(
    'resource',
  );
  @override
  late final GeneratedColumn<String> resource = GeneratedColumn<String>(
    'resource',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<String> lastModified = GeneratedColumn<String>(
    'last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cacheControlMeta = const VerificationMeta(
    'cacheControl',
  );
  @override
  late final GeneratedColumn<String> cacheControl = GeneratedColumn<String>(
    'cache_control',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _freshUntilMeta = const VerificationMeta(
    'freshUntil',
  );
  @override
  late final GeneratedColumn<DateTime> freshUntil = GeneratedColumn<DateTime>(
    'fresh_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payload,
    checkedAt,
    resource,
    etag,
    lastModified,
    cacheControl,
    freshUntil,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'classroom_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClassroomCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_checkedAtMeta);
    }
    if (data.containsKey('resource')) {
      context.handle(
        _resourceMeta,
        resource.isAcceptableOrUnknown(data['resource']!, _resourceMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('last_modified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['last_modified']!,
          _lastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('cache_control')) {
      context.handle(
        _cacheControlMeta,
        cacheControl.isAcceptableOrUnknown(
          data['cache_control']!,
          _cacheControlMeta,
        ),
      );
    }
    if (data.containsKey('fresh_until')) {
      context.handle(
        _freshUntilMeta,
        freshUntil.isAcceptableOrUnknown(data['fresh_until']!, _freshUntilMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClassroomCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClassroomCacheEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      )!,
      resource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource'],
      ),
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified'],
      ),
      cacheControl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_control'],
      ),
      freshUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fresh_until'],
      ),
    );
  }

  @override
  $ClassroomCacheEntriesTable createAlias(String alias) {
    return $ClassroomCacheEntriesTable(attachedDatabase, alias);
  }
}

class ClassroomCacheEntry extends DataClass
    implements Insertable<ClassroomCacheEntry> {
  final int id;
  final String payload;
  final DateTime checkedAt;
  final String? resource;
  final String? etag;
  final String? lastModified;
  final String? cacheControl;
  final DateTime? freshUntil;
  const ClassroomCacheEntry({
    required this.id,
    required this.payload,
    required this.checkedAt,
    this.resource,
    this.etag,
    this.lastModified,
    this.cacheControl,
    this.freshUntil,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['payload'] = Variable<String>(payload);
    map['checked_at'] = Variable<DateTime>(checkedAt);
    if (!nullToAbsent || resource != null) {
      map['resource'] = Variable<String>(resource);
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || lastModified != null) {
      map['last_modified'] = Variable<String>(lastModified);
    }
    if (!nullToAbsent || cacheControl != null) {
      map['cache_control'] = Variable<String>(cacheControl);
    }
    if (!nullToAbsent || freshUntil != null) {
      map['fresh_until'] = Variable<DateTime>(freshUntil);
    }
    return map;
  }

  ClassroomCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return ClassroomCacheEntriesCompanion(
      id: Value(id),
      payload: Value(payload),
      checkedAt: Value(checkedAt),
      resource: resource == null && nullToAbsent
          ? const Value.absent()
          : Value(resource),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
      cacheControl: cacheControl == null && nullToAbsent
          ? const Value.absent()
          : Value(cacheControl),
      freshUntil: freshUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(freshUntil),
    );
  }

  factory ClassroomCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClassroomCacheEntry(
      id: serializer.fromJson<int>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
      checkedAt: serializer.fromJson<DateTime>(json['checkedAt']),
      resource: serializer.fromJson<String?>(json['resource']),
      etag: serializer.fromJson<String?>(json['etag']),
      lastModified: serializer.fromJson<String?>(json['lastModified']),
      cacheControl: serializer.fromJson<String?>(json['cacheControl']),
      freshUntil: serializer.fromJson<DateTime?>(json['freshUntil']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'payload': serializer.toJson<String>(payload),
      'checkedAt': serializer.toJson<DateTime>(checkedAt),
      'resource': serializer.toJson<String?>(resource),
      'etag': serializer.toJson<String?>(etag),
      'lastModified': serializer.toJson<String?>(lastModified),
      'cacheControl': serializer.toJson<String?>(cacheControl),
      'freshUntil': serializer.toJson<DateTime?>(freshUntil),
    };
  }

  ClassroomCacheEntry copyWith({
    int? id,
    String? payload,
    DateTime? checkedAt,
    Value<String?> resource = const Value.absent(),
    Value<String?> etag = const Value.absent(),
    Value<String?> lastModified = const Value.absent(),
    Value<String?> cacheControl = const Value.absent(),
    Value<DateTime?> freshUntil = const Value.absent(),
  }) => ClassroomCacheEntry(
    id: id ?? this.id,
    payload: payload ?? this.payload,
    checkedAt: checkedAt ?? this.checkedAt,
    resource: resource.present ? resource.value : this.resource,
    etag: etag.present ? etag.value : this.etag,
    lastModified: lastModified.present ? lastModified.value : this.lastModified,
    cacheControl: cacheControl.present ? cacheControl.value : this.cacheControl,
    freshUntil: freshUntil.present ? freshUntil.value : this.freshUntil,
  );
  ClassroomCacheEntry copyWithCompanion(ClassroomCacheEntriesCompanion data) {
    return ClassroomCacheEntry(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      resource: data.resource.present ? data.resource.value : this.resource,
      etag: data.etag.present ? data.etag.value : this.etag,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      cacheControl: data.cacheControl.present
          ? data.cacheControl.value
          : this.cacheControl,
      freshUntil: data.freshUntil.present
          ? data.freshUntil.value
          : this.freshUntil,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClassroomCacheEntry(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('resource: $resource, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('cacheControl: $cacheControl, ')
          ..write('freshUntil: $freshUntil')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    payload,
    checkedAt,
    resource,
    etag,
    lastModified,
    cacheControl,
    freshUntil,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClassroomCacheEntry &&
          other.id == this.id &&
          other.payload == this.payload &&
          other.checkedAt == this.checkedAt &&
          other.resource == this.resource &&
          other.etag == this.etag &&
          other.lastModified == this.lastModified &&
          other.cacheControl == this.cacheControl &&
          other.freshUntil == this.freshUntil);
}

class ClassroomCacheEntriesCompanion
    extends UpdateCompanion<ClassroomCacheEntry> {
  final Value<int> id;
  final Value<String> payload;
  final Value<DateTime> checkedAt;
  final Value<String?> resource;
  final Value<String?> etag;
  final Value<String?> lastModified;
  final Value<String?> cacheControl;
  final Value<DateTime?> freshUntil;
  const ClassroomCacheEntriesCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.resource = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.cacheControl = const Value.absent(),
    this.freshUntil = const Value.absent(),
  });
  ClassroomCacheEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String payload,
    required DateTime checkedAt,
    this.resource = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.cacheControl = const Value.absent(),
    this.freshUntil = const Value.absent(),
  }) : payload = Value(payload),
       checkedAt = Value(checkedAt);
  static Insertable<ClassroomCacheEntry> custom({
    Expression<int>? id,
    Expression<String>? payload,
    Expression<DateTime>? checkedAt,
    Expression<String>? resource,
    Expression<String>? etag,
    Expression<String>? lastModified,
    Expression<String>? cacheControl,
    Expression<DateTime>? freshUntil,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (resource != null) 'resource': resource,
      if (etag != null) 'etag': etag,
      if (lastModified != null) 'last_modified': lastModified,
      if (cacheControl != null) 'cache_control': cacheControl,
      if (freshUntil != null) 'fresh_until': freshUntil,
    });
  }

  ClassroomCacheEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? payload,
    Value<DateTime>? checkedAt,
    Value<String?>? resource,
    Value<String?>? etag,
    Value<String?>? lastModified,
    Value<String?>? cacheControl,
    Value<DateTime?>? freshUntil,
  }) {
    return ClassroomCacheEntriesCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      checkedAt: checkedAt ?? this.checkedAt,
      resource: resource ?? this.resource,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      cacheControl: cacheControl ?? this.cacheControl,
      freshUntil: freshUntil ?? this.freshUntil,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (resource.present) {
      map['resource'] = Variable<String>(resource.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<String>(lastModified.value);
    }
    if (cacheControl.present) {
      map['cache_control'] = Variable<String>(cacheControl.value);
    }
    if (freshUntil.present) {
      map['fresh_until'] = Variable<DateTime>(freshUntil.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClassroomCacheEntriesCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('resource: $resource, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('cacheControl: $cacheControl, ')
          ..write('freshUntil: $freshUntil')
          ..write(')'))
        .toString();
  }
}

abstract class _$ClassroomCache extends GeneratedDatabase {
  _$ClassroomCache(QueryExecutor e) : super(e);
  $ClassroomCacheManager get managers => $ClassroomCacheManager(this);
  late final $ClassroomCacheEntriesTable classroomCacheEntries =
      $ClassroomCacheEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [classroomCacheEntries];
}

typedef $$ClassroomCacheEntriesTableCreateCompanionBuilder =
    ClassroomCacheEntriesCompanion Function({
      Value<int> id,
      required String payload,
      required DateTime checkedAt,
      Value<String?> resource,
      Value<String?> etag,
      Value<String?> lastModified,
      Value<String?> cacheControl,
      Value<DateTime?> freshUntil,
    });
typedef $$ClassroomCacheEntriesTableUpdateCompanionBuilder =
    ClassroomCacheEntriesCompanion Function({
      Value<int> id,
      Value<String> payload,
      Value<DateTime> checkedAt,
      Value<String?> resource,
      Value<String?> etag,
      Value<String?> lastModified,
      Value<String?> cacheControl,
      Value<DateTime?> freshUntil,
    });

class $$ClassroomCacheEntriesTableFilterComposer
    extends Composer<_$ClassroomCache, $ClassroomCacheEntriesTable> {
  $$ClassroomCacheEntriesTableFilterComposer({
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

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resource => $composableBuilder(
    column: $table.resource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheControl => $composableBuilder(
    column: $table.cacheControl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get freshUntil => $composableBuilder(
    column: $table.freshUntil,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClassroomCacheEntriesTableOrderingComposer
    extends Composer<_$ClassroomCache, $ClassroomCacheEntriesTable> {
  $$ClassroomCacheEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resource => $composableBuilder(
    column: $table.resource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheControl => $composableBuilder(
    column: $table.cacheControl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get freshUntil => $composableBuilder(
    column: $table.freshUntil,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClassroomCacheEntriesTableAnnotationComposer
    extends Composer<_$ClassroomCache, $ClassroomCacheEntriesTable> {
  $$ClassroomCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumn<String> get resource =>
      $composableBuilder(column: $table.resource, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cacheControl => $composableBuilder(
    column: $table.cacheControl,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get freshUntil => $composableBuilder(
    column: $table.freshUntil,
    builder: (column) => column,
  );
}

class $$ClassroomCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$ClassroomCache,
          $ClassroomCacheEntriesTable,
          ClassroomCacheEntry,
          $$ClassroomCacheEntriesTableFilterComposer,
          $$ClassroomCacheEntriesTableOrderingComposer,
          $$ClassroomCacheEntriesTableAnnotationComposer,
          $$ClassroomCacheEntriesTableCreateCompanionBuilder,
          $$ClassroomCacheEntriesTableUpdateCompanionBuilder,
          (
            ClassroomCacheEntry,
            BaseReferences<
              _$ClassroomCache,
              $ClassroomCacheEntriesTable,
              ClassroomCacheEntry
            >,
          ),
          ClassroomCacheEntry,
          PrefetchHooks Function()
        > {
  $$ClassroomCacheEntriesTableTableManager(
    _$ClassroomCache db,
    $ClassroomCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClassroomCacheEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ClassroomCacheEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ClassroomCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> checkedAt = const Value.absent(),
                Value<String?> resource = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<String?> cacheControl = const Value.absent(),
                Value<DateTime?> freshUntil = const Value.absent(),
              }) => ClassroomCacheEntriesCompanion(
                id: id,
                payload: payload,
                checkedAt: checkedAt,
                resource: resource,
                etag: etag,
                lastModified: lastModified,
                cacheControl: cacheControl,
                freshUntil: freshUntil,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String payload,
                required DateTime checkedAt,
                Value<String?> resource = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<String?> cacheControl = const Value.absent(),
                Value<DateTime?> freshUntil = const Value.absent(),
              }) => ClassroomCacheEntriesCompanion.insert(
                id: id,
                payload: payload,
                checkedAt: checkedAt,
                resource: resource,
                etag: etag,
                lastModified: lastModified,
                cacheControl: cacheControl,
                freshUntil: freshUntil,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClassroomCacheEntriesTable, ClassroomCacheEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$ClassroomCache,
                    $ClassroomCacheEntriesTable,
                    ClassroomCacheEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClassroomCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ClassroomCache,
      $ClassroomCacheEntriesTable,
      ClassroomCacheEntry,
      $$ClassroomCacheEntriesTableFilterComposer,
      $$ClassroomCacheEntriesTableOrderingComposer,
      $$ClassroomCacheEntriesTableAnnotationComposer,
      $$ClassroomCacheEntriesTableCreateCompanionBuilder,
      $$ClassroomCacheEntriesTableUpdateCompanionBuilder,
      (
        ClassroomCacheEntry,
        BaseReferences<
          _$ClassroomCache,
          $ClassroomCacheEntriesTable,
          ClassroomCacheEntry
        >,
      ),
      ClassroomCacheEntry,
      PrefetchHooks Function()
    >;

class $ClassroomCacheManager {
  final _$ClassroomCache _db;
  $ClassroomCacheManager(this._db);
  $$ClassroomCacheEntriesTableTableManager get classroomCacheEntries =>
      $$ClassroomCacheEntriesTableTableManager(_db, _db.classroomCacheEntries);
}
