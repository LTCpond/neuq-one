import 'campus_clock.dart';

/// Published NEUQ teaching intervals, indexed by period number minus one.
const neuqPeriods = [
  (start: 480, end: 525),
  (start: 530, end: 575),
  (start: 605, end: 650),
  (start: 655, end: 700),
  (start: 840, end: 885),
  (start: 890, end: 935),
  (start: 965, end: 1010),
  (start: 1015, end: 1060),
  (start: 1120, end: 1165),
  (start: 1170, end: 1215),
  (start: 1225, end: 1270),
  (start: 1275, end: 1320),
];

String periodLabel(int index) {
  final period = neuqPeriods[index - 1];
  return '第 $index 节 · ${clockLabel(period.start)}–${clockLabel(period.end)}';
}

int? periodAtStart(int minute) {
  final index = neuqPeriods.indexWhere((period) => period.start == minute);
  return index < 0 ? null : index + 1;
}

int? periodAtEnd(int minute) {
  final index = neuqPeriods.indexWhere((period) => period.end == minute);
  return index < 0 ? null : index + 1;
}
