import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// Portraits a person can pick (initials otherwise); the server accepts the same set.
const avatarChoices = [
  'female_1',
  'female_2',
  'female_3',
  'male_1',
  'male_2',
  'male_3',
];

/// Looping decoration (slow spins, drifting light) stays off in tests and for reduced-motion users.
class Motion {
  static bool ambient = true;
  static bool of(BuildContext context) =>
      ambient && !MediaQuery.disableAnimationsOf(context);
}

/// An image from assets/images (see tool/prepare_assets.py), fading in once decoded.
class Art extends StatelessWidget {
  final String name;
  final double? width, height;
  final BoxFit fit;
  final Alignment alignment;
  const Art(
    this.name, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/$name.webp',
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    filterQuality: FilterQuality.high,
    gaplessPlayback: true,
    frameBuilder: (_, child, frame, sync) => sync
        ? child
        : AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 420),
            child: child,
          ),
    errorBuilder: (_, _, _) => SizedBox(width: width, height: height),
  );
}

/// Rebuilds [builder] with a 0→1 loop value (0 forever when looping motion is off).
class Ambient extends StatefulWidget {
  final Duration period;
  final bool reverse;
  final Widget Function(BuildContext context, double t) builder;
  const Ambient({
    super.key,
    required this.period,
    required this.builder,
    this.reverse = false,
  });
  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.of(context)) {
      if (!controller.isAnimating) controller.repeat(reverse: widget.reverse);
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => widget.builder(context, controller.value),
  );
}

/// Fades and rises into place once, after [delay]; used to stagger the sections of a screen.
class Reveal extends StatefulWidget {
  final Widget child;
  final int delay;
  final double rise;
  const Reveal({
    super.key,
    required this.child,
    this.delay = 0,
    this.rise = 16,
  });
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 460 + widget.delay),
  )..forward();
  late final curve = CurvedAnimation(
    parent: controller,
    curve: Interval(
      widget.delay / (460 + widget.delay),
      1,
      curve: Curves.easeOutCubic,
    ),
  );
  @override
  void dispose() {
    curve.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: curve,
    child: widget.child,
    builder: (_, child) => Opacity(
      opacity: curve.value,
      child: Transform.translate(
        offset: Offset(0, widget.rise * (1 - curve.value)),
        child: child,
      ),
    ),
  );
}

/// Motes of warm light drifting upward, for the splash scene.
class Sparkles extends StatelessWidget {
  const Sparkles({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: Ambient(
        period: const Duration(seconds: 26),
        builder: (_, t) =>
            CustomPaint(size: Size.infinite, painter: _SparklePainter(t)),
      ),
    ),
  );
}

