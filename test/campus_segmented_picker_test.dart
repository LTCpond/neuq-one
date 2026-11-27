import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/core/widgets/campus_segmented_picker.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'segments share width and use the cobalt selection in $brightness',
      (tester) async {
        var selected = '成绩';
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => CampusSegmentedPicker<String>(
                  values: const ['成绩', '培养方案', '考试安排'],
                  selected: selected,
                  labelOf: (value) => value,
                  onChanged: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        );

        final widths = [
          for (final label in ['成绩', '培养方案', '考试安排'])
            tester
                .getSize(
                  find
                      .ancestor(
                        of: find.text(label),
                        matching: find.byType(InkWell),
                      )
                      .first,
                )
                .width,
        ];
        expect(widths[0], closeTo(widths[1], .01));
        expect(widths[1], closeTo(widths[2], .01));

        Ink inkFor(String label) => tester.widget<Ink>(
          find.ancestor(of: find.text(label), matching: find.byType(Ink)).first,
        );
        Color? colorFor(String label) =>
            (inkFor(label).decoration as BoxDecoration).color;

        expect(colorFor('成绩'), campusBlue);
        expect(colorFor('培养方案'), Colors.transparent);
        expect(tester.widget<Text>(find.text('成绩')).style?.color, Colors.white);
        expect(
          tester.widget<Text>(find.text('培养方案')).style?.color,
          Theme.of(tester.element(find.text('培养方案')))
              .colorScheme
              .onSurfaceVariant,
        );

        await tester.tap(find.text('考试安排'));
        await tester.pumpAndSettle();
        expect(colorFor('考试安排'), campusBlue);
        expect(colorFor('成绩'), Colors.transparent);
        expect(
          tester.widget<Text>(find.text('考试安排')).style?.color,
          Colors.white,
        );
      },
    );
  }
}
