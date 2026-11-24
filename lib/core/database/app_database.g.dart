// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SemesterRowsTable extends SemesterRows
    with TableInfo<$SemesterRowsTable, SemesterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SemesterRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<DateTime> start = GeneratedColumn<DateTime>(
    'start',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weeksMeta = const VerificationMeta('weeks');
  @override
  late final GeneratedColumn<int> weeks = GeneratedColumn<int>(
    'weeks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, start, weeks];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'semester_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SemesterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('start')) {
      context.handle(
        _startMeta,
        start.isAcceptableOrUnknown(data['start']!, _startMeta),
      );
    } else if (isInserting) {
      context.missing(_startMeta);
    }
    if (data.containsKey('weeks')) {
      context.handle(
        _weeksMeta,
        weeks.isAcceptableOrUnknown(data['weeks']!, _weeksMeta),
      );
    } else if (isInserting) {
      context.missing(_weeksMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SemesterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SemesterRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      start: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start'],
      )!,
      weeks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weeks'],
      )!,
    );
  }

  @override
  $SemesterRowsTable createAlias(String alias) {
    return $SemesterRowsTable(attachedDatabase, alias);
  }
}

class SemesterRow extends DataClass implements Insertable<SemesterRow> {
  final String id;
  final String name;
  final DateTime start;
  final int weeks;
  const SemesterRow({
    required this.id,
    required this.name,
    required this.start,
    required this.weeks,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['start'] = Variable<DateTime>(start);
    map['weeks'] = Variable<int>(weeks);
    return map;
  }

  SemesterRowsCompanion toCompanion(bool nullToAbsent) {
    return SemesterRowsCompanion(
      id: Value(id),
      name: Value(name),
      start: Value(start),
      weeks: Value(weeks),
    );
  }

  factory SemesterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SemesterRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      start: serializer.fromJson<DateTime>(json['start']),
      weeks: serializer.fromJson<int>(json['weeks']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'start': serializer.toJson<DateTime>(start),
      'weeks': serializer.toJson<int>(weeks),
    };
  }

  SemesterRow copyWith({
    String? id,
    String? name,
    DateTime? start,
    int? weeks,
  }) => SemesterRow(
    id: id ?? this.id,
    name: name ?? this.name,
    start: start ?? this.start,
    weeks: weeks ?? this.weeks,
  );
  SemesterRow copyWithCompanion(SemesterRowsCompanion data) {
    return SemesterRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      start: data.start.present ? data.start.value : this.start,
      weeks: data.weeks.present ? data.weeks.value : this.weeks,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SemesterRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('start: $start, ')
          ..write('weeks: $weeks')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, start, weeks);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SemesterRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.start == this.start &&
          other.weeks == this.weeks);
}