class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final seed = math.Random(11);
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
    for (var i = 0; i < 30; i++) {
      final x = seed.nextDouble(), y0 = seed.nextDouble();
      final speed = 1 + seed.nextInt(2), r = 0.8 + seed.nextDouble() * 1.9;
      final phase = seed.nextDouble(), beat = 2 + seed.nextInt(4);
      final y = (y0 - t * speed) % 1;
      final twinkle = 0.5 + 0.5 * math.sin(2 * math.pi * (t * beat + phase));
      paint.color = const Color(
        0xffffe6a6,
      ).withValues(alpha: 0.15 + 0.6 * twinkle);
      canvas.drawCircle(
        Offset(
          (x + 0.015 * math.sin(2 * math.pi * (t * speed + phase))) *
              size.width,
          y * size.height,
        ),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

/// Materials for raised controls: a metal rim, a shaded body, a solid lip that gives thickness.
class _Material3D {
  final List<Color> rim, body;
  final List<double> stops;
  final Color lip, glow, label, labelShadow;
  final double gloss;
  const _Material3D({
    required this.rim,
    required this.body,
    required this.stops,
    required this.lip,
    required this.glow,
    required this.label,
    required this.labelShadow,
    required this.gloss,
  });
  static const emerald = _Material3D(
    rim: [Color(0xffe9c877), Color(0xffa97c2c)],
    body: [
      Color(0xff4a9267),
      Color(0xff2d6a48),
      Color(0xff1d4f34),
      Color(0xff133c27),
    ],
    stops: [0, 0.42, 0.72, 1],
    lip: Color(0xff0c2b1b),
    glow: Color(0xff174a30),
    label: Colors.white,
    labelShadow: Color(0x99041a0e),
    gloss: 0.34,
  );
  static const metal = _Material3D(
    rim: [Color(0xfffff0c2), Color(0xff9a7024)],
    body: [
      Color(0xfff8e3a6),
      Color(0xffe0b75f),
      Color(0xffc1913a),
      Color(0xff9c7126),
    ],
    stops: [0, 0.4, 0.74, 1],
    lip: Color(0xff6f4e15),
    glow: Color(0xff8a6420),
    label: Color(0xff3a2705),
    labelShadow: Color(0x66fff5d5),
    gloss: 0.5,
  );
  static const ivory = _Material3D(
    rim: [Color(0xffefd9a4), Color(0xffc29a4e)],
    body: [
      Color(0xffffffff),
      Color(0xfffdf8ee),
      Color(0xfff4ead7),
      Color(0xffe7d9bf),
    ],
    stops: [0, 0.45, 0.78, 1],
    lip: Color(0xffbfa675),
    glow: Color(0xff7a5e2c),
    label: Palette.ink,
    labelShadow: Color(0xbbffffff),
    gloss: 0.75,
  );
}

/// The app's main button: looks like a pressed-metal pill and physically sinks when touched.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool arrow, gold, ivory, shine;
  final IconData? icon;
  final double height;
  const PrimaryButton(
    this.label, {
    super.key,
    this.onPressed,
    this.arrow = true,
    this.icon,
    this.gold = false,
    this.ivory = false,
    this.shine = false,
    this.height = 56,
  });
  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final look = widget.gold
        ? _Material3D.metal
        : widget.ivory
        ? _Material3D.ivory
        : _Material3D.emerald;
    final h = widget.height;
    final radius = BorderRadius.circular(h / 2);
    final foreground = enabled ? look.label : const Color(0xff9a9385);
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        height: h,
        padding: const EdgeInsets.all(1.6),
        transform: Matrix4.translationValues(0, down ? 2.6 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: enabled
              ? LinearGradient(
                  colors: look.rim,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [Color(0xffcfc7b6), Color(0xfff0e9db)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
          boxShadow: !enabled
              ? const []
              : [
                  BoxShadow(color: look.lip, offset: Offset(0, down ? 1 : 3.6)),
                  BoxShadow(
                    color: look.glow.withValues(alpha: down ? 0.2 : 0.38),
                    offset: Offset(0, down ? 4 : 11),
                    blurRadius: down ? 8 : 20,
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: down ? 0.08 : 0.16),
                    offset: Offset(0, down ? 6 : 18),
                    blurRadius: down ? 10 : 28,
                    spreadRadius: -8,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: enabled
                      ? LinearGradient(
                          colors: look.body,
                          stops: look.stops,
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : const LinearGradient(
                          colors: [Color(0xffdcd5c7), Color(0xffe9e3d6)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                ),
              ),
              if (enabled) ...[
                // Light from above: a soft gloss following the pill's contour.
                Positioned(
                  left: 1.5,
                  right: 1.5,
                  top: 1,
                  height: h * 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(h / 2),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: look.gloss),
                          Colors.white.withValues(alpha: look.gloss * 0.2),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.shine)
                  RepaintBoundary(
                    child: Ambient(
                      period: const Duration(milliseconds: 5200),
                      builder: (_, t) => t == 0 || t > 0.26
                          ? const SizedBox.shrink()
                          : Align(
                              alignment: Alignment(-1.5 + 3 * t / 0.26, 0),
                              child: Transform(
                                transform: Matrix4.skewX(-0.45),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 46,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0),
                                        Colors.white.withValues(alpha: 0.32),
                                        Colors.white.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
              ],
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onPressed,
                  onHighlightChanged: (v) => setState(() => down = v),
                  splashColor: Colors.white.withValues(alpha: 0.12),
                  highlightColor: Colors.black.withValues(alpha: 0.05),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(
                              widget.icon,
                              color: foreground,
                              size: 20,
                              shadows: enabled
                                  ? [
                                      Shadow(
                                        color: look.labelShadow,
                                        offset: const Offset(0, 1),
                                        blurRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontSize: h > 46 ? 17 : 14.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                shadows: enabled
                                    ? [
                                        Shadow(
                                          color: look.labelShadow,
                                          offset: const Offset(0, 1),
                                          blurRadius: 1.5,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                          if (widget.arrow) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 20,
                              color: foreground,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact raised pill for inline actions such as Edit.
class SmallButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  const SmallButton(this.label, {super.key, this.onPressed});
  @override
  State<SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<SmallButton> {
  bool down = false;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 100),
    transform: Matrix4.translationValues(0, down ? 1.4 : 0, 0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        colors: [Colors.white, Color(0xffefe6d3)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      border: Border.all(color: const Color(0xffdcc593)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xffbfa675),
          offset: Offset(0, down ? 0.6 : 2),
        ),
        BoxShadow(
          color: Palette.shadow.withValues(alpha: 0.18),
          offset: const Offset(0, 4),
          blurRadius: 7,
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onPressed,
        onHighlightChanged: (v) => setState(() => down = v),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Palette.greenDark,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Round raised icon button for app bars.
class RoundIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });
  @override
  State<RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<RoundIconButton> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 40,
      height: 40,
      transform: Matrix4.translationValues(0, down ? 1.4 : 0, 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xffefe6d3)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: const Color(0xffe2d2ad)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xffcdb98e),
            offset: Offset(0, down ? 0.6 : 2),
          ),
          BoxShadow(
            color: Palette.shadow.withValues(alpha: 0.2),
            offset: const Offset(0, 5),
            blurRadius: 9,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onPressed,
          onHighlightChanged: (v) => setState(() => down = v),
          child: Icon(
            widget.icon,
            size: 20,
            color: widget.onPressed == null ? Palette.muted : Palette.greenDark,
          ),
        ),
      ),
    ),
  );
}

/// Raised paper card: lit from above, sits on a warm layered shadow and sinks a little when pressed.
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final double radius;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Palette.surface,
    this.borderColor = Palette.border,
    this.onTap,
    this.radius = 18,
  });
  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    final accented = widget.borderColor != Palette.border;
    return AnimatedScale(
      scale: down ? 0.985 : 1,
      duration: const Duration(milliseconds: 110),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(widget.color, Colors.white, 0.65)!,
              widget.color,
            ],
          ),
          border: Border.all(
            color: widget.borderColor,
            width: accented ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (accented ? widget.borderColor : Palette.shadow)
                  .withValues(alpha: down ? 0.08 : (accented ? 0.24 : 0.13)),
              offset: Offset(0, down ? 2 : 7),
              blurRadius: down ? 6 : 18,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Palette.shadow.withValues(alpha: 0.08),
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            onHighlightChanged: widget.onTap == null
                ? null
                : (v) => setState(() => down = v),
            splashColor: Palette.gold.withValues(alpha: 0.12),
            highlightColor: Palette.gold.withValues(alpha: 0.05),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// A round gold coin holding an icon, used for the home tiles.
class Medallion extends StatelessWidget {
  final IconData icon;
  final double size;
  const Medallion(this.icon, {super.key, this.size = 50});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xfffff0c2), Color(0xffb98a32), Color(0xfff3d78e)],
      ),
      boxShadow: [
        const BoxShadow(color: Color(0xff8a6420), offset: Offset(0, 1.6)),
        BoxShadow(
          color: const Color(0xff8a6420).withValues(alpha: 0.35),
          offset: const Offset(0, 6),
          blurRadius: 10,
          spreadRadius: -1,
        ),
      ],
    ),
    child: Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.45),
          radius: 1,
          colors: [Color(0xff3f8a5e), Color(0xff1d4f34), Color(0xff133c27)],
          stops: [0, 0.65, 1],
        ),
      ),
      child: Icon(
        icon,
        size: size * 0.48,
        color: const Color(0xfff5dc9d),
        shadows: const [
          Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
    ),
  );
}

