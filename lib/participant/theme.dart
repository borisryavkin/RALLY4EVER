import 'package:flutter/material.dart';

const navy = Color(0xff001751);
const coral = Color(0xffff4b4c);
const pink = Color(0xffffb7b7);
const cream = Color(0xfff2eeeb);
const slate = Color(0xff4d5b80);
const grey = Color(0xff929292);

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
    headlineLarge: TextStyle(
      fontFamily: 'Figtree',
      fontSize: 34,
      height: 1.05,
      fontWeight: FontWeight.w800,
      color: navy,
      letterSpacing: -1,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Figtree',
      fontSize: 27,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: navy,
      letterSpacing: -.6,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Figtree',
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: navy,
    ),
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
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
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
    titleTextStyle: TextStyle(
      fontFamily: 'Figtree',
      fontWeight: FontWeight.w700,
      fontSize: 20,
      color: navy,
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xffffe3e2),
    height: 72,
  ),
  dividerTheme: const DividerThemeData(color: Color(0xffe5dfdc)),
);

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
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.dark = false});
  final String label;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: dark ? navy : const Color(0xffe1f2e7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: dark ? Colors.white : navy,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
