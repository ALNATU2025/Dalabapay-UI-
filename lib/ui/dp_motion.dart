// lib/ui/dp_motion.dart
// Motion for the Dalabapay design system: page transitions, entrance
// animations, press feedback, number count-up and the animated status mark
// used on receipts. Everything respects the system "remove animations"
// setting (MediaQuery.disableAnimations).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'dp_tokens.dart';

class DPMotion {
  DPMotion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 420);
  static const Duration slow = Duration(milliseconds: 900);
  static const Curve curve = Curves.easeOutCubic;

  /// Delay for the [i]-th item of a staggered list.
  static Duration stagger(int i, {int stepMs = 45, int startMs = 0, int maxSteps = 10}) =>
      Duration(milliseconds: startMs + stepMs * math.min(i, maxSteps));

  /// True when the user turned animations off in system settings.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Page transitions for the whole app (set in the theme).
  static const PageTransitionsTheme pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: DPPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: DPPageTransitionsBuilder(),
      TargetPlatform.windows: DPPageTransitionsBuilder(),
      TargetPlatform.linux: DPPageTransitionsBuilder(),
      TargetPlatform.fuchsia: DPPageTransitionsBuilder(),
    },
  );
}

/// New screens rise in and fade up; the screen underneath eases back slightly.
class DPPageTransitionsBuilder extends PageTransitionsBuilder {
  const DPPageTransitionsBuilder();

  static final Animatable<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic));
  static final Animatable<double> _fade = CurveTween(
    curve: const Interval(0, 0.7, curve: Curves.easeOut),
  );
  static final Animatable<double> _behindScale = Tween<double>(
    begin: 1,
    end: 0.97,
  ).chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (DPMotion.reduced(context)) return child;
    return ScaleTransition(
      scale: secondaryAnimation.drive(_behindScale),
      child: SlideTransition(
        position: animation.drive(_rise),
        child: FadeTransition(opacity: animation.drive(_fade), child: child),
      ),
    );
  }
}

/// Fades and slides its child in the first time it is shown.
class DPAppear extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical travel in logical pixels (positive = rises from below).
  final double offsetY;

  /// Starting scale (1 = no scale).
  final double scaleFrom;

  const DPAppear({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = DPMotion.base,
    this.offsetY = 14,
    this.scaleFrom = 1,
  });

  @override
  State<DPAppear> createState() => _DPAppearState();
}

class _DPAppearState extends State<DPAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DPMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = DPMotion.curve.transform(_c.value);
        Widget w = Transform.translate(
          offset: Offset(0, (1 - t) * widget.offsetY),
          child: child,
        );
        if (widget.scaleFrom != 1) {
          w = Transform.scale(
            scale: lerpDouble(widget.scaleFrom, 1, t)!,
            child: w,
          );
        }
        return Opacity(opacity: _c.value.clamp(0.0, 1.0), child: w);
      },
    );
  }
}

/// Shrinks slightly while pressed — tactile feedback for buttons and tiles.
/// It only listens to the pointer, so taps still reach the child.
class DPPressable extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressedScale;
  const DPPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  @override
  State<DPPressable> createState() => _DPPressableState();
}

class _DPPressableState extends State<DPPressable> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: DPMotion.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Animates a number from its previous value (0 at first) to [value].
class DPCountUp extends StatelessWidget {
  final double value;
  final String Function(double v) format;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;

  const DPCountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = DPMotion.slow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: DPMotion.reduced(context) ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text(format(v), style: style, textAlign: textAlign),
    );
  }
}

enum DPStatusKind { success, pending, failed }

/// Animated status mark for receipts: the circle pops in, the tick (or cross)
/// draws itself, rings ripple out and — on success — a few sparks burst.
class DPStatusHero extends StatefulWidget {
  final DPStatusKind kind;
  final double size;
  const DPStatusHero({
    super.key,
    this.kind = DPStatusKind.success,
    this.size = 96,
  });

  /// Picks the kind from a backend status word.
  static DPStatusKind kindFor(String status) {
    final s = status.toLowerCase();
    if (s.contains('pend') || s.contains('process') || s.contains('initi')) {
      return DPStatusKind.pending;
    }
    if (s.contains('fail') || s.contains('cancel') || s.contains('declin')) {
      return DPStatusKind.failed;
    }
    return DPStatusKind.success;
  }

  @override
  State<DPStatusHero> createState() => _DPStatusHeroState();
}