/// Sliding selector: a raised emerald thumb moving in a recessed track.
class PillSwitch<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double height, fontSize;
  const PillSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.height = 46,
    this.fontSize = 14,
  });
  @override
  Widget build(BuildContext context) {
    final count = options.length;
    final index = options.indexWhere((o) => o.$1 == value);
    final radius = BorderRadius.circular(height / 2);
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xffdfd3bc), Color(0xfff2ebdc)],
        ),
        border: Border.all(color: const Color(0xffd7c9ae)),
        boxShadow: const [
          BoxShadow(color: Color(0xccffffff), offset: Offset(0, 1)),
        ],
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment(
                count == 1 ? 0 : -1 + 2 * index / (count - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xffe9c877), Color(0xffa97c2c)],
                    ),
                    boxShadow: [
                      const BoxShadow(
                        color: Color(0xff0c2b1b),
                        offset: Offset(0, 1.4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        offset: const Offset(0, 4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xff4a9267),
                          Color(0xff235a3b),
                          Color(0xff133c27),
                        ],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final (i, option) in options.indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(option.$1),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          style: TextStyle(
                            fontFamily: 'KundliSans',
                            fontFamilyFallback: const ['KundliSansDeva'],
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: i == index ? Colors.white : Palette.ink,
                          ),
                          child: Text(
                            option.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Radio or checkbox indicator for rows that are tapped as a whole: recessed when off, a raised
/// emerald jewel when on.
class SelectDot extends StatelessWidget {
  final bool selected, square;
  const SelectDot({super.key, required this.selected, this.square = false});
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(square ? 7 : 13);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff4a9267), Color(0xff133c27)],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xffe3d9c5), Color(0xfffdf9f0)],
              ),
        border: Border.all(
          color: selected ? Palette.gold : const Color(0xffcbbd9f),
          width: selected ? 1.4 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Palette.greenDeep.withValues(alpha: 0.4),
                  offset: const Offset(0, 3),
                  blurRadius: 6,
                ),
              ]
            : const [],
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: square
            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
            : Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Color(0xfff0d48e)],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Floating bottom bar; the current tab's icon rises onto a raised emerald pill.
class KundliNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;
  const KundliNavBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.items,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Palette.surface],
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      border: const Border(top: BorderSide(color: Palette.border)),
      boxShadow: [
        BoxShadow(
          color: Palette.shadow.withValues(alpha: 0.16),
          offset: const Offset(0, -5),
          blurRadius: 20,
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Row(
          children: [
            for (final (i, item) in items.indexed)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          width: i == index ? 58 : 44,
                          height: 32,
                          transform: Matrix4.translationValues(
                            0,
                            i == index ? -2 : 0,
                            0,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: i == index
                                ? const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xff4a9267),
                                      Color(0xff235a3b),
                                      Color(0xff133c27),
                                    ],
                                  )
                                : null,
                            border: i == index
                                ? Border.all(color: Palette.gold)
                                : null,
                            boxShadow: i == index
                                ? [
                                    BoxShadow(
                                      color: Palette.greenDeep.withValues(
                                        alpha: 0.4,
                                      ),
                                      offset: const Offset(0, 4),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            i == index ? item.$2 : item.$1,
                            size: 21,
                            color: i == index ? Colors.white : Palette.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontFamily: 'KundliSans',
                            fontFamilyFallback: const ['KundliSansDeva'],
                            fontSize: 11.5,
                            color: i == index ? Palette.green : Palette.muted,
                            fontWeight: i == index
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          child: Text(item.$3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A chosen portrait ([image], one of [avatarChoices]) or initials, framed in a thin gold ring.
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? image;
  const Avatar(this.name, {super.key, this.size = 46, this.image});
  static const tones = [
    (Color(0xfff8e4d3), Color(0xffeac3a4), Color(0xff8a4b23)),
    (Color(0xffeef4e7), Color(0xffcfdfc0), Color(0xff2f5b3c)),
    (Color(0xfffbf0d9), Color(0xfff0d89f), Color(0xff7a5a12)),
    (Color(0xfff8e5e2), Color(0xffecc2bc), Color(0xff8c3a32)),
    (Color(0xffe9f0f6), Color(0xffc5d5e3), Color(0xff2f4f6b)),
  ];
  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w.characters.first).join();
    final tone =
        tones[name.codeUnits.fold<int>(0, (a, b) => a + b) % tones.length];
    final portrait = avatarChoices.contains(image);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff6e3b0), Color(0xffc29a4e), Color(0xfff0dba6)],
        ),
        boxShadow: [
          BoxShadow(
            color: Palette.shadow.withValues(alpha: 0.28),
            offset: const Offset(0, 3),
            blurRadius: 7,
          ),
        ],
      ),
      child: ClipOval(
        child: portrait
            ? Image.asset(
                'assets/images/avatar_$image.webp',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [tone.$1, tone.$2],
                  ),
                ),
                child: Center(
                  child: Text(
                    initials.toUpperCase(),
                    style: TextStyle(
                      color: tone.$3,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.34,
                    ),
                  ),
                ),
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
    'excellent': (Color(0xffe6f3df), Color(0xffc9e3bb), Color(0xff2f6b34)),
    'good': (Color(0xffeef5e2), Color(0xffd8e6c2), Color(0xff4b6b2a)),
    'average': (Color(0xfffdf2d9), Color(0xfff6dfa8), Color(0xff8a5a00)),
    'low': (Color(0xfffbe7e1), Color(0xfff3c9be), Color(0xffa23b2a)),
  };
  @override
  Widget build(BuildContext context) {
    final c = colours[band] ?? colours['average']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.$1, c.$2],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.$2),
        boxShadow: [
          BoxShadow(
            color: c.$3.withValues(alpha: 0.16),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.$3,
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: i <= step ? Palette.gold : Palette.border,
              ),
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: i <= step
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xfff3d78e), Color(0xffb98a32)],
                  )
                : null,
            border: Border.all(
              color: i <= step ? const Color(0xffa97c2c) : Palette.muted,
            ),
            boxShadow: i <= step
                ? [
                    BoxShadow(
                      color: const Color(0xff8a6420).withValues(alpha: 0.4),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ]
                : null,
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
            color: i == step ? const Color(0xff9a7024) : Palette.muted,
            fontWeight: i == step ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    ],
  );
}

