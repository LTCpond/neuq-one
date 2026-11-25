import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/features/services/data/employment_feed.dart';

void main() {
  test(
    'reads the two official homepage lists and keeps their detail links',
    () {
      const page = '''
<ul><li><div class="cont">
<div class="new-time"><p>11月</p><p>25日</p></div>
<div class="content-info"><p><a class="title" href="/teachin/view/id/100">示例宣讲会</a>
<span class="time">14:00-15:30</span></p><span class="address">工学馆112</span></div>
</div></li></ul>
<ul><li><div class="cont">
<div class="new-time"><p>11月</p><p>26日</p></div>
<div class="content-info"><p><a class="title" href="/jobfair/view/id/201">
<span class="status-text">已举办</span>示例招聘会</a></p>
<span class="address">大学会馆</span></div>
</div></li></ul>
''';
      final events = readEmploymentFeed(page);
      expect(events.map((event) => event.kind), EmploymentKind.values);
      expect(events.first.when, '11月25日 · 14:00-15:30');
      expect(events.first.where, '工学馆112');
      expect(events.last.title, '示例招聘会');
      expect(events.last.when, '11月26日 · 已举办');
      expect(
        events.last.url.toString(),
        'https://job.neuq.edu.cn/jobfair/view/id/201',
      );
      expect(
        () => readEmploymentFeed(
          page.replaceFirst(
            '/jobfair/view',
            'https://other.example/jobfair/view',
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
