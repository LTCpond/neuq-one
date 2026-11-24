import '../../features/grades/domain/grades.dart';
import '../../features/services/domain/classrooms.dart';
import '../../features/timetable/domain/timetable.dart';

abstract interface class SchoolDataSource
    implements
        SchoolTimetableDataSource,
        SchoolGradesDataSource,
        SchoolClassroomsDataSource {}
