import 'package:material_ui/material_ui.dart';

const _lightCourseColors = [
  (Color(0xFFB6CDFF), Color(0xFF204696)),
  (Color(0xFFDDC6FA), Color(0xFF69419F)),
  (Color(0xFFB5E5D2), Color(0xFF216C51)),
  (Color(0xFFFFDA9D), Color(0xFF75470F)),
  (Color(0xFFF5BCCA), Color(0xFF963F58)),
  (Color(0xFFBAE4EF), Color(0xFF236C84)),
];

const _darkCourseColors = [
  (Color(0xFF3459CE), Color(0xFFE4ECFF)),
  (Color(0xFF6D509D), Color(0xFFF0E7FF)),
  (Color(0xFF235E50), Color(0xFFC8F3E2)),
  (Color(0xFF775428), Color(0xFFFFE5BB)),
  (Color(0xFF82475D), Color(0xFFFFDFE8)),
  (Color(0xFF245A71), Color(0xFFC6EEFA)),
];

List<(Color, Color)> coursePalette(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? _darkCourseColors
    : _lightCourseColors;

(Color, Color) courseBlockColors(BuildContext context, int index) {
  final palette = coursePalette(context);
  return palette[index % palette.length];
}
