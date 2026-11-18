/// How the dock arrives: the `dockEntrance` axis, drawn.
///
/// ─── IT WAS A SETTING WITH NOTHING BEHIND IT ────────────────────────────────
///
/// The value was parsed, resolved, stored and offered in Desktop settings, and
/// no dock read it, so every choice looked identical. This is the reader. It
/// wraps whichever dock a shell draws (GnomeDock, AquaDock) rather than living
/// inside one of them, so the four docks cannot drift apart on it.
///
/// ─── WHEN IT PLAYS ──────────────────────────────────────────────────────────
///
///   * on first paint;
///   * whenever the launcher comes back to the front, which is what "the dock
///     arrives" means to someone pressing Home;
///   * when the mode itself changes, so picking one in Settings and returning
///     shows it, instead of a choice you cannot see until the next launch.
///
/// Never on a timer and never while idle: one short controller run per arrival,
/// and `none` builds no controller at all.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class DockEntrance extends StatefulWidget {
  const DockEntrance({
    super.key,
    required this.mode,
    required this.child,
    this.from = AxisDirection.up,
  });

  /// One of `dockEntranceModes`: none, slide, expand, blur, stagger, gloss.
  final String mode;

  /// The direction the dock travels to arrive. A bottom dock moves up; a left
  /// dock moves right.
  final AxisDirection from;

  final Widget child;

  @override
  State<DockEntrance> createState() => _DockEntranceState();
}

class _DockEntranceState extends State<DockEntrance>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 420);

  // Both created in initState, never lazily. With mode 'none' the build
  // never touched `_t`, so the first read was in dispose(), and creating a
  // ticker there looks up TickerMode on a deactivated element and throws.
  late final AnimationController _t;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: _duration, value: 1);
    _life = AppLifecycleListener(onResume: _play);
    _play();
  }

  @override
  void didUpdateWidget(DockEntrance old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _play();
  }

  void _play() {
    if (widget.mode == 'none' || !mounted) return;
    _t.forward(from: 0);
  }

  @override
  void dispose() {
    _life.dispose();
    _t.dispose();
    super.dispose();
  }

  Offset get _travel => switch (widget.from) {
        AxisDirection.up => const Offset(0, 1),
        AxisDirection.down => const Offset(0, -1),
        AxisDirection.right => const Offset(-1, 0),
        AxisDirection.left => const Offset(1, 0),
      };

  @override
  Widget build(BuildContext context) {
    if (widget.mode == 'none') return widget.child;

    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        final e = Curves.easeOutCubic.transform(v);

        return switch (widget.mode) {
          // Rises from its own edge, about its own height, fading in.
          'slide' => FractionalTranslation(
              translation: _travel * (1 - e),
              child: Opacity(opacity: e, child: child),
            ),
          // Grows out from its centre along the edge it sits on.
          'expand' => Transform.scale(
              scaleX: widget.from == AxisDirection.up ||
                      widget.from == AxisDirection.down
                  ? 0.6 + 0.4 * e
                  : 1,
              scaleY: widget.from == AxisDirection.left ||
                      widget.from == AxisDirection.right
                  ? 0.6 + 0.4 * e
                  : 1,
              child: Opacity(opacity: e, child: child),
            ),
          // Comes into focus.
          'blur' => ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 14 * (1 - e),
                sigmaY: 14 * (1 - e),
              ),
              child: Opacity(opacity: e, child: child),
            ),
          // Revealed along its length, so the icons appear one after another.
          'stagger' => ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => _wipe(rect, e),
              child: child,
            ),
          // A single highlight crossing the dock as it fades in.
          'gloss' => Opacity(
              opacity: (e * 1.6).clamp(0.0, 1.0),
              child: ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (rect) => _sheen(rect, v),
                child: child,
              ),
            ),
          _ => child!,
        };
      },
    );
  }

  /// Opaque up to [e] of the way along the dock, with a soft leading edge.
  Shader _wipe(Rect rect, double e) {
    final horizontal = widget.from == AxisDirection.up ||
        widget.from == AxisDirection.down;
    final edge = (e * 1.2).clamp(0.0, 1.2);
    return LinearGradient(
      begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
      end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
      colors: const [
        Colors.white, // theme-exempt: mask alpha, never painted
        Colors.white, // theme-exempt: mask alpha
        Color(0x00FFFFFF), // theme-exempt: mask alpha
      ],
      stops: [0, (edge - 0.2).clamp(0.0, 1.0), edge.clamp(0.0, 1.0)],
    ).createShader(rect);
  }

  /// A narrow white band sweeping across, over the dock's own pixels only.
  Shader _sheen(Rect rect, double v) {
    final x = -0.3 + 1.6 * v;
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [
        Color(0x00FFFFFF), // theme-exempt: highlight
        Color(0x66FFFFFF), // theme-exempt: highlight
        Color(0x00FFFFFF), // theme-exempt: highlight
      ],
      stops: [
        (x - 0.15).clamp(0.0, 1.0),
        x.clamp(0.0, 1.0),
        (x + 0.15).clamp(0.0, 1.0),
      ],
    ).createShader(rect);
  }
}
