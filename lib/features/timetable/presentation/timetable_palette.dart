import 'package:material_ui/material_ui.dart';

const _lightCourseColors = [
  (Color(0xFFB6CDFF), Color(0xFF204696)),
  (Color(0xFFDDC6FA), Color(0xFF69419F)),
  (Color(0xFFB5E5D2), Color(0xFF216C51)),
  (Color(0xFFFFDA9D), Color(0xFF75470F)),
  (Color(0xFFF5BCCA), Color(0xFF963F58)),
  (Color(0xFFBAE4EF), Color(0xFF236C84)),
  (Color(0xFFE8EDB5), Color(0xFF596321)),
  (Color(0xFFC4C7F3), Color(0xFF454B91)),
  (Color(0xFFE7D4BD), Color(0xFF795435)),
  (Color(0xFFB9DBF8), Color(0xFF245C90)),
  (Color(0xFFDCC5E2), Color(0xFF774681)),
  (Color(0xFFBCE0E0), Color(0xFF286865)),
];

const _darkCourseColors = [
  (Color(0xFF3459CE), Color(0xFFE4ECFF)),
  (Color(0xFF6D509D), Color(0xFFF0E7FF)),
  (Color(0xFF235E50), Color(0xFFC8F3E2)),
  (Color(0xFF775428), Color(0xFFFFE5BB)),
  (Color(0xFF82475D), Color(0xFFFFDFE8)),
  (Color(0xFF245A71), Color(0xFFC6EEFA)),
  (Color(0xFF4F552C), Color(0xFFE7EDB9)),
  (Color(0xFF454C80), Color(0xFFE1E4FF)),
  (Color(0xFF614C3A), Color(0xFFF7E2CC)),
  (Color(0xFF315779), Color(0xFFD8EDFF)),
  (Color(0xFF60466D), Color(0xFFF4DEF8)),
  (Color(0xFF325952), Color(0xFFD4F1EB)),
];

typedef ExamPalette = ({Color background, Color text, Color border});

ExamPalette examPalette(Brightness brightness, {bool finished = false}) {
  if (brightness == Brightness.dark) {
    return (
      background: finished ? const Color(0xFF493C3B) : const Color(0xFF783934),
      text: finished ? const Color(0xFFE1C8C4) : const Color(0xFFFFDAD4),
      border: const Color(0xFFFFB4AA),
    );
  }
  return (
    background: finished ? const Color(0xFFF2E9E7) : const Color(0xFFFBE2DF),
    text: finished ? const Color(0xFF78605C) : const Color(0xFFA52D28),
    border: const Color(0xFFA52D28),
  );
}

List<(Color, Color)> coursePalette(BuildContext context) =>
    _palette(Theme.of(context).brightness);

List<(Color, Color)> _palette(Brightness brightness) =>
    brightness == Brightness.dark ? _darkCourseColors : _lightCourseColors;

List<Color> coursePaletteColors(Brightness brightness, int index) {
  final palette = _palette(brightness);
  final (background, foreground) = palette[index % palette.length];
  return [background, foreground];
}

(Color, Color) courseBlockColors(BuildContext context, int index) {
  final palette = coursePalette(context);
  return palette[index % palette.length];
}
