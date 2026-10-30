import 'package:flutter/material.dart';

export 'ui.dart';

/// Palette from the Figma reference: cream paper, deep emerald actions, antique gold accents.
class Palette {
  static const background = Color(0xfff7f1e6);
  static const surface = Color(0xfffffcf6);
  static const green = Color(0xff2f5b3c);
  static const greenDark = Color(0xff234630);
  static const greenDeep = Color(0xff143a26);
  static const greenSoft = Color(0xffe4ecdc);
  static const gold = Color(0xffc9963b);
  static const goldSoft = Color(0xfff6e7c9);
  static const ink = Color(0xff2b2a26);
  static const muted = Color(0xff6f6a60);
  static const border = Color(0xffe6dcc9);
  static const orange = Color(0xffd9822b);
  static const shadow = Color(0xff5c4522);
}

/// Serif headings: Noto Serif (Latin) with Noto Serif Devanagari, bundled as subsets in assets/fonts.
TextStyle heading(
  double size, {
  Color color = Palette.ink,
  List<Shadow>? shadows,
}) => TextStyle(
  fontFamily: 'KundliSerif',
  fontFamilyFallback: const ['KundliSerifDeva'],
  fontWeight: FontWeight.w600,
  fontSize: size,
  color: color,
  height: 1.2,
  shadows: shadows,
);

/// Screens rise gently and fade in, on every platform.
class SoftRiseTransitions extends PageTransitionsBuilder {
  const SoftRiseTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

ThemeData kundliTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.green,
    primary: Palette.green,
    surface: Palette.background,
  );
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Palette.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'KundliSans',
    fontFamilyFallback: const ['KundliSansDeva'],
    scaffoldBackgroundColor: Palette.background,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SoftRiseTransitions(),
        TargetPlatform.iOS: SoftRiseTransitions(),
        TargetPlatform.linux: SoftRiseTransitions(),
        TargetPlatform.macOS: SoftRiseTransitions(),
        TargetPlatform.windows: SoftRiseTransitions(),
      },
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Palette.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: Palette.ink,
      titleTextStyle: heading(19),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.green,
        textStyle: const TextStyle(
          fontFamily: 'KundliSans',
          fontFamilyFallback: ['KundliSansDeva'],
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.greenDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.gold,
      linearTrackColor: Color(0xffeee4d0),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: const BorderSide(color: Palette.gold, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: const TextStyle(color: Color(0xffa39d90)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.green : null,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Palette.green
            : const Color(0xffcfc8ba),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerColor: Colors.transparent,
  );
}
