import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// Vector stand-ins for the Figma artwork: drawn, so they stay sharp and add no image downloads.

/// Gold mandala with a green centre (logo on the language screen and native splash).
/// [progress] 0→1 grows the rings outward for the splash animation.
class MandalaPainter extends CustomPainter {
  final double progress;
  MandalaPainter([this.progress = 1]);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final gold = Paint()
      ..color = Palette.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.022;
    final green = Paint()
      ..color = Palette.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.024;
    // Rings of petals from the centre outward: (petals, inner radius, outer radius, paint).
    final rings = [
      (8, 0.18, 0.42, green),
      (12, 0.36, 0.64, gold),
      (16, 0.58, 0.86, gold),
      (24, 0.82, 0.98, gold),
    ];
    for (final (i, ring) in rings.indexed) {
      final t = ((progress - i * 0.18) / 0.4).clamp(0.0, 1.0);
      if (t == 0) continue;
      final (count, inner, outer, paint) = ring;
      for (var k = 0; k < count; k++) {
        final a = 2 * math.pi * k / count;
        canvas.drawPath(
          petal(
            c,
            a,
            r * inner,
            r * (inner + (outer - inner) * t),
            r * 0.9 / count * 2.4,
          ),
          paint,
        );
      }
      canvas.drawCircle(c, r * inner, paint);
    }
    final dot = ((progress - 0.1) / 0.3).clamp(0.0, 1.0);
    canvas.drawCircle(c, r * 0.1 * dot, Paint()..color = Palette.green);
    canvas.drawCircle(c, r * 0.05 * dot, Paint()..color = Palette.goldSoft);
  }

  /// A pointed petal from radius [from] to [to] along angle [a].
  Path petal(Offset c, double a, double from, double to, double width) {
    Offset at(double radius, double da) =>
        c + Offset(math.cos(a + da), math.sin(a + da)) * radius;
    final spread = width / math.max(from, 1);
    final mid = (from + to) / 2;
    return Path()
      ..moveTo(at(from, 0).dx, at(from, 0).dy)
      ..quadraticBezierTo(
        at(mid, spread).dx,
        at(mid, spread).dy,
        at(to, 0).dx,
        at(to, 0).dy,
      )
      ..quadraticBezierTo(
        at(mid, -spread).dx,
        at(mid, -spread).dy,
        at(from, 0).dx,
        at(from, 0).dy,
      );
  }

  @override
  bool shouldRepaint(MandalaPainter old) => old.progress != progress;
}

/// Home banner: dawn sky, sun with a zodiac arc, hills, river and a temple on the bank.
class HeroScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xfffbefd6), Color(0xfff6e2bd), Color(0xfff7efe2)],
          stops: [0, 0.6, 1],
        ).createShader(rect),
    );
    final sun = Offset(w * 0.5, h * 0.42);
    // Zodiac arc with twelve marks.
    final arc = Paint()
      ..color = Palette.gold.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final arcR = h * 0.36;
    canvas.drawArc(
      Rect.fromCircle(center: sun, radius: arcR),
      math.pi,
      math.pi,
      false,
      arc,
    );
    for (var i = 0; i <= 12; i++) {
      final a = math.pi + math.pi * i / 12;
      canvas.drawCircle(
        sun + Offset(math.cos(a), math.sin(a)) * arcR,
        2.2,
        Paint()..color = Palette.gold,
      );
    }
    for (var i = 0; i < 16; i++) {
      final a = math.pi + math.pi * i / 15;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        sun + d * (h * 0.13),
        sun + d * (h * 0.2),
        arc..strokeWidth = 1.4,
      );
    }
    canvas.drawCircle(sun, h * 0.1, Paint()..color = const Color(0xffe9a33c));
    // Hills.
    final hills = Path()
      ..moveTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.2, h * 0.48, w * 0.42, h * 0.6)
      ..quadraticBezierTo(w * 0.62, h * 0.5, w * 0.8, h * 0.58)
      ..quadraticBezierTo(w * 0.92, h * 0.54, w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xffcfd8b4));
    // River.
    final river = Path()
      ..moveTo(0, h * 0.72)
      ..quadraticBezierTo(w * 0.5, h * 0.66, w, h * 0.72)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(river, Paint()..color = const Color(0xffe9e4d2));
    final ripple = Paint()
      ..color = const Color(0xffd8cfb8)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 4; i++) {
      final y = h * (0.78 + i * 0.05);
      canvas.drawLine(
        Offset(w * (0.3 + i * 0.04), y),
        Offset(w * (0.55 + i * 0.03), y),
        ripple,
      );
    }
    temple(canvas, Offset(w * 0.8, h * 0.66), h * 0.34);
    temple(canvas, Offset(w * 0.68, h * 0.68), h * 0.2);
    tree(canvas, Offset(w * 0.13, h * 0.7), h * 0.42);
  }

  void temple(Canvas canvas, Offset base, double height) {
    final paint = Paint()..color = const Color(0xffd7a85c);
    final shade = Paint()..color = const Color(0xffb98b45);
    final width = height * 0.55;
    canvas.drawRect(
      Rect.fromLTWH(
        base.dx - width / 2,
        base.dy - height * 0.32,
        width,
        height * 0.32,
      ),
      paint,
    );
    // Shikhara (tower) and its finial.
    final tower = Path()
      ..moveTo(base.dx - width * 0.36, base.dy - height * 0.32)
      ..quadraticBezierTo(
        base.dx - width * 0.3,
        base.dy - height * 0.85,
        base.dx,
        base.dy - height,
      )
      ..quadraticBezierTo(
        base.dx + width * 0.3,
        base.dy - height * 0.85,
        base.dx + width * 0.36,
        base.dy - height * 0.32,
      )
      ..close();
    canvas.drawPath(tower, paint);
    canvas.drawLine(
      Offset(base.dx, base.dy - height),
      Offset(base.dx, base.dy - height * 1.1),
      shade..strokeWidth = 1.6,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        base.dx - width * 0.12,
        base.dy - height * 0.22,
        width * 0.24,
        height * 0.22,
      ),
      shade,
    );
  }

  void tree(Canvas canvas, Offset base, double height) {
    canvas.drawLine(
      base,
      base - Offset(0, height * 0.55),
      Paint()
        ..color = const Color(0xff7a6a4a)
        ..strokeWidth = height * 0.06,
    );
    final leaves = Paint()..color = const Color(0xff8fa16a);
    for (final o in [
      Offset(0, -0.75),
      Offset(-0.22, -0.6),
      Offset(0.22, -0.62),
      Offset(0, -0.5),
    ]) {
      canvas.drawCircle(base + o * height, height * 0.2, leaves);
    }
  }

  @override
  bool shouldRepaint(HeroScenePainter old) => false;
}

