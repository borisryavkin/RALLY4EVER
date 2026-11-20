import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/typography.dart';

export '../theme/colors.dart';

ThemeData rallyTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Inter',
  scaffoldBackgroundColor: cream,
  colorScheme: const ColorScheme.light(
    primary: coral,
    secondary: navy,
    surface: Colors.white,
    onSurface: navy,
    onPrimary: Colors.white,
  ),
  textTheme: const TextTheme(
    headlineLarge: AppTypography.display,
    headlineMedium: AppTypography.h1,
    titleLarge: AppTypography.h2,
    titleMedium: TextStyle(fontWeight: FontWeight.w700, color: navy),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: slate),
    bodySmall: TextStyle(fontSize: 12, height: 1.45, color: slate),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffe4dfdd)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      textStyle: AppTypography.button,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: navy,
      minimumSize: const Size.fromHeight(44),
      side: const BorderSide(color: Color(0xffd9d6df)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: cream,
    foregroundColor: navy,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: AppTypography.h2,
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xffffe3e2),
    height: 72,
  ),
  dividerTheme: const DividerThemeData(color: Color(0xffe5dfdc)),
);

const _weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Thu 19 Nov, 1:12 pm" instead of a `DateTime`'s own `toString()`
/// ("2026-11-19 13:12:33.702+1100") -- the one place admin/coach screens
/// format a moment for display. Always in the device's local time.
String friendlyDateTime(DateTime value) {
  final local = value.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'pm' : 'am';
  return '${_weekdayNames[local.weekday - 1]} ${local.day} '
      '${_monthNames[local.month - 1]}, $hour12:$minute$period';
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = 16,
  });
  final Widget child;
  final Color color;
  final double padding;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: EdgeInsets.all(padding),
      // Every brand background colour except navy itself needs navy text to
      // meet AA contrast (e.g. plain slate body text on a pink panel is
      // only ~4.07:1); default to that here so no caller has to remember to
      // override text colour per panel background.
      child: DefaultTextStyle.merge(
        style: TextStyle(color: color == navy ? Colors.white : navy),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.dark = false, this.muted = false});
  final String label;
  final bool dark;
  // A session that's full, closed, cancelled or over -- a visibly
  // different (grey, not green) pill from "spots available".
  final bool muted;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: dark
          ? navy
          : muted
          ? const Color(0xffe4dfdd)
          : const Color(0xffe1f2e7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: dark ? Colors.white : muted ? slate : navy,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