/// Search field set into the page: darker along its top edge, as if pressed into the paper.
class SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchBox({super.key, required this.hint, required this.onChanged});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, 0.3],
        colors: [Color(0xffe6dcc8), Color(0xfff3ecde)],
      ),
      border: Border.all(color: const Color(0xffe0d4bd)),
      boxShadow: const [
        BoxShadow(color: Color(0xccffffff), offset: Offset(0, 1)),
      ],
    ),
    child: TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, color: Palette.muted),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
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

/// The Guna score: the arc sweeps in and the number counts up, with a tick per guna around it.
class ScoreRing extends StatelessWidget {
  final num score;
  final String caption;
  final double size;
  const ScoreRing({
    super.key,
    required this.score,
    required this.caption,
    this.size = 188,
  });
  @override
  Widget build(BuildContext context) {
    final target = (score / 36).clamp(0, 1).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(target * t, target),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t == 1
                      ? (score == score.roundToDouble()
                            ? '${score.toInt()}'
                            : '$score')
                      : '${(score * t).round()}',
                  style: heading(
                    size * 0.29,
                    color: Palette.greenDeep,
                    shadows: const [
                      Shadow(
                        color: Colors.white,
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                Text(caption, style: const TextStyle(color: Palette.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value, full;
  _RingPainter(this.value, this.full);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    final radius = outer - 20;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * value;

    // Paper disc behind the number.
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xffffffff), Color(0xfffbf5e8)],
        ).createShader(rect),
    );
    // One gold tick per guna.
    for (var i = 0; i < 36; i++) {
      final a = start + 2 * math.pi * (i + 0.5) / 36;
      final earned = (i + 0.5) / 36 <= value;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * (outer - 8),
        center + Offset(math.cos(a), math.sin(a)) * (outer - 2),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = earned ? Palette.gold : const Color(0xffdfd5c0),
      );
    }
    // Recessed track.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;
    canvas.drawCircle(center, radius, track..color = const Color(0xffe4dac6));
    canvas.drawCircle(
      center + const Offset(0, 1),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..color = const Color(0xfff0e9db),
    );
    if (value <= 0) return;
    // Cast shadow, then the arc, then a highlight along it.
    canvas.drawArc(
      rect.shift(const Offset(0, 3)),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round
        ..color = Palette.greenDeep.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          transform: const GradientRotation(start),
          colors: const [
            Color(0xff133c27),
            Color(0xff2d6a48),
            Color(0xff4f9a6c),
          ],
          stops: [0, full * 0.6, full],
        ).createShader(rect),
    );
    canvas.drawArc(
      rect.deflate(-3.6),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.32),
    );
    // Gold bead at the tip.
    final tip =
        center +
        Offset(math.cos(start + sweep), math.sin(start + sweep)) * radius;
    canvas.drawCircle(
      tip + const Offset(0, 2),
      8.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      tip,
      8,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          colors: [Color(0xfffff3cc), Color(0xffd9ab55), Color(0xff9c7126)],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: tip, radius: 8)),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// Warm paper with leaf sprigs in two corners, behind long screens such as the report.
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xfffbf6ec),
                Palette.background,
                Color(0xfff3ebda),
              ],
            ),
          ),
        ),
        Positioned(
          right: -34,
          top: -14,
          child: Transform.rotate(
            angle: 0.5,
            child: const Opacity(
              opacity: 0.32,
              child: Art('sprig', width: 130, height: 150),
            ),
          ),
        ),
        Positioned(
          left: -40,
          top: 120,
          child: Transform.rotate(
            angle: -0.6,
            child: const Opacity(
              opacity: 0.2,
              child: Art('sprig', width: 120, height: 140),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The opening scene shared by the language screen and the native splash: painted background, a slowly
/// turning mandala and the name and tagline as real text, so they stay sharp on every screen.
class BrandScene extends StatelessWidget {
  final String name, tagline;
  final List<Widget> below;
  const BrandScene({
    super.key,
    required this.name,
    required this.tagline,
    this.below = const [],
  });
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Ambient(
        period: const Duration(seconds: 28),
        reverse: true,
        builder: (_, t) => Transform.scale(
          scale: 1.02 + 0.05 * Curves.easeInOut.transform(t),
          child: const Art(
            'splash_bg',
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
        ),
      ),
      const Sparkles(),
      SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final mandala = math.min(box.maxWidth * 0.54, box.maxHeight * 0.26);
            final nameSize = math.min(46.0, box.maxWidth * 0.115);
            return Column(
              children: [
                SizedBox(height: box.maxHeight * 0.06),
                Reveal(
                  rise: 0,
                  child: SizedBox(
                    width: mandala,
                    height: mandala,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // A halo that lifts the emblem off the sky.
                        Positioned(
                          left: -mandala * 0.25,
                          right: -mandala * 0.25,
                          top: -mandala * 0.25,
                          bottom: -mandala * 0.25,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                stops: const [0, 0.62, 1],
                                colors: [
                                  const Color(
                                    0xfffff6dc,
                                  ).withValues(alpha: 0.95),
                                  const Color(
                                    0xfffff3cf,
                                  ).withValues(alpha: 0.6),
                                  const Color(0xfffff3cf).withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Ambient(
                          period: const Duration(seconds: 90),
                          builder: (_, t) => Transform.rotate(
                            angle: 2 * math.pi * t,
                            child: Art(
                              'mandala',
                              width: mandala,
                              height: mandala,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: box.maxHeight * 0.016),
                Reveal(
                  delay: 180,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: heading(
                      nameSize,
                      color: Palette.greenDeep,
                      shadows: const [
                        Shadow(color: Color(0xeeffffff), blurRadius: 14),
                        Shadow(
                          color: Color(0x55ffffff),
                          offset: Offset(0, 1),
                          blurRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Reveal(
                  delay: 320,
                  child: Text(
                    tagline,
                    textAlign: TextAlign.center,
                    style: heading(
                      nameSize * 0.42,
                      color: const Color(0xff3c3524),
                      shadows: const [
                        Shadow(color: Color(0xddffffff), blurRadius: 10),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                ...below,
              ],
            );
          },
        ),
      ),
    ],
  );
}