class SemesterRowsCompanion extends UpdateCompanion<SemesterRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> start;
  final Value<int> weeks;
  final Value<int> rowid;
  const SemesterRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.start = const Value.absent(),
    this.weeks = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SemesterRowsCompanion.insert({
    required String id,
    required String name,
    required DateTime start,
    required int weeks,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       start = Value(start),
       weeks = Value(weeks);
  static Insertable<SemesterRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? start,
    Expression<int>? weeks,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (start != null) 'start': start,
      if (weeks != null) 'weeks': weeks,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SemesterRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? start,
    Value<int>? weeks,
    Value<int>? rowid,
  }) {
    return SemesterRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      start: start ?? this.start,
      weeks: weeks ?? this.weeks,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (start.present) {
      map['start'] = Variable<DateTime>(start.value);
    }
    if (weeks.present) {
      map['weeks'] = Variable<int>(weeks.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SemesterRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('start: $start, ')
          ..write('weeks: $weeks, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CourseRowsTable extends CourseRows
    with TableInfo<$CourseRowsTable, CourseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<String> semesterId = GeneratedColumn<String>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES semester_rows (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teacherMeta = const VerificationMeta(
    'teacher',
  );
  @override
  late final GeneratedColumn<String> teacher = GeneratedColumn<String>(
    'teacher',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomMeta = const VerificationMeta('room');
  @override
  late final GeneratedColumn<String> room = GeneratedColumn<String>(
    'room',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMinuteMeta = const VerificationMeta(
    'startMinute',
  );
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
    'start_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMinuteMeta = const VerificationMeta(
    'endMinute',
  );
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
    'end_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weeksMeta = const VerificationMeta('weeks');
  @override
  late final GeneratedColumn<String> weeks = GeneratedColumn<String>(
    'weeks',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorIndexMeta = const VerificationMeta(
    'colorIndex',
  );
  @override
  late final GeneratedColumn<int> colorIndex = GeneratedColumn<int>(
    'color_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    semesterId,
    name,
    teacher,
    room,
    weekday,
    startMinute,
    endMinute,
    weeks,
    colorIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CourseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('teacher')) {
      context.handle(
        _teacherMeta,
        teacher.isAcceptableOrUnknown(data['teacher']!, _teacherMeta),
      );
    } else if (isInserting) {
      context.missing(_teacherMeta);
    }
    if (data.containsKey('room')) {
      context.handle(
        _roomMeta,
        room.isAcceptableOrUnknown(data['room']!, _roomMeta),
      );
    } else if (isInserting) {
      context.missing(_roomMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('start_minute')) {
      context.handle(
        _startMinuteMeta,
        startMinute.isAcceptableOrUnknown(
          data['start_minute']!,
          _startMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startMinuteMeta);
    }
    if (data.containsKey('end_minute')) {
      context.handle(
        _endMinuteMeta,
        endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta),
      );
    } else if (isInserting) {
      context.missing(_endMinuteMeta);
    }
    if (data.containsKey('weeks')) {
      context.handle(
        _weeksMeta,
        weeks.isAcceptableOrUnknown(data['weeks']!, _weeksMeta),
      );
    } else if (isInserting) {
      context.missing(_weeksMeta);
    }
    if (data.containsKey('color_index')) {
      context.handle(
        _colorIndexMeta,
        colorIndex.isAcceptableOrUnknown(data['color_index']!, _colorIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_colorIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CourseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}semester_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      teacher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teacher'],
      )!,
      room: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      startMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_minute'],
      )!,
      endMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_minute'],
      )!,
      weeks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weeks'],
      )!,
      colorIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_index'],
      )!,
    );
  }

  @override
  $CourseRowsTable createAlias(String alias) {
    return $CourseRowsTable(attachedDatabase, alias);
  }
}

class CourseRow extends DataClass implements Insertable<CourseRow> {
  final String id;
  final String semesterId;
  final String name;
  final String teacher;
  final String room;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final String weeks;
  final int colorIndex;
  const CourseRow({
    required this.id,
    required this.semesterId,
    required this.name,
    required this.teacher,
    required this.room,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.weeks,
    required this.colorIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['semester_id'] = Variable<String>(semesterId);
    map['name'] = Variable<String>(name);
    map['teacher'] = Variable<String>(teacher);
    map['room'] = Variable<String>(room);
    map['weekday'] = Variable<int>(weekday);
    map['start_minute'] = Variable<int>(startMinute);
    map['end_minute'] = Variable<int>(endMinute);
    map['weeks'] = Variable<String>(weeks);
    map['color_index'] = Variable<int>(colorIndex);
    return map;
  }

  CourseRowsCompanion toCompanion(bool nullToAbsent) {
    return CourseRowsCompanion(
      id: Value(id),
      semesterId: Value(semesterId),
      name: Value(name),
      teacher: Value(teacher),
      room: Value(room),
      weekday: Value(weekday),
      startMinute: Value(startMinute),
      endMinute: Value(endMinute),
      weeks: Value(weeks),
      colorIndex: Value(colorIndex),
    );
  }

  factory CourseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseRow(
      id: serializer.fromJson<String>(json['id']),
      semesterId: serializer.fromJson<String>(json['semesterId']),
      name: serializer.fromJson<String>(json['name']),
      teacher: serializer.fromJson<String>(json['teacher']),
      room: serializer.fromJson<String>(json['room']),
      weekday: serializer.fromJson<int>(json['weekday']),
      startMinute: serializer.fromJson<int>(json['startMinute']),
      endMinute: serializer.fromJson<int>(json['endMinute']),
      weeks: serializer.fromJson<String>(json['weeks']),
      colorIndex: serializer.fromJson<int>(json['colorIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'semesterId': serializer.toJson<String>(semesterId),
      'name': serializer.toJson<String>(name),
      'teacher': serializer.toJson<String>(teacher),
      'room': serializer.toJson<String>(room),
      'weekday': serializer.toJson<int>(weekday),
      'startMinute': serializer.toJson<int>(startMinute),
      'endMinute': serializer.toJson<int>(endMinute),
      'weeks': serializer.toJson<String>(weeks),
      'colorIndex': serializer.toJson<int>(colorIndex),
    };
  }

  CourseRow copyWith({
    String? id,
    String? semesterId,
    String? name,
    String? teacher,
    String? room,
    int? weekday,
    int? startMinute,
    int? endMinute,
    String? weeks,
    int? colorIndex,
  }) => CourseRow(
    id: id ?? this.id,
    semesterId: semesterId ?? this.semesterId,
    name: name ?? this.name,
    teacher: teacher ?? this.teacher,
    room: room ?? this.room,
    weekday: weekday ?? this.weekday,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    weeks: weeks ?? this.weeks,
    colorIndex: colorIndex ?? this.colorIndex,
  );
  CourseRow copyWithCompanion(CourseRowsCompanion data) {
    return CourseRow(
      id: data.id.present ? data.id.value : this.id,
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      name: data.name.present ? data.name.value : this.name,
      teacher: data.teacher.present ? data.teacher.value : this.teacher,
      room: data.room.present ? data.room.value : this.room,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      startMinute: data.startMinute.present
          ? data.startMinute.value
          : this.startMinute,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
      weeks: data.weeks.present ? data.weeks.value : this.weeks,
      colorIndex: data.colorIndex.present
          ? data.colorIndex.value
          : this.colorIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseRow(')
          ..write('id: $id, ')
          ..write('semesterId: $semesterId, ')
          ..write('name: $name, ')
          ..write('teacher: $teacher, ')
          ..write('room: $room, ')
          ..write('weekday: $weekday, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('weeks: $weeks, ')
          ..write('colorIndex: $colorIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    semesterId,
    name,
    teacher,
    room,
    weekday,
    startMinute,
    endMinute,
    weeks,
    colorIndex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseRow &&
          other.id == this.id &&
          other.semesterId == this.semesterId &&
          other.name == this.name &&
          other.teacher == this.teacher &&
          other.room == this.room &&
          other.weekday == this.weekday &&
          other.startMinute == this.startMinute &&
          other.endMinute == this.endMinute &&
          other.weeks == this.weeks &&
          other.colorIndex == this.colorIndex);
}

class CourseRowsCompanion extends UpdateCompanion<CourseRow> {
  final Value<String> id;
  final Value<String> semesterId;
  final Value<String> name;
  final Value<String> teacher;
  final Value<String> room;
  final Value<int> weekday;
  final Value<int> startMinute;
  final Value<int> endMinute;
  final Value<String> weeks;
  final Value<int> colorIndex;
  final Value<int> rowid;
  const CourseRowsCompanion({
    this.id = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.name = const Value.absent(),
    this.teacher = const Value.absent(),
    this.room = const Value.absent(),
    this.weekday = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.weeks = const Value.absent(),
    this.colorIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CourseRowsCompanion.insert({
    required String id,
    required String semesterId,
    required String name,
    required String teacher,
    required String room,
    required int weekday,
    required int startMinute,
    required int endMinute,
    required String weeks,
    required int colorIndex,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       semesterId = Value(semesterId),
       name = Value(name),
       teacher = Value(teacher),
       room = Value(room),
       weekday = Value(weekday),
       startMinute = Value(startMinute),
       endMinute = Value(endMinute),
       weeks = Value(weeks),
       colorIndex = Value(colorIndex);
  static Insertable<CourseRow> custom({
    Expression<String>? id,
    Expression<String>? semesterId,
    Expression<String>? name,
    Expression<String>? teacher,
    Expression<String>? room,
    Expression<int>? weekday,
    Expression<int>? startMinute,
    Expression<int>? endMinute,
    Expression<String>? weeks,
    Expression<int>? colorIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (semesterId != null) 'semester_id': semesterId,
      if (name != null) 'name': name,
      if (teacher != null) 'teacher': teacher,
      if (room != null) 'room': room,
      if (weekday != null) 'weekday': weekday,
      if (startMinute != null) 'start_minute': startMinute,
      if (endMinute != null) 'end_minute': endMinute,
      if (weeks != null) 'weeks': weeks,
      if (colorIndex != null) 'color_index': colorIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CourseRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? semesterId,
    Value<String>? name,
    Value<String>? teacher,
    Value<String>? room,
    Value<int>? weekday,
    Value<int>? startMinute,
    Value<int>? endMinute,
    Value<String>? weeks,
    Value<int>? colorIndex,
    Value<int>? rowid,
  }) {
    return CourseRowsCompanion(
      id: id ?? this.id,
      semesterId: semesterId ?? this.semesterId,
      name: name ?? this.name,
      teacher: teacher ?? this.teacher,
      room: room ?? this.room,
      weekday: weekday ?? this.weekday,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      weeks: weeks ?? this.weeks,
      colorIndex: colorIndex ?? this.colorIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (semesterId.present) {
      map['semester_id'] = Variable<String>(semesterId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (teacher.present) {
      map['teacher'] = Variable<String>(teacher.value);
    }
    if (room.present) {
      map['room'] = Variable<String>(room.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    if (weeks.present) {
      map['weeks'] = Variable<String>(weeks.value);
    }
    if (colorIndex.present) {
      map['color_index'] = Variable<int>(colorIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseRowsCompanion(')
          ..write('id: $id, ')
          ..write('semesterId: $semesterId, ')
          ..write('name: $name, ')
          ..write('teacher: $teacher, ')
          ..write('room: $room, ')
          ..write('weekday: $weekday, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('weeks: $weeks, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GradeRowsTable extends GradeRows
    with TableInfo<$GradeRowsTable, GradeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GradeRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<String> semesterId = GeneratedColumn<String>(
    'semester_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES semester_rows (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _creditMeta = const VerificationMeta('credit');
  @override
  late final GeneratedColumn<double> credit = GeneratedColumn<double>(
    'credit',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _demoMeta = const VerificationMeta('demo');
  @override
  late final GeneratedColumn<bool> demo = GeneratedColumn<bool>(
    'demo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("demo" IN (0, 1))',
    ),
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('numeric'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    semesterId,
    name,
    credit,
    score,
    kind,
    demo,
    format,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'grade_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<GradeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_semesterIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('credit')) {
      context.handle(
        _creditMeta,
        credit.isAcceptableOrUnknown(data['credit']!, _creditMeta),
      );
    } else if (isInserting) {
      context.missing(_creditMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('demo')) {
      context.handle(
        _demoMeta,
        demo.isAcceptableOrUnknown(data['demo']!, _demoMeta),
      );
    } else if (isInserting) {
      context.missing(_demoMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GradeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GradeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}semester_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      credit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}credit'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      demo: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}demo'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
    );
  }

  @override
  $GradeRowsTable createAlias(String alias) {
    return $GradeRowsTable(attachedDatabase, alias);
  }
}

class GradeRow extends DataClass implements Insertable<GradeRow> {
  final String id;
  final String semesterId;
  final String name;
  final double credit;
  final double score;
  final String kind;
  final bool demo;
  final String format;
  const GradeRow({
    required this.id,
    required this.semesterId,
    required this.name,
    required this.credit,
    required this.score,
    required this.kind,
    required this.demo,
    required this.format,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['semester_id'] = Variable<String>(semesterId);
    map['name'] = Variable<String>(name);
    map['credit'] = Variable<double>(credit);
    map['score'] = Variable<double>(score);
    map['kind'] = Variable<String>(kind);
    map['demo'] = Variable<bool>(demo);
    map['format'] = Variable<String>(format);
    return map;
  }

  GradeRowsCompanion toCompanion(bool nullToAbsent) {
    return GradeRowsCompanion(
      id: Value(id),
      semesterId: Value(semesterId),
      name: Value(name),
      credit: Value(credit),
      score: Value(score),
      kind: Value(kind),
      demo: Value(demo),
      format: Value(format),
    );
  }

  factory GradeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GradeRow(
      id: serializer.fromJson<String>(json['id']),
      semesterId: serializer.fromJson<String>(json['semesterId']),
      name: serializer.fromJson<String>(json['name']),
      credit: serializer.fromJson<double>(json['credit']),
      score: serializer.fromJson<double>(json['score']),
      kind: serializer.fromJson<String>(json['kind']),
      demo: serializer.fromJson<bool>(json['demo']),
      format: serializer.fromJson<String>(json['format']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'semesterId': serializer.toJson<String>(semesterId),
      'name': serializer.toJson<String>(name),
      'credit': serializer.toJson<double>(credit),
      'score': serializer.toJson<double>(score),
      'kind': serializer.toJson<String>(kind),
      'demo': serializer.toJson<bool>(demo),
      'format': serializer.toJson<String>(format),
    };
  }

  GradeRow copyWith({
    String? id,
    String? semesterId,
    String? name,
    double? credit,
    double? score,
    String? kind,
    bool? demo,
    String? format,
  }) => GradeRow(
    id: id ?? this.id,
    semesterId: semesterId ?? this.semesterId,
    name: name ?? this.name,
    credit: credit ?? this.credit,
    score: score ?? this.score,
    kind: kind ?? this.kind,
    demo: demo ?? this.demo,
    format: format ?? this.format,
  );
  GradeRow copyWithCompanion(GradeRowsCompanion data) {
    return GradeRow(
      id: data.id.present ? data.id.value : this.id,
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      name: data.name.present ? data.name.value : this.name,
      credit: data.credit.present ? data.credit.value : this.credit,
      score: data.score.present ? data.score.value : this.score,
      kind: data.kind.present ? data.kind.value : this.kind,
      demo: data.demo.present ? data.demo.value : this.demo,
      format: data.format.present ? data.format.value : this.format,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GradeRow(')
          ..write('id: $id, ')
          ..write('semesterId: $semesterId, ')
          ..write('name: $name, ')
          ..write('credit: $credit, ')
          ..write('score: $score, ')
          ..write('kind: $kind, ')
          ..write('demo: $demo, ')
          ..write('format: $format')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, semesterId, name, credit, score, kind, demo, format);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GradeRow &&
          other.id == this.id &&
          other.semesterId == this.semesterId &&
          other.name == this.name &&
          other.credit == this.credit &&
          other.score == this.score &&
          other.kind == this.kind &&
          other.demo == this.demo &&
          other.format == this.format);
}

class GradeRowsCompanion extends UpdateCompanion<GradeRow> {
  final Value<String> id;
  final Value<String> semesterId;
  final Value<String> name;
  final Value<double> credit;
  final Value<double> score;
  final Value<String> kind;
  final Value<bool> demo;
  final Value<String> format;
  final Value<int> rowid;
  const GradeRowsCompanion({
    this.id = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.name = const Value.absent(),
    this.credit = const Value.absent(),
    this.score = const Value.absent(),
    this.kind = const Value.absent(),
    this.demo = const Value.absent(),
    this.format = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GradeRowsCompanion.insert({
    required String id,
    required String semesterId,
    required String name,
    required double credit,
    required double score,
    required String kind,
    required bool demo,
    this.format = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       semesterId = Value(semesterId),
       name = Value(name),
       credit = Value(credit),
       score = Value(score),
       kind = Value(kind),
       demo = Value(demo);
  static Insertable<GradeRow> custom({
    Expression<String>? id,
    Expression<String>? semesterId,
    Expression<String>? name,
    Expression<double>? credit,
    Expression<double>? score,
    Expression<String>? kind,
    Expression<bool>? demo,
    Expression<String>? format,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (semesterId != null) 'semester_id': semesterId,
      if (name != null) 'name': name,
      if (credit != null) 'credit': credit,
      if (score != null) 'score': score,
      if (kind != null) 'kind': kind,
      if (demo != null) 'demo': demo,
      if (format != null) 'format': format,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GradeRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? semesterId,
    Value<String>? name,
    Value<double>? credit,
    Value<double>? score,
    Value<String>? kind,
    Value<bool>? demo,
    Value<String>? format,
    Value<int>? rowid,
  }) {
    return GradeRowsCompanion(
      id: id ?? this.id,
      semesterId: semesterId ?? this.semesterId,
      name: name ?? this.name,
      credit: credit ?? this.credit,
      score: score ?? this.score,
      kind: kind ?? this.kind,
      demo: demo ?? this.demo,
      format: format ?? this.format,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (semesterId.present) {
      map['semester_id'] = Variable<String>(semesterId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (credit.present) {
      map['credit'] = Variable<double>(credit.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (demo.present) {
      map['demo'] = Variable<bool>(demo.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GradeRowsCompanion(')
          ..write('id: $id, ')
          ..write('semesterId: $semesterId, ')
          ..write('name: $name, ')
          ..write('credit: $credit, ')
          ..write('score: $score, ')
          ..write('kind: $kind, ')
          ..write('demo: $demo, ')
          ..write('format: $format, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExamRowsTable extends ExamRows with TableInfo<$ExamRowsTable, ExamRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExamRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomMeta = const VerificationMeta('room');
  @override
  late final GeneratedColumn<String> room = GeneratedColumn<String>(
    'room',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, at, room];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exam_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExamRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('room')) {
      context.handle(
        _roomMeta,
        room.isAcceptableOrUnknown(data['room']!, _roomMeta),
      );
    } else if (isInserting) {
      context.missing(_roomMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExamRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExamRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
      room: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room'],
      )!,
    );
  }

  @override
  $ExamRowsTable createAlias(String alias) {
    return $ExamRowsTable(attachedDatabase, alias);
  }
}

class ExamRow extends DataClass implements Insertable<ExamRow> {
  final String id;
  final String name;
  final DateTime at;
  final String room;
  const ExamRow({
    required this.id,
    required this.name,
    required this.at,
    required this.room,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['at'] = Variable<DateTime>(at);
    map['room'] = Variable<String>(room);
    return map;
  }

  ExamRowsCompanion toCompanion(bool nullToAbsent) {
    return ExamRowsCompanion(
      id: Value(id),
      name: Value(name),
      at: Value(at),
      room: Value(room),
    );
  }

  factory ExamRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExamRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      at: serializer.fromJson<DateTime>(json['at']),
      room: serializer.fromJson<String>(json['room']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'at': serializer.toJson<DateTime>(at),
      'room': serializer.toJson<String>(room),
    };
  }

  ExamRow copyWith({String? id, String? name, DateTime? at, String? room}) =>
      ExamRow(
        id: id ?? this.id,
        name: name ?? this.name,
        at: at ?? this.at,
        room: room ?? this.room,
      );
  ExamRow copyWithCompanion(ExamRowsCompanion data) {
    return ExamRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      at: data.at.present ? data.at.value : this.at,
      room: data.room.present ? data.room.value : this.room,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExamRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('at: $at, ')
          ..write('room: $room')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, at, room);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExamRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.at == this.at &&
          other.room == this.room);
}

class ExamRowsCompanion extends UpdateCompanion<ExamRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> at;
  final Value<String> room;
  final Value<int> rowid;
  const ExamRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.at = const Value.absent(),
    this.room = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExamRowsCompanion.insert({
    required String id,
    required String name,
    required DateTime at,
    required String room,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       at = Value(at),
       room = Value(room);
  static Insertable<ExamRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? at,
    Expression<String>? room,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (at != null) 'at': at,
      if (room != null) 'room': room,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExamRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? at,
    Value<String>? room,
    Value<int>? rowid,
  }) {
    return ExamRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      at: at ?? this.at,
      room: room ?? this.room,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (room.present) {
      map['room'] = Variable<String>(room.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExamRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('at: $at, ')
          ..write('room: $room, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SchoolCacheRowsTable extends SchoolCacheRows
    with TableInfo<$SchoolCacheRowsTable, SchoolCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchoolCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, payload, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'school_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SchoolCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SchoolCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchoolCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      )!,
    );
  }

  @override
  $SchoolCacheRowsTable createAlias(String alias) {
    return $SchoolCacheRowsTable(attachedDatabase, alias);
  }
}

class SchoolCacheRow extends DataClass implements Insertable<SchoolCacheRow> {
  final String id;
  final String payload;
  final DateTime syncedAt;
  const SchoolCacheRow({
    required this.id,
    required this.payload,
    required this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  SchoolCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return SchoolCacheRowsCompanion(
      id: Value(id),
      payload: Value(payload),
      syncedAt: Value(syncedAt),
    );
  }

  factory SchoolCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchoolCacheRow(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  SchoolCacheRow copyWith({String? id, String? payload, DateTime? syncedAt}) =>
      SchoolCacheRow(
        id: id ?? this.id,
        payload: payload ?? this.payload,
        syncedAt: syncedAt ?? this.syncedAt,
      );
  SchoolCacheRow copyWithCompanion(SchoolCacheRowsCompanion data) {
    return SchoolCacheRow(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchoolCacheRow(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, payload, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchoolCacheRow &&
          other.id == this.id &&
          other.payload == this.payload &&
          other.syncedAt == this.syncedAt);
}

class SchoolCacheRowsCompanion extends UpdateCompanion<SchoolCacheRow> {
  final Value<String> id;
  final Value<String> payload;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const SchoolCacheRowsCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SchoolCacheRowsCompanion.insert({
    required String id,
    required String payload,
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload),
       syncedAt = Value(syncedAt);
  static Insertable<SchoolCacheRow> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SchoolCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? payload,
    Value<DateTime>? syncedAt,
    Value<int>? rowid,
  }) {
    return SchoolCacheRowsCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchoolCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SemesterRowsTable semesterRows = $SemesterRowsTable(this);
  late final $CourseRowsTable courseRows = $CourseRowsTable(this);
  late final $GradeRowsTable gradeRows = $GradeRowsTable(this);
  late final $ExamRowsTable examRows = $ExamRowsTable(this);
  late final $SchoolCacheRowsTable schoolCacheRows = $SchoolCacheRowsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    semesterRows,
    courseRows,
    gradeRows,
    examRows,
    schoolCacheRows,
  ];
}

typedef $$SemesterRowsTableCreateCompanionBuilder =
    SemesterRowsCompanion Function({
      required String id,
      required String name,
      required DateTime start,
      required int weeks,
      Value<int> rowid,
    });
typedef $$SemesterRowsTableUpdateCompanionBuilder =
    SemesterRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> start,
      Value<int> weeks,
      Value<int> rowid,
    });

final class $$SemesterRowsTableReferences
    extends BaseReferences<_$AppDatabase, $SemesterRowsTable, SemesterRow> {
  $$SemesterRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CourseRowsTable, List<CourseRow>>
  _courseRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.courseRows,
    aliasName: 'semester_rows__id__course_rows__semester_id',
  );

  $$CourseRowsTableProcessedTableManager get courseRowsRefs {
    final manager = $$CourseRowsTableTableManager(
      $_db,
      $_db.courseRows,
    ).filter((f) => f.semesterId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_courseRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$GradeRowsTable, List<GradeRow>>
  _gradeRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.gradeRows,
    aliasName: 'semester_rows__id__grade_rows__semester_id',
  );

  $$GradeRowsTableProcessedTableManager get gradeRowsRefs {
    final manager = $$GradeRowsTableTableManager(
      $_db,
      $_db.gradeRows,
    ).filter((f) => f.semesterId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_gradeRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SemesterRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SemesterRowsTable> {
  $$SemesterRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weeks => $composableBuilder(
    column: $table.weeks,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> courseRowsRefs(
    Expression<bool> Function($$CourseRowsTableFilterComposer f) f,
  ) {
    final $$CourseRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.courseRows,
      getReferencedColumn: (t) => t.semesterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRowsTableFilterComposer(
            $db: $db,
            $table: $db.courseRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> gradeRowsRefs(
    Expression<bool> Function($$GradeRowsTableFilterComposer f) f,
  ) {
    final $$GradeRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gradeRows,
      getReferencedColumn: (t) => t.semesterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeRowsTableFilterComposer(
            $db: $db,
            $table: $db.gradeRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SemesterRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SemesterRowsTable> {
  $$SemesterRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weeks => $composableBuilder(
    column: $table.weeks,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SemesterRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SemesterRowsTable> {
  $$SemesterRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get start =>
      $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<int> get weeks =>
      $composableBuilder(column: $table.weeks, builder: (column) => column);

  Expression<T> courseRowsRefs<T extends Object>(
    Expression<T> Function($$CourseRowsTableAnnotationComposer a) f,
  ) {
    final $$CourseRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.courseRows,
      getReferencedColumn: (t) => t.semesterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.courseRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> gradeRowsRefs<T extends Object>(
    Expression<T> Function($$GradeRowsTableAnnotationComposer a) f,
  ) {
    final $$GradeRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gradeRows,
      getReferencedColumn: (t) => t.semesterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GradeRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.gradeRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SemesterRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SemesterRowsTable,
          SemesterRow,
          $$SemesterRowsTableFilterComposer,
          $$SemesterRowsTableOrderingComposer,
          $$SemesterRowsTableAnnotationComposer,
          $$SemesterRowsTableCreateCompanionBuilder,
          $$SemesterRowsTableUpdateCompanionBuilder,
          (SemesterRow, $$SemesterRowsTableReferences),
          SemesterRow,
          PrefetchHooks Function({bool courseRowsRefs, bool gradeRowsRefs})
        > {
  $$SemesterRowsTableTableManager(_$AppDatabase db, $SemesterRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SemesterRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SemesterRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SemesterRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> start = const Value.absent(),
                Value<int> weeks = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SemesterRowsCompanion(
                id: id,
                name: name,
                start: start,
                weeks: weeks,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime start,
                required int weeks,
                Value<int> rowid = const Value.absent(),
              }) => SemesterRowsCompanion.insert(
                id: id,
                name: name,
                start: start,
                weeks: weeks,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SemesterRowsTable, SemesterRow>(table),
                  $$SemesterRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({courseRowsRefs = false, gradeRowsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (courseRowsRefs) db.courseRows,
                    if (gradeRowsRefs) db.gradeRows,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (courseRowsRefs)
                        await $_getPrefetchedDataByColumns<
                          SemesterRow,
                          $SemesterRowsTable,
                          CourseRow,
                          $CourseRowsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SemesterRowsTableReferences
                              ._courseRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SemesterRowsTableReferences(
                                db,
                                table,
                                p0,
                              ).courseRowsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'semester_id',
                          typedResults: items,
                        ),
                      if (gradeRowsRefs)
                        await $_getPrefetchedDataByColumns<
                          SemesterRow,
                          $SemesterRowsTable,
                          GradeRow,
                          $GradeRowsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SemesterRowsTableReferences
                              ._gradeRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SemesterRowsTableReferences(
                                db,
                                table,
                                p0,
                              ).gradeRowsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'semester_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SemesterRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SemesterRowsTable,
      SemesterRow,
      $$SemesterRowsTableFilterComposer,
      $$SemesterRowsTableOrderingComposer,
      $$SemesterRowsTableAnnotationComposer,
      $$SemesterRowsTableCreateCompanionBuilder,
      $$SemesterRowsTableUpdateCompanionBuilder,
      (SemesterRow, $$SemesterRowsTableReferences),
      SemesterRow,
      PrefetchHooks Function({bool courseRowsRefs, bool gradeRowsRefs})
    >;
typedef $$CourseRowsTableCreateCompanionBuilder = CourseRowsCompanion Function({
  required String id,
  required String semesterId,
  required String name,
  required String teacher,
  required String room,
  required int weekday,
  required int startMinute,
  required int endMinute,
  required String weeks,
  required int colorIndex,
  Value<int> rowid,
});
typedef $$CourseRowsTableUpdateCompanionBuilder = CourseRowsCompanion Function({
  Value<String> id,
  Value<String> semesterId,
  Value<String> name,
  Value<String> teacher,
  Value<String> room,
  Value<int> weekday,
  Value<int> startMinute,
  Value<int> endMinute,
  Value<String> weeks,
  Value<int> colorIndex,
  Value<int> rowid,
});

final class $$CourseRowsTableReferences
    extends BaseReferences<_$AppDatabase, $CourseRowsTable, CourseRow> {
  $$CourseRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SemesterRowsTable _semesterIdTable(_$AppDatabase db) => db
      .semesterRows
      .createAlias('course_rows__semester_id__semester_rows__id');

  $$SemesterRowsTableProcessedTableManager get semesterId {
    final $_column = $_itemColumn<String>('semester_id')!;

    final manager = $$SemesterRowsTableTableManager(
      $_db,
      $_db.semesterRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_semesterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CourseRowsTableFilterComposer
    extends Composer<_$AppDatabase, $CourseRowsTable> {
  $$CourseRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teacher => $composableBuilder(
    column: $table.teacher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get room => $composableBuilder(
    column: $table.room,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weeks => $composableBuilder(
    column: $table.weeks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => ColumnFilters(column),
  );

  $$SemesterRowsTableFilterComposer get semesterId {
    final $$SemesterRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.semesterId,
      referencedTable: $db.semesterRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemesterRowsTableFilterComposer(
            $db: $db,
            $table: $db.semesterRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CourseRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseRowsTable> {
  $$CourseRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teacher => $composableBuilder(
    column: $table.teacher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get room => $composableBuilder(
    column: $table.room,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weeks => $composableBuilder(
    column: $table.weeks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => ColumnOrderings(column),
  );

  $$SemesterRowsTableOrderingComposer get semesterId {
    final $$SemesterRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.semesterId,
      referencedTable: $db.semesterRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemesterRowsTableOrderingComposer(
            $db: $db,
            $table: $db.semesterRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CourseRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseRowsTable> {
  $$CourseRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get teacher =>
      $composableBuilder(column: $table.teacher, builder: (column) => column);

  GeneratedColumn<String> get room =>
      $composableBuilder(column: $table.room, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  GeneratedColumn<String> get weeks =>
      $composableBuilder(column: $table.weeks, builder: (column) => column);

  GeneratedColumn<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => column,
  );

  $$SemesterRowsTableAnnotationComposer get semesterId {
    final $$SemesterRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.semesterId,
      referencedTable: $db.semesterRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemesterRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.semesterRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CourseRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CourseRowsTable,
          CourseRow,
          $$CourseRowsTableFilterComposer,
          $$CourseRowsTableOrderingComposer,
          $$CourseRowsTableAnnotationComposer,
          $$CourseRowsTableCreateCompanionBuilder,
          $$CourseRowsTableUpdateCompanionBuilder,
          (CourseRow, $$CourseRowsTableReferences),
          CourseRow,
          PrefetchHooks Function({bool semesterId})
        > {
  $$CourseRowsTableTableManager(_$AppDatabase db, $CourseRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> semesterId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> teacher = const Value.absent(),
                Value<String> room = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<int> startMinute = const Value.absent(),
                Value<int> endMinute = const Value.absent(),
                Value<String> weeks = const Value.absent(),
                Value<int> colorIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CourseRowsCompanion(
                id: id,
                semesterId: semesterId,
                name: name,
                teacher: teacher,
                room: room,
                weekday: weekday,
                startMinute: startMinute,
                endMinute: endMinute,
                weeks: weeks,
                colorIndex: colorIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String semesterId,
                required String name,
                required String teacher,
                required String room,
                required int weekday,
                required int startMinute,
                required int endMinute,
                required String weeks,
                required int colorIndex,
                Value<int> rowid = const Value.absent(),
              }) => CourseRowsCompanion.insert(
                id: id,
                semesterId: semesterId,
                name: name,
                teacher: teacher,
                room: room,
                weekday: weekday,
                startMinute: startMinute,
                endMinute: endMinute,
                weeks: weeks,
                colorIndex: colorIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CourseRowsTable, CourseRow>(table),
                  $$CourseRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({semesterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (semesterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.semesterId,
                        referencedTable: $$CourseRowsTableReferences
                            ._semesterIdTable(db),
                        referencedColumn: $$CourseRowsTableReferences
                            ._semesterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CourseRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CourseRowsTable,
      CourseRow,
      $$CourseRowsTableFilterComposer,
      $$CourseRowsTableOrderingComposer,
      $$CourseRowsTableAnnotationComposer,
      $$CourseRowsTableCreateCompanionBuilder,
      $$CourseRowsTableUpdateCompanionBuilder,
      (CourseRow, $$CourseRowsTableReferences),
      CourseRow,
      PrefetchHooks Function({bool semesterId})
    >;
typedef $$GradeRowsTableCreateCompanionBuilder = GradeRowsCompanion Function({
  required String id,
  required String semesterId,
  required String name,
  required double credit,
  required double score,
  required String kind,
  required bool demo,
  Value<String> format,
  Value<int> rowid,
});
typedef $$GradeRowsTableUpdateCompanionBuilder = GradeRowsCompanion Function({
  Value<String> id,
  Value<String> semesterId,
  Value<String> name,
  Value<double> credit,
  Value<double> score,
  Value<String> kind,
  Value<bool> demo,
  Value<String> format,
  Value<int> rowid,
});

final class $$GradeRowsTableReferences
    extends BaseReferences<_$AppDatabase, $GradeRowsTable, GradeRow> {
  $$GradeRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SemesterRowsTable _semesterIdTable(_$AppDatabase db) =>
      db.semesterRows.createAlias('grade_rows__semester_id__semester_rows__id');

  $$SemesterRowsTableProcessedTableManager get semesterId {
    final $_column = $_itemColumn<String>('semester_id')!;

    final manager = $$SemesterRowsTableTableManager(
      $_db,
      $_db.semesterRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_semesterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GradeRowsTableFilterComposer
    extends Composer<_$AppDatabase, $GradeRowsTable> {
  $$GradeRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get credit => $composableBuilder(
    column: $table.credit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get demo => $composableBuilder(
    column: $table.demo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  $$SemesterRowsTableFilterComposer get semesterId {
    final $$SemesterRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.semesterId,
      referencedTable: $db.semesterRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemesterRowsTableFilterComposer(
            $db: $db,
            $table: $db.semesterRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GradeRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $GradeRowsTable> {
  $$GradeRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get credit => $composableBuilder(
    column: $table.credit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get demo => $composableBuilder(
    column: $table.demo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  $$SemesterRowsTableOrderingComposer get semesterId {
    final $$SemesterRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.semesterId,
      referencedTable: $db.semesterRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemesterRowsTableOrderingComposer(
            $db: $db,
            $table: $db.semesterRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GradeRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GradeRowsTable> {
  $$GradeRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get credit =>
      $composableBuilder(column: $table.credit, builder: (column) => column);

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get demo =>
      $composableBuilder(column: $table.demo, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  $$SemesterRowsTableAnnotationComposer get semesterId {
    final $$SemesterRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.semesterId,
      referencedTable: $db.semesterRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemesterRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.semesterRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GradeRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GradeRowsTable,
          GradeRow,
          $$GradeRowsTableFilterComposer,
          $$GradeRowsTableOrderingComposer,
          $$GradeRowsTableAnnotationComposer,
          $$GradeRowsTableCreateCompanionBuilder,
          $$GradeRowsTableUpdateCompanionBuilder,
          (GradeRow, $$GradeRowsTableReferences),
          GradeRow,
          PrefetchHooks Function({bool semesterId})
        > {
  $$GradeRowsTableTableManager(_$AppDatabase db, $GradeRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GradeRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GradeRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GradeRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> semesterId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> credit = const Value.absent(),
                Value<double> score = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> demo = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GradeRowsCompanion(
                id: id,
                semesterId: semesterId,
                name: name,
                credit: credit,
                score: score,
                kind: kind,
                demo: demo,
                format: format,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String semesterId,
                required String name,
                required double credit,
                required double score,
                required String kind,
                required bool demo,
                Value<String> format = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GradeRowsCompanion.insert(
                id: id,
                semesterId: semesterId,
                name: name,
                credit: credit,
                score: score,
                kind: kind,
                demo: demo,
                format: format,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GradeRowsTable, GradeRow>(table),
                  $$GradeRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({semesterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (semesterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.semesterId,
                        referencedTable: $$GradeRowsTableReferences
                            ._semesterIdTable(db),
                        referencedColumn: $$GradeRowsTableReferences
                            ._semesterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GradeRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GradeRowsTable,
      GradeRow,
      $$GradeRowsTableFilterComposer,
      $$GradeRowsTableOrderingComposer,
      $$GradeRowsTableAnnotationComposer,
      $$GradeRowsTableCreateCompanionBuilder,
      $$GradeRowsTableUpdateCompanionBuilder,
      (GradeRow, $$GradeRowsTableReferences),
      GradeRow,
      PrefetchHooks Function({bool semesterId})
    >;
typedef $$ExamRowsTableCreateCompanionBuilder = ExamRowsCompanion Function({
  required String id,
  required String name,
  required DateTime at,
  required String room,
  Value<int> rowid,
});
typedef $$ExamRowsTableUpdateCompanionBuilder = ExamRowsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<DateTime> at,
  Value<String> room,
  Value<int> rowid,
});

class $$ExamRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ExamRowsTable> {
  $$ExamRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get room => $composableBuilder(
    column: $table.room,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExamRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExamRowsTable> {
  $$ExamRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get room => $composableBuilder(
    column: $table.room,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExamRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExamRowsTable> {
  $$ExamRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<String> get room =>
      $composableBuilder(column: $table.room, builder: (column) => column);
}

class $$ExamRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExamRowsTable,
          ExamRow,
          $$ExamRowsTableFilterComposer,
          $$ExamRowsTableOrderingComposer,
          $$ExamRowsTableAnnotationComposer,
          $$ExamRowsTableCreateCompanionBuilder,
          $$ExamRowsTableUpdateCompanionBuilder,
          (ExamRow, BaseReferences<_$AppDatabase, $ExamRowsTable, ExamRow>),
          ExamRow,
          PrefetchHooks Function()
        > {
  $$ExamRowsTableTableManager(_$AppDatabase db, $ExamRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExamRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExamRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExamRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<String> room = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExamRowsCompanion(
                id: id,
                name: name,
                at: at,
                room: room,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime at,
                required String room,
                Value<int> rowid = const Value.absent(),
              }) => ExamRowsCompanion.insert(
                id: id,
                name: name,
                at: at,
                room: room,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExamRowsTable, ExamRow>(table),
                  BaseReferences<_$AppDatabase, $ExamRowsTable, ExamRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExamRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExamRowsTable,
      ExamRow,
      $$ExamRowsTableFilterComposer,
      $$ExamRowsTableOrderingComposer,
      $$ExamRowsTableAnnotationComposer,
      $$ExamRowsTableCreateCompanionBuilder,
      $$ExamRowsTableUpdateCompanionBuilder,
      (ExamRow, BaseReferences<_$AppDatabase, $ExamRowsTable, ExamRow>),
      ExamRow,
      PrefetchHooks Function()
    >;
typedef $$SchoolCacheRowsTableCreateCompanionBuilder =
    SchoolCacheRowsCompanion Function({
      required String id,
      required String payload,
      required DateTime syncedAt,
      Value<int> rowid,
    });
typedef $$SchoolCacheRowsTableUpdateCompanionBuilder =
    SchoolCacheRowsCompanion Function({
      Value<String> id,
      Value<String> payload,
      Value<DateTime> syncedAt,
      Value<int> rowid,
    });

class $$SchoolCacheRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SchoolCacheRowsTable> {
  $$SchoolCacheRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SchoolCacheRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SchoolCacheRowsTable> {
  $$SchoolCacheRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SchoolCacheRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchoolCacheRowsTable> {
  $$SchoolCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$SchoolCacheRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SchoolCacheRowsTable,
          SchoolCacheRow,
          $$SchoolCacheRowsTableFilterComposer,
          $$SchoolCacheRowsTableOrderingComposer,
          $$SchoolCacheRowsTableAnnotationComposer,
          $$SchoolCacheRowsTableCreateCompanionBuilder,
          $$SchoolCacheRowsTableUpdateCompanionBuilder,
          (
            SchoolCacheRow,
            BaseReferences<
              _$AppDatabase,
              $SchoolCacheRowsTable,
              SchoolCacheRow
            >,
          ),
          SchoolCacheRow,
          PrefetchHooks Function()
        > {
  $$SchoolCacheRowsTableTableManager(
    _$AppDatabase db,
    $SchoolCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchoolCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchoolCacheRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchoolCacheRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchoolCacheRowsCompanion(
                id: id,
                payload: payload,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payload,
                required DateTime syncedAt,
                Value<int> rowid = const Value.absent(),
              }) => SchoolCacheRowsCompanion.insert(
                id: id,
                payload: payload,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SchoolCacheRowsTable, SchoolCacheRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SchoolCacheRowsTable,
                    SchoolCacheRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SchoolCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SchoolCacheRowsTable,
      SchoolCacheRow,
      $$SchoolCacheRowsTableFilterComposer,
      $$SchoolCacheRowsTableOrderingComposer,
      $$SchoolCacheRowsTableAnnotationComposer,
      $$SchoolCacheRowsTableCreateCompanionBuilder,
      $$SchoolCacheRowsTableUpdateCompanionBuilder,
      (
        SchoolCacheRow,
        BaseReferences<_$AppDatabase, $SchoolCacheRowsTable, SchoolCacheRow>,
      ),
      SchoolCacheRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SemesterRowsTableTableManager get semesterRows =>
      $$SemesterRowsTableTableManager(_db, _db.semesterRows);
  $$CourseRowsTableTableManager get courseRows =>
      $$CourseRowsTableTableManager(_db, _db.courseRows);
  $$GradeRowsTableTableManager get gradeRows =>
      $$GradeRowsTableTableManager(_db, _db.gradeRows);
  $$ExamRowsTableTableManager get examRows =>
      $$ExamRowsTableTableManager(_db, _db.examRows);
  $$SchoolCacheRowsTableTableManager get schoolCacheRows =>
      $$SchoolCacheRowsTableTableManager(_db, _db.schoolCacheRows);
}
