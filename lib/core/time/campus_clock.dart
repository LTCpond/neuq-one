const campusOffset = Duration(hours: 8);

DateTime campusNow() => DateTime.now().toUtc().add(campusOffset);

DateTime calendarDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

DateTime mondayOf(DateTime date) =>
    calendarDate(date).subtract(Duration(days: date.weekday - 1));

String shortDate(DateTime date) => '${date.month}月${date.day}日';

String weekdayLabel(int weekday) => '周${'一二三四五六日'[weekday - 1]}';

String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