class _DPStatusHeroState extends State<DPStatusHero>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DPMotion.reduced(context)) {
      _c.value = 1;
      return;
    }
    _c.forward().whenComplete(() {
      if (mounted && widget.kind == DPStatusKind.pending) _pulse.repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color c;
    final Color bg;
    switch (widget.kind) {
      case DPStatusKind.success:
        c = DP.green;
        bg = DP.mint;
        break;
      case DPStatusKind.pending:
        c = DP.amber;
        bg = DP.amberBg;
        break;
      case DPStatusKind.failed:
        c = DP.red;
        bg = DP.redBg;
        break;
    }
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size * 1.5,
        height: widget.size * 1.5,
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, _pulse]),
          builder: (context, _) => CustomPaint(
            painter: _StatusPainter(
              t: _c.value,
              pulse: _pulse.value,
              kind: widget.kind,
              color: c,
              halo: bg,
              size: widget.size,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPainter extends CustomPainter {
  final double t;
  final double pulse;
  final DPStatusKind kind;
  final Color color;
  final Color halo;
  final double size;

  _StatusPainter({
    required this.t,
    required this.pulse,
    required this.kind,
    required this.color,
    required this.halo,
    required this.size,
  });

  double _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    return curve.transform((t - a) / (b - a));
  }

  @override
  void paint(Canvas canvas, Size s) {
    final center = s.center(Offset.zero);
    final outerR = size / 2;
    final innerR = size * 0.34;

    // Ripple rings
    for (final start in [0.18, 0.34]) {
      final r = _seg(start, start + 0.55, Curves.easeOut);
      if (r > 0 && r < 1) {
        canvas.drawCircle(
          center,
          innerR + (outerR * 1.45 - innerR) * r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.35 * (1 - r)),
        );
      }
    }
    // Pending: soft breathing ring after the intro
    if (kind == DPStatusKind.pending && pulse > 0) {
      final p = Curves.easeOut.transform(pulse);
      canvas.drawCircle(
        center,
        outerR + outerR * 0.35 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.3 * (1 - p)),
      );
    }

    // Halo + disc
    final haloScale = _seg(0.0, 0.45, Curves.easeOutBack);
    canvas.drawCircle(center, outerR * haloScale, Paint()..color = halo);
    final discScale = _seg(0.08, 0.55, Curves.elasticOut);
    canvas.drawCircle(center, innerR * discScale, Paint()..color = color);

    // Sparks (success only)
    if (kind == DPStatusKind.success) {
      final sp = _seg(0.42, 1.0, Curves.easeOut);
      if (sp > 0 && sp < 1) {
        final paint = Paint()..color = color.withValues(alpha: 1 - sp);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + math.pi / 8;
          final d = outerR * (0.9 + 0.45 * sp);
          canvas.drawCircle(
            center + Offset(math.cos(a) * d, math.sin(a) * d),
            3.2 * (1 - sp * 0.6),
            paint,
          );
        }
      }
    }

    // Glyph
    final draw = _seg(0.4, 0.78);
    if (draw <= 0) return;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = innerR * 0.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) =>
        center + Offset((x - 0.5) * innerR * 2, (y - 0.5) * innerR * 2);

    final Path path;
    switch (kind) {
      case DPStatusKind.success:
        path = Path()
          ..moveTo(p(0.27, 0.53).dx, p(0.27, 0.53).dy)
          ..lineTo(p(0.44, 0.69).dx, p(0.44, 0.69).dy)
          ..lineTo(p(0.74, 0.36).dx, p(0.74, 0.36).dy);
        break;
      case DPStatusKind.failed:
        path = Path()
          ..moveTo(p(0.33, 0.33).dx, p(0.33, 0.33).dy)
          ..lineTo(p(0.67, 0.67).dx, p(0.67, 0.67).dy)
          ..moveTo(p(0.67, 0.33).dx, p(0.67, 0.33).dy)
          ..lineTo(p(0.33, 0.67).dx, p(0.33, 0.67).dy);
        break;
      case DPStatusKind.pending:
        // Clock: hands sweep in
        path = Path()
          ..moveTo(p(0.5, 0.5).dx, p(0.5, 0.5).dy)
          ..lineTo(p(0.5, 0.28).dx, p(0.5, 0.28).dy)
          ..moveTo(p(0.5, 0.5).dx, p(0.5, 0.5).dy)
          ..lineTo(p(0.66, 0.6).dx, p(0.66, 0.6).dy);
        break;
    }
    // Draw the path progressively
    final out = Path();
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    var remaining = total * draw;
    for (final m in metrics) {
      if (remaining <= 0) break;
      final len = math.min(remaining, m.length);
      out.addPath(m.extractPath(0, len), Offset.zero);
      remaining -= len;
    }
    canvas.drawPath(out, stroke);
  }

  @override
  bool shouldRepaint(covariant _StatusPainter old) =>
      old.t != t || old.pulse != pulse || old.kind != kind;
}