/// Soft leaves and a lotus framing the language screen.
class BotanicalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final leaf = Paint()
      ..color = const Color(0xff9aab7c).withValues(alpha: 0.55);
    final dark = Paint()
      ..color = const Color(0xff6f8a58).withValues(alpha: 0.5);
    void sprig(Offset base, double angle, double length, Paint paint) {
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        base,
        base + dir * length,
        Paint()
          ..color = paint.color
          ..strokeWidth = 2,
      );
      for (var i = 1; i <= 5; i++) {
        final p = base + dir * (length * i / 6);
        for (final side in [-1, 1]) {
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(angle + side * 0.9);
          canvas.drawOval(
            Rect.fromLTWH(0, -length * 0.045, length * 0.2, length * 0.09),
            paint,
          );
          canvas.restore();
        }
      }
    }

    // Sized from a phone-width frame so wide browser windows keep delicate sprigs.
    final u = math.min(w, 430.0);
    sprig(Offset(0, h * 0.25), -0.5, u * 0.3, leaf);
    sprig(Offset(w, h * 0.3), math.pi + 0.5, u * 0.28, leaf);
    sprig(Offset(0, h * 0.95), -0.9, u * 0.42, dark);
    sprig(Offset(w, h * 0.9), math.pi + 0.8, u * 0.38, dark);
    canvas.save();
    canvas.translate(w - u * 0.38, h - u * 0.2);
    LotusPainter().paint(canvas, Size(u * 0.24, u * 0.16));
    canvas.restore();
  }

  @override
  bool shouldRepaint(BotanicalPainter old) => false;
}

/// Pink-gold lotus (language screen and report decoration).
class LotusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final base = Offset(w / 2, h);
    final petal = Paint()..color = const Color(0xfff2b99a);
    final inner = Paint()..color = const Color(0xffeaa07f);
    for (final (a, len, p) in [
      (-1.0, 0.95, petal),
      (1.0, 0.95, petal),
      (-0.5, 1.0, inner),
      (0.5, 1.0, inner),
      (0.0, 1.05, petal),
    ]) {
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(a * 0.55);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(-w * 0.16, -h * 0.5 * len, 0, -h * len)
        ..quadraticBezierTo(w * 0.16, -h * 0.5 * len, 0, 0);
      canvas.drawPath(path, p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(LotusPainter old) => false;
}

/// Small lotus outline used beside the score ring.
class LotusIcon extends StatelessWidget {
  final double size;
  const LotusIcon({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 0.66), painter: _LotusOutline());
}

class _LotusOutline extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = Palette.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final base = Offset(w / 2, h);
    for (final a in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(a * 0.6);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-w * 0.13, -h * 0.5, 0, -h * 0.95)
          ..quadraticBezierTo(w * 0.13, -h * 0.5, 0, 0),
        p,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LotusOutline old) => false;
}
