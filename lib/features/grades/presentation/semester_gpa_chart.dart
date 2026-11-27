import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../timetable/domain/timetable.dart';

typedef SemesterGpaPoint = ({Semester semester, double? gpa});

class SemesterGpaChart extends StatelessWidget {
  const SemesterGpaChart({super.key, required this.points});

  final List<SemesterGpaPoint> points;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = [
      for (final point in points)
        if (point.gpa case final gpa? when gpa.isFinite) gpa,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '各学期 GPA 趋势',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (values.isEmpty)
              Text('暂无学期 GPA', style: TextStyle(color: colors.onSurfaceVariant))
            else
              _plot(context, values),
          ],
        ),
      ),
    );
  }

  Widget _plot(BuildContext context, List<double> values) {
    final colors = Theme.of(context).colorScheme;
    final lowest = values.reduce(math.min);
    final highest = values.reduce(math.max);
    final lower = math.max(0.0, ((lowest - .15) * 2).floorToDouble() / 2);
    final paddedUpper = ((highest + .15) * 2).ceilToDouble() / 2;
    final upper = math.max(
      lower + .5,
      highest <= 5 ? math.min(5.0, paddedUpper) : paddedUpper,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final tickHeight = textScaler.scale(10) * 1.2;
    final plotHeight = 94 + tickHeight;
    final axisStyle = TextStyle(
      color: colors.onSurfaceVariant,
      fontSize: 10,
      height: 1.2,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: plotHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final tick in [upper, (upper + lower) / 2, lower])
                Text(tick.toStringAsFixed(2), style: axisStyle),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(
                  constraints.maxWidth,
                  points.length * math.max(68.0, textScaler.scale(46)),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: plotHeight,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: tickHeight / 2),
                        child: CustomPaint(
                          painter: _TrendPainter(points, lower, upper, colors),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final point in points)
                          Expanded(child: _TermLabel(point: point)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TermLabel extends StatelessWidget {
  const _TermLabel({required this.point});

  static final _schoolTerm = RegExp(r'^(\d{4})-\d{2}(\d{2}) (春|秋)季学期$');

  final SemesterGpaPoint point;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final gpa = point.gpa;
    final value = gpa != null && gpa.isFinite ? gpa : null;
    final name = point.semester.name;
    final compactName = name.replaceFirstMapped(
      _schoolTerm,
      (match) => '${match[1]}–${match[2]} ${match[3]}',
    );
    final description =
        '$name · ${value == null ? '暂无 GPA' : 'GPA ${value.toStringAsFixed(4)}'}';
    return Tooltip(
      message: description,
      triggerMode: TooltipTriggerMode.tap,
      excludeFromSemantics: true,
      child: Semantics(
        label: description,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            children: [
              Text(
                value?.toStringAsFixed(2) ?? '—',
                style: TextStyle(
                  color: value == null
                      ? colors.onSurfaceVariant
                      : colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                compactName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.points, this.lower, this.upper, this.colors);

  final List<SemesterGpaPoint> points;
  final double lower;
  final double upper;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = colors.outlineVariant;
    for (final y in [0.0, size.height / 2, size.height]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final path = Path();
    final dots = <Offset>[];
    final spacing = size.width / points.length;
    var connected = false;
    for (final (index, point) in points.indexed) {
      final value = point.gpa;
      if (value == null || !value.isFinite) {
        connected = false;
        continue;
      }
      final x = (index + .5) * spacing;
      final y = size.height * (upper - value) / (upper - lower);
      if (connected) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
      }
      connected = true;
      dots.add(Offset(x, y));
    }
    final line = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
    final fill = Paint()..color = colors.primary;
    final ring = Paint()..color = colors.surface;
    for (final dot in dots) {
      canvas.drawCircle(dot, 5, ring);
      canvas.drawCircle(dot, 3.5, fill);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      points != oldDelegate.points ||
      lower != oldDelegate.lower ||
      upper != oldDelegate.upper ||
      colors != oldDelegate.colors;
}
