import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Palette and shared widgets from the Figma reference: cream paper, deep green actions, gold accents.
class Palette {
  static const background = Color(0xfff7f1e6);
  static const surface = Color(0xfffffcf6);
  static const green = Color(0xff2f5b3c);
  static const greenDark = Color(0xff234630);
  static const greenSoft = Color(0xffe4ecdc);
  static const gold = Color(0xffc9963b);
  static const goldSoft = Color(0xfff6e7c9);
  static const ink = Color(0xff2b2a26);
  static const muted = Color(0xff6f6a60);
  static const border = Color(0xffe6dcc9);
  static const orange = Color(0xffd9822b);
}

/// Portraits from the owner's asset pack that a person can pick (initials otherwise).
const avatarChoices = ['female_1', 'male_1', 'male_2'];

/// An illustration from assets/images (see tool/prepare_assets.sh). The pack's art sits on white, so it
/// is multiplied with the colour behind it ([on]) and the white disappears into the page or card.
class Art extends StatelessWidget {
  final String name;
  final double? width, height;
  final BoxFit fit;
  final Color? on;
  final Alignment alignment;
  const Art(
    this.name, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.on = Palette.background,
    this.alignment = Alignment.center,
  });
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/$name.jpg',
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    color: on,
    colorBlendMode: on == null ? null : BlendMode.multiply,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => SizedBox(width: width, height: height),
  );
}

/// Serif headings: Noto Serif (Latin) with Noto Serif Devanagari, bundled as subsets in assets/fonts.
TextStyle heading(double size, {Color color = Palette.ink}) => TextStyle(
  fontFamily: 'KundliSerif',
  fontFamilyFallback: const ['KundliSerifDeva'],
  fontWeight: FontWeight.w600,
  fontSize: size,
  color: color,
  height: 1.2,
);

ThemeData kundliTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.green,
    primary: Palette.green,
    surface: Palette.background,
  );
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Palette.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Palette.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Palette.ink,
      titleTextStyle: heading(19),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: const BorderSide(color: Palette.green, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xffa39d90)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Palette.green
              : Palette.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Palette.ink,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: Palette.border)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.green : null,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: const RadioThemeData(
      fillColor: WidgetStatePropertyAll(Palette.green),
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
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.surface,
      indicatorColor: Palette.greenSoft,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Palette.green
              : Palette.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          color: s.contains(WidgetState.selected)
              ? Palette.green
              : Palette.muted,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
    ),
  );
}

/// Full-width green pill with an optional trailing arrow, as on every primary action in the design.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool arrow, gold;
  final IconData? icon;
  const PrimaryButton(
    this.label, {
    super.key,
    this.onPressed,
    this.arrow = true,
    this.icon,
    this.gold = false,
  });
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: enabled
              ? LinearGradient(
                  colors: gold
                      ? const [Color(0xffe0b25a), Color(0xffb5832c)]
                      : const [Palette.green, Palette.greenDark],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          color: enabled ? null : const Color(0xffd9d3c6),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? Colors.white : const Color(0xff8d877b),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (arrow) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward,
                    size: 19,
                    color: enabled ? Colors.white : const Color(0xff8d877b),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White rounded card with the design's warm hairline border.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Palette.surface,
    this.borderColor = Palette.border,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: borderColor),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// A chosen portrait ([image], one of [avatarChoices]) or initials on a warm tone picked from the name.
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? image;
  const Avatar(this.name, {super.key, this.size = 46, this.image});
  static const tones = [
    (Color(0xfff3d9c4), Color(0xff8a4b23)),
    (Color(0xffe4ecdc), Color(0xff2f5b3c)),
    (Color(0xfff6e7c9), Color(0xff7a5a12)),
    (Color(0xfff2d6d3), Color(0xff8c3a32)),
    (Color(0xffdde6ee), Color(0xff2f4f6b)),
  ];
  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w.characters.first).join();
    final tone =
        tones[name.codeUnits.fold<int>(0, (a, b) => a + b) % tones.length];
    if (avatarChoices.contains(image)) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          image: DecorationImage(
            image: AssetImage('assets/images/avatar_$image.jpg'),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.$1,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: tone.$2,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Traditional band for a Guna score (same thresholds as the server).
String scoreBand(num score) => score >= 33
    ? 'excellent'
    : score >= 25
    ? 'good'
    : score >= 18
    ? 'average'
    : 'low';

/// Verdict chip: Excellent / Good / Moderate / Challenging, coloured as in the design.
class BandChip extends StatelessWidget {
  final String band;
  final String label;
  const BandChip(this.band, this.label, {super.key});
  static const colours = {
    'excellent': (Color(0xffdcebd4), Color(0xff2f6b34)),
    'good': (Color(0xffe6efd9), Color(0xff4b6b2a)),
    'average': (Color(0xfffbebc8), Color(0xff8a5a00)),
    'low': (Color(0xfff8dcd5), Color(0xffa23b2a)),
  };
  @override
  Widget build(BuildContext context) {
    final c = colours[band] ?? colours['average']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: c.$1,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.$2,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// "1 Details — 2 Confirm" progress header.
class StepIndicator extends StatelessWidget {
  final int step;
  final List<String> labels;
  const StepIndicator({super.key, required this.step, required this.labels});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, label) in labels.indexed) ...[
        if (i > 0)
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: Palette.border,
            ),
          ),
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i <= step ? Palette.gold : Colors.transparent,
            border: Border.all(color: i <= step ? Palette.gold : Palette.muted),
          ),
          child: Text(
            '${i + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: i <= step ? Colors.white : Palette.muted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: i == step ? Palette.gold : Palette.muted,
            fontWeight: i == step ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    ],
  );
}

class SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchBox({super.key, required this.hint, required this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search, color: Palette.muted),
      fillColor: const Color(0xffefe7d8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// Field caption above an input, as in the design's forms.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 7),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: Palette.ink,
      ),
    ),
  );
}

/// The green progress ring around the Guna score on the detailed report.
class ScoreRing extends StatelessWidget {
  final num score;
  final String caption;
  const ScoreRing({super.key, required this.score, required this.caption});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 150,
    child: CustomPaint(
      painter: _RingPainter((score / 36).clamp(0, 1).toDouble()),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              score == score.roundToDouble() ? '${score.toInt()}' : '$score',
              style: heading(46),
            ),
            Text(caption, style: const TextStyle(color: Palette.muted)),
          ],
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(8),
      0,
      2 * math.pi,
      false,
      ring..color = const Color(0xffe8e2d4),
    );
    canvas.drawArc(
      rect.deflate(8),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      ring..color = Palette.green,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}
