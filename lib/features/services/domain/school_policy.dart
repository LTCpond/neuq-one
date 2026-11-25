const _schoolName = '东北大学秦皇岛分校';

class SchoolPolicy {
  const SchoolPolicy({
    required this.id,
    required this.title,
    required this.category,
    required this.sha256,
  });

  final String id;
  final String title;
  final String category;
  final String sha256;

  String get shortTitle => title.startsWith(_schoolName)
      ? title.substring(_schoolName.length)
      : title;
}
