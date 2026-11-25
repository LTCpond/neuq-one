import 'package:material_ui/material_ui.dart';

const campusBlue = Color(0xFF2459E0);
const campusLime = Color(0xFFD6F36C);

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF111720) : const Color(0xFFF4F6FA);
  final surface = dark ? const Color(0xFF202A38) : Colors.white;
  final ink = dark ? const Color(0xFFE9EFFA) : const Color(0xFF18243B);
  final muted = dark ? const Color(0xFFA7B4C7) : const Color(0xFF65748B);
  final line = dark ? const Color(0xFF344154) : const Color(0xFFE5E9F1);
  final pale = dark ? const Color(0xFF293F68) : const Color(0xFFE0E8FF);
  final blue = dark ? const Color(0xFF9AB5FF) : campusBlue;
  final colors =
      ColorScheme.fromSeed(
        seedColor: campusBlue,
        brightness: brightness,
      ).copyWith(
        primary: blue,
        primaryContainer: pale,
        onPrimaryContainer: dark
            ? const Color(0xFFD5E2FF)
            : const Color(0xFF244595),
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: muted,
        outlineVariant: line,
        surfaceContainerLow: background,
        surfaceContainer: surface,
        surfaceContainerHigh: dark
            ? const Color(0xFF283444)
            : const Color(0xFFE3E8F1),
      );
  final base = ThemeData(
    colorScheme: colors,
    useMaterial3: true,
    fontFamily: 'Roboto',
    fontFamilyFallback: const [
      'Noto Sans SC',
      'Noto Sans CJK SC',
      'Microsoft YaHei',
    ],
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 58,
      labelPadding: const EdgeInsets.only(top: 2),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          height: 1.1,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: selected ? blue : muted,
        );
      }),
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 30,
        height: 1.17,
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
