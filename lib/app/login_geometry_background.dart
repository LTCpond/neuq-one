import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import 'login_motion.dart';

class LoginGeometryBackground extends StatelessWidget {
  const LoginGeometryBackground({
    super.key,
    required this.entrance,
    required this.footerHeight,
  });

  final Animation<double> entrance;
  final double footerHeight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LoginGeometryPainter(
            entrance: entrance,
            footerHeight: footerHeight,
            blue: dark ? const Color(0xFF234497) : campusBlue,
            sky: dark ? const Color(0xFF287CA6) : const Color(0xFF38BDF8),
            indigo: dark ? const Color(0xFF6474AE) : const Color(0xFFA5B4FC),
          ),
        ),
      ),
    );
  }
}

class _LoginGeometryPainter extends CustomPainter {
  _LoginGeometryPainter({
    required this.entrance,
    required this.footerHeight,
    required this.blue,
    required this.sky,
    required this.indigo,
  }) : _mainCircle = loginPhase(entrance, 0, 400, curve: Curves.easeOutQuart),
       _skyCircle = loginPhase(entrance, 80, 500),
       _mainTriangle = loginPhase(entrance, 350, 730),
       _indigoTriangle = loginPhase(entrance, 410, 750),
       _lines = [
         for (var index = 0; index < 5; index++)
           loginPhase(entrance, 400 + index * 32, 672 + index * 32),
       ],
       super(repaint: entrance);

  final Animation<double> entrance;
  final double footerHeight;
  final Color blue;
  final Color sky;
  final Color indigo;
  final Animation<double> _mainCircle;
  final Animation<double> _skyCircle;
  final Animation<double> _mainTriangle;
  final Animation<double> _indigoTriangle;
  final List<Animation<double>> _lines;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(240.0, math.min(size.width * .44, size.height * .26));
    final right = size.width;
    final bottom = size.height;
    final paint = Paint();
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    void circle(Offset center, double radius, Color color, double progress) {
      final travel = unit * (1 - progress);
      canvas.drawCircle(
        center + Offset(travel, -travel),
        radius,
        paint..color = color,
      );
    }

    circle(
      Offset(right - unit * .07, unit * .04),
      unit * .67,
      blue,
      _mainCircle.value,
    );
    circle(
      Offset(right - unit * .66, unit * .29),
      unit * .27,
      sky,
      _skyCircle.value,
    );

    if (footerHeight > 0) {
      final base = math.min(right * .46, footerHeight * 2.55);

      void triangle(
        double start,
        double peak,
        double height,
        Color color,
        double progress,
      ) {
        final travel = footerHeight * (1 - progress);
        final path = Path()
          ..moveTo(start + travel, bottom + travel)
          ..lineTo(peak + travel, bottom - height + travel)
          ..lineTo(right + base * .3 + travel, bottom + travel)
          ..close();
        canvas.drawPath(path, paint..color = color);
      }

      triangle(
        right - base * 1.13,
        right - base * .28,
        footerHeight * .70,
        indigo,
        _indigoTriangle.value,
      );
      triangle(
        right - base * .77,
        right - base * .11,
        footerHeight,
        blue,
        _mainTriangle.value,
      );

      const lengths = [1.0, .84, .94, .70, .79];
      final step = footerHeight * .16;
      final length = math.min(right * .32, footerHeight * 1.55);
      for (var i = 0; i < lengths.length; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            bottom - step * (5 - i),
            length * lengths[i] * _lines[i].value,
            step * .44,
          ),
          paint..color = i.isEven ? blue : sky,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LoginGeometryPainter oldDelegate) =>
      oldDelegate.entrance != entrance ||
      oldDelegate.footerHeight != footerHeight ||
      oldDelegate.blue != blue ||
      oldDelegate.sky != sky ||
      oldDelegate.indigo != indigo;
}
