import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/theme_mark.dart';
import '../../engine/splash_spec.dart';
import '../../engine/theme_source.dart';
import 'hello_lettering.dart';

/// Everything the splash renderer needs that is not in the [SplashSpec].
///
/// Its own small value type for the same reason [BootColors] is one: the
/// renderer never has to know the shape of EffectiveTheme, and the mapping
/// happens at ONE wiring point (home_screen) where the field names are known.
class SplashChrome {
  const SplashChrome({
    required this.background,
    required this.accent,
    required this.onDark,
    this.title,
    this.logoAsset,
    this.displayFontFamily,
    this.monoFontFamily = 'UbuntuMono',
    this.hello = false,
    this.onHelloShown,
  });

  /// Write the distro's words out after the bar, this once. Only meaningful
  /// for [SplashStyle.hello]; the caller decides "this once" from prefs.
  final bool hello;

  /// The words have been written: record it so the next boot skips them.
  final VoidCallback? onHelloShown;

  /// The distro's dark base, so the splash reads as THIS distro starting.
  final Color background;
  final Color accent;
  final Color onDark;

  /// Distro name, the text style's content, and the fallback when a theme has
  /// no logo artwork.
  final String? title;

  /// Already resolved by the caller: the spec's own logo, else the theme's dark
  /// logo variant, else null.
  ///
  /// ─── THIS WAS A String AND THAT WAS THE BUG ─────────────────────────────
  ///
  /// A [ThemeAsset], because the same `theme.json` string means two different
  /// things and only [ThemeSource] knows which. A bundled Ubuntu says
  /// `assets/themes/ubuntu-24-04/logo_dark.webp`; the SAME distro republished
  /// over the CDN says `logo_dark.webp`, a bare filename sitting in the pack
  /// directory, because `PackPaths` refuses separators.
  ///
  /// Carrying a String across this boundary threw away the knowledge of which,
  /// so the renderer below had no choice but to guess, and it guessed
  /// `Image.asset` every time. On any installed pack that is
  /// `Unable to load asset: "logo_dark.webp"`, raised inside the image
  /// pipeline, swallowed by an errorBuilder, and visible only as a splash with
  /// no mark on it. Every other consumer of a theme path in the app already
  /// went through `source.asset(...)`; see `_Strip` in wallpaper_screen.dart,
  /// which carries the same scar. The splash was the last one holding a String.
  final ThemeAsset? logoAsset;

  final String? displayFontFamily;
  final String monoFontFamily;
}

/// Paints a [SplashSpec] for its duration, then fades out.
///
/// Purely visual and stateless with respect to the app, exactly like
/// [BootSequence]: it does not decide WHEN to play (that is [BootController])
/// and it does not touch prefs. It renders and calls [onComplete].
///
/// Not tap-to-skip, unlike the verbose boot. A six-second log you did not ask
/// for needs an escape hatch; a 900ms splash does not, and a tap target that
/// lives for under a second is one you will hit by accident on the shell
/// underneath.
class SplashSequence extends StatefulWidget {
  const SplashSequence({
    super.key,
    required this.spec,
    required this.background,
    required this.accent,
    required this.onDark,
    required this.onComplete,
    this.title,
    this.logoAsset,
    this.monoFontFamily = 'UbuntuMono',
    this.displayFontFamily,
    this.hello = false,
    this.onHelloShown,
  });

  final SplashSpec spec;

  /// See [SplashChrome.hello].
  final bool hello;

  /// See [SplashChrome.onHelloShown].
  final VoidCallback? onHelloShown;

  /// The distro's dark base, so the splash reads as THIS distro starting rather
  /// than as a generic black screen, the same rule the boot canvas follows.
  final Color background;
  final Color accent;
  final Color onDark;

  /// Distro name, for [SplashStyle.text] and as the fallback when there is no
  /// logo to draw.
  final String? title;

  /// Resolved by the caller: the spec's own `logo`, else the theme's dark logo
  /// variant, else null. See [SplashChrome.logoAsset] for why this is a
  /// [ThemeAsset] and not a path.
  final ThemeAsset? logoAsset;

  final String monoFontFamily;
  final String? displayFontFamily;

  final VoidCallback onComplete;

  @override
  State<SplashSequence> createState() => _SplashSequenceState();
}

class _SplashSequenceState extends State<SplashSequence>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.spec.durationMs),
  );

  /// The writing: a hand's pace for two short words, eased in and out.
  static const _writeMs = 2600;

  /// The finished words stay on screen this long before the desktop.
  static const _holdMs = 700;

  late final AnimationController _write = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _writeMs),
  );

  /// The bar has finished and the words are being written.
  bool _writing = false;

  bool get _hello => widget.spec.style == SplashStyle.hello && widget.hello;

  bool _fading = false;

  @override
  void initState() {
    super.initState();

    // Reduce-motion: honour the opt-out by holding a still frame for a beat
    // instead of animating. The splash still happens (it is a transition, not
    // decoration), it just does not move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _afterBar();
    });

    // The reduce-motion path never runs the controller to completion, so it
    // needs its own timer to land.
    Future<void>.delayed(
      Duration(milliseconds: widget.spec.durationMs + 60),
      _afterBar,
    );
  }

  /// The bar is full: the desktop, or first the words.
  void _afterBar() {
    if (!_hello) {
      _finish();
      return;
    }
    if (_writing || _fading || !mounted) return;
    setState(() => _writing = true);

    // Recorded as soon as the words START, not when they end: a launcher
    // killed mid-hello must not greet the user again on the next boot.
    widget.onHelloShown?.call();

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      // The words appear whole and hold; nothing is drawn moving.
      _write.value = 1.0;
    } else {
      _write.forward();
    }
    Future<void>.delayed(
      Duration(milliseconds: (reduceMotion ? 0 : _writeMs) + _holdMs),
      _finish,
    );
  }

  void _finish() {
    if (_fading || !mounted) return;
    setState(() => _fading = true);
    // Fade out, then hand control back, so the shell "comes up" underneath
    // rather than hard-cutting in.
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _write.dispose();
    super.dispose();
  }

  /// Turns completed so far at one turn a second, so a spinner keeps the same
  /// pace whatever duration the theme authored.
  double get _turns =>
      _controller.value * widget.spec.durationMs / Duration.millisecondsPerSecond;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final padding = MediaQuery.paddingOf(context);
    final showFoot = !_writing && spec.console == null && spec.wordmark != null;

    return AnimatedOpacity(
      opacity: _fading ? 0 : 1,
      duration: const Duration(milliseconds: 200),
      child: DecoratedBox(
        decoration: _ground(spec.background),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (spec.decor case final decor?)
              RepaintBoundary(
                child: CustomPaint(
                  painter: _DecorPainter(
                    decor: decor,
                    fallback: widget.onDark,
                  ),
                ),
              ),
            if (spec.console case final console? when !_writing)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  padding.top + 48,
                  18,
                  padding.bottom + 24,
                ),
                child: _Console(
                  console: console,
                  controller: _controller,
                  durationMs: spec.durationMs,
                  ink: widget.onDark,
                  accent: widget.accent,
                  fontFamily: widget.monoFontFamily,
                ),
              )
            else
              Center(
                // ─── THE LOGO HANDS OVER TO THE WORDS ───────────────────────
                //
                // A cross-fade in place, so the mark and bar dissolve and the
                // writing begins where they were, the way a phone's boot gives
                // way to its hello rather than cutting to it.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: _writing
                      ? HelloLettering(
                          key: const ValueKey('hello'),
                          progress: CurvedAnimation(
                            parent: _write,
                            curve: Curves.easeInOutCubic,
                          ),
                          color: widget.onDark,
                          width: MediaQuery.sizeOf(context).width * 0.72,
                        )
                      : Padding(
                          key: const ValueKey('boot'),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _stack(spec),
                        ),
                ),
              ),
            if (showFoot)
              Positioned(
                left: 24,
                right: 24,
                bottom: padding.bottom + 64,
                child: _SplashTextView(
                  text: spec.wordmark!,
                  ink: widget.onDark,
                  displayFont: widget.displayFontFamily,
                  monoFont: widget.monoFontFamily,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Logo, caption, indicator, top to bottom.
  Widget _stack(SplashSpec spec) {
    // The bare-name style draws no mark, unless the theme asked for a
    // graphical indicator, in which case it is a logo splash after all.
    final bareText = spec.style == SplashStyle.text && spec.indicator == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!bareText) _logoBlock(spec),
        if (!bareText && spec.caption != null) ...[
          const SizedBox(height: 22),
          _SplashTextView(
            text: spec.caption!,
            ink: widget.onDark,
            displayFont: widget.displayFontFamily,
            monoFont: widget.monoFontFamily,
          ),
        ],
        if (!bareText) SizedBox(height: spec.gap),
        _indicator(spec),
      ],
    );
  }

  /// The mark, with its optional breathing glow and turning ring.
  Widget _logoBlock(SplashSpec spec) {
    final mark = _logo(spec.logoSize);
    final ring = spec.ring;
    final glow = spec.logoGlow;
    if (ring == null && glow == null) return mark;

    final box = ring?.size ?? spec.logoSize;
    return SizedBox.square(
      dimension: box,
      child: AnimatedBuilder(
        animation: _controller,
        child: mark,
        builder: (context, child) {
          // One breath every 2.4s, matching the mockup's glow.
          final breath = 0.5 - 0.5 * math.cos(_turns * 2 * math.pi / 2.4);
          return Stack(
            alignment: Alignment.center,
            // The glow spreads past the box; clipping it would square it off.
            clipBehavior: Clip.none,
            children: [
              if (glow != null)
                Container(
                  width: spec.logoSize,
                  height: spec.logoSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: glow,
                        blurRadius: 24 + 36 * breath,
                        spreadRadius: 8 * breath,
                      ),
                    ],
                  ),
                ),
              if (ring != null)
                CustomPaint(
                  size: Size.square(ring.size),
                  painter: _RingPainter(
                    ring: ring,
                    angle: _turns * 2 * math.pi,
                    accent: widget.accent,
                    track: widget.onDark.withValues(alpha: 0.08),
                  ),
                ),
              child!,
            ],
          );
        },
      ),
    );
  }

  /// The distro's name in its own display font.
  ///
  /// Used for a theme that ships no artwork AND as the failure arm below, which
  /// is the part that changed. A missing file used to render
  /// `SizedBox.shrink`, so a broken logo path produced a splash with a hole in
  /// it and no way to tell that apart from a theme that simply has no mark.
  /// Landing on the wordmark means the worst case is a plainer splash rather
  /// than an empty one.
  Widget _wordmark() => Text(
        widget.title ?? '',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: widget.displayFontFamily,
          fontSize: 26,
          fontWeight: FontWeight.w300,
          letterSpacing: 1.5,
          color: widget.onDark,
        ),
      );

  Widget _logo(double size) {
    // ── THE FOUR BRANCHES MOVED TO [ThemeMark] ─────────────────────────
    //
    // This file used to spell out svg-or-raster and file-or-asset itself, and
    // it was the FIRST place that got the file-or-asset half right. Two other
    // readers then made the original mistake independently, which is what
    // turned a fixed bug into a shared widget: the branches live in one place
    // now and this call site says only what is specific to a splash.
    return ThemeMark(
      asset: widget.logoAsset,
      size: size,
      // ── AS AUTHORED, NOT KNOCKED OUT ───────────────────────────────
      //
      // This tinted to onDark, and on Ubuntu that turned the orange mark into
      // a solid white circle: srcIn keeps the alpha and replaces every opaque
      // pixel, so the disc and the friends inside it become one shape.
      //
      // The dark variant of [ThemeLogo] is already artwork authored for a dark
      // surface, so tinting it discards exactly what the second variant exists
      // to preserve. The FALLBACK keeps its own colour, because the Mindhunter
      // mark genuinely is one monochrome silhouette that has to read on every
      // distro.
      tint: null,
      fallback: _wordmark(),
    );
  }

  Widget _indicator(SplashSpec spec) {
    final faint = widget.onDark.withValues(alpha: 0.18);

    // The theme authored one: draw exactly that.
    if (spec.indicator case final i?) {
      return switch (i.kind) {
        SplashIndicatorKind.dots => _Dots(
            controller: _controller,
            color: i.color ?? widget.onDark,
            count: i.count,
            diameter: i.thickness,
          ),
        SplashIndicatorKind.bar => _Bar(
            controller: _controller,
            accent: i.color ?? widget.accent,
            track: i.track ?? faint,
            width: i.width,
            thickness: i.thickness,
          ),
        SplashIndicatorKind.spinner => _Spinner(
            controller: _controller,
            durationMs: spec.durationMs,
            color: i.color ?? widget.accent,
            track: i.track ?? widget.onDark.withValues(alpha: 0.12),
            size: i.size,
            stroke: i.thickness,
          ),
        SplashIndicatorKind.none => const SizedBox.shrink(),
      };
    }

    // Otherwise the style decides, exactly as before the graphical fields.
    return switch (spec.style) {
      SplashStyle.dots => _Dots(
          controller: _controller,
          color: widget.onDark,
        ),
      SplashStyle.bar => _Bar(
          controller: _controller,
          accent: widget.accent,
          track: faint,
        ),
      SplashStyle.spinner => _Spinner(
          controller: _controller,
          durationMs: spec.durationMs,
          color: widget.accent,
          track: widget.onDark.withValues(alpha: 0.12),
        ),
      // A phone's boot: the same determinate bar in the logo's own white,
      // not the accent. Phones do not colour their boot bar.
      SplashStyle.hello => _Bar(
          controller: _controller,
          accent: widget.onDark,
          track: widget.onDark.withValues(alpha: 0.22),
        ),
      SplashStyle.text => Text(
          widget.title ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: widget.monoFontFamily,
            fontSize: 13,
            color: widget.onDark.withValues(alpha: 0.7),
          ),
        ),
      // Handled by the gate, which never mounts this widget for `none`.
      SplashStyle.none => const SizedBox.shrink(),
    };
  }

  /// The ground: the theme's own fill, else the distro's dark base.
  BoxDecoration _ground(SplashBackground? bg) {
    if (bg == null) return BoxDecoration(color: widget.background);
    final colors = bg.colors.length == 1 ? [bg.colors.first, bg.colors.first] : bg.colors;
    return switch (bg.fill) {
      SplashFill.solid => BoxDecoration(color: bg.colors.first),
      SplashFill.radial => BoxDecoration(
          color: bg.colors.last,
          gradient: RadialGradient(
            center: bg.center,
            radius: 1.1,
            colors: colors,
          ),
        ),
      SplashFill.linear => () {
          // CSS degrees: 0 points up, 90 right, 180 down.
          final rad = bg.angle * math.pi / 180;
          final end = Alignment(math.sin(rad), -math.cos(rad));
          return BoxDecoration(
            color: bg.colors.last,
            gradient: LinearGradient(
              begin: -end,
              end: end,
              colors: colors,
            ),
          );
        }(),
    };
  }
}

/// A [SplashText], wrapped and centred, never clipped.
class _SplashTextView extends StatelessWidget {
  const _SplashTextView({
    required this.text,
    required this.ink,
    required this.displayFont,
    required this.monoFont,
  });

  final SplashText text;
  final Color ink;
  final String? displayFont;
  final String monoFont;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: text.mono ? monoFont : displayFont,
      fontSize: text.size,
      fontWeight: FontWeight.values[(text.weight ~/ 100) - 1],
      letterSpacing: text.spacing,
      color: text.color ?? ink,
      height: 1.2,
    );
    return Text.rich(
      TextSpan(
        // Tracking adds space after the last letter too; padding the start by
        // the same amount keeps tracked caps optically centred.
        children: [
          if (text.spacing > 0)
            WidgetSpan(child: SizedBox(width: text.spacing)),
          TextSpan(text: text.text),
          if (text.suffix case final suffix?)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  suffix,
                  style: style.copyWith(
                    fontSize: text.size * 0.5,
                    letterSpacing: 0,
                    color: style.color!.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

/// Plymouth's pulsing dots: each one brightens in turn, on a loop.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.controller,
    required this.color,
    this.count = 5,
    this.diameter = 7,
  });

  final AnimationController controller;
  final Color color;
  final int count;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Three passes across the dots over the splash's life, so the rhythm
        // reads regardless of the authored duration.
        final t = (controller.value * 3) % 1.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: diameter * 0.6),
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(
                      alpha: 0.25 + 0.75 * _pulse(t, i / count),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// A short bright window travelling along the row, wrapping at the end.
  static double _pulse(double t, double offset) {
    final d = (t - offset) % 1.0;
    return d < 0.25 ? 1.0 - (d / 0.25) : 0.0;
  }
}

/// KDE's determinate bar. Determinate, not indeterminate, because the splash
/// has a known duration: a bar that spins forever while the thing behind it is
/// already ready is the animation everyone has learned to distrust.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.controller,
    required this.accent,
    required this.track,
    this.width = 180,
    this.thickness = 3,
  });

  final AnimationController controller;
  final Color accent;
  final Color track;
  final double width;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(thickness / 2),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => LinearProgressIndicator(
            value: controller.value,
            minHeight: thickness,
            backgroundColor: track,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ),
    );
  }
}

/// A quarter arc turning over a faint track, driven by the splash clock so it
/// holds still under reduce-motion like everything else here.
class _Spinner extends StatelessWidget {
  const _Spinner({
    required this.controller,
    required this.durationMs,
    required this.color,
    required this.track,
    this.size = 22,
    this.stroke = 2,
  });

  final AnimationController controller;
  final int durationMs;
  final Color color;
  final Color track;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(
          ring: SplashRing(
            kind: SplashRingKind.arc,
            colors: [color],
            size: size,
            thickness: stroke,
          ),
          angle: controller.value *
              durationMs /
              Duration.millisecondsPerSecond *
              2 *
              math.pi,
          accent: color,
          track: track,
          sweep: math.pi / 2,
        ),
      ),
    );
  }
}

/// A ring around the logo: one arc over a track, or a full multi-colour sweep.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.ring,
    required this.angle,
    required this.accent,
    required this.track,
    this.sweep = math.pi,
  });

  final SplashRing ring;
  final double angle;
  final Color accent;
  final Color track;

  /// Arc only: how much of the circle is lit.
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = ring.thickness;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;

    if (ring.kind == SplashRingKind.conic && ring.colors.length > 1) {
      // The sweep turns, rather than the arc, so the ring reads as one piece.
      paint.shader = SweepGradient(
        colors: [...ring.colors, ring.colors.first],
        transform: GradientRotation(angle),
      ).createShader(rect);
      canvas.drawArc(rect, 0, 2 * math.pi, false, paint);
      return;
    }

    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    paint
      ..color = ring.colors.isEmpty ? accent : ring.colors.first
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, angle - math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.angle != angle ||
      old.ring != ring ||
      old.accent != accent ||
      old.track != track;
}

/// The faint pattern over the ground. Painted once: it does not move.
class _DecorPainter extends CustomPainter {
  const _DecorPainter({required this.decor, required this.fallback});

  final SplashDecor decor;
  final Color fallback;

  /// Fixed star positions in unit space, so every boot draws the same sky.
  static const _stars = <(double, double, double)>[
    (0.20, 0.30, 1.0), (0.70, 0.60, 1.0), (0.40, 0.80, 1.5),
    (0.85, 0.20, 1.0), (0.12, 0.62, 0.8), (0.55, 0.14, 1.2),
    (0.92, 0.48, 0.8), (0.30, 0.08, 0.9), (0.64, 0.88, 1.1),
    (0.08, 0.90, 1.0), (0.48, 0.42, 0.7), (0.78, 0.74, 0.9),
    (0.26, 0.50, 0.6), (0.95, 0.92, 1.2), (0.36, 0.22, 0.6),
    (0.60, 0.34, 0.8), (0.16, 0.12, 1.1), (0.82, 0.36, 0.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    switch (decor.kind) {
      case SplashDecorKind.grid:
        const cell = 26.0;
        final paint = Paint()
          ..color = decor.color ?? fallback.withValues(alpha: 0.06)
          ..strokeWidth = 1;
        for (var x = 0.0; x <= size.width; x += cell) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = 0.0; y <= size.height; y += cell) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case SplashDecorKind.stars:
        final paint = Paint()
          ..color = decor.color ?? fallback.withValues(alpha: 0.5);
        for (final (x, y, r) in _stars) {
          canvas.drawCircle(Offset(x * size.width, y * size.height), r, paint);
        }
    }
  }

  @override
  bool shouldRepaint(_DecorPainter old) =>
      old.decor != decor || old.fallback != fallback;
}

/// A tty login, typed a line at a time, ending on a blinking cursor.
class _Console extends StatelessWidget {
  const _Console({
    required this.console,
    required this.controller,
    required this.durationMs,
    required this.ink,
    required this.accent,
    required this.fontFamily,
  });

  final SplashConsole console;
  final AnimationController controller;
  final int durationMs;
  final Color ink;
  final Color accent;
  final String fontFamily;

  /// `Sun Nov 15 14:06`, the way `login` prints it. Not localised: it is a
  /// line of terminal output, and a tty does not translate its own log.
  static String _now() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} ${months[t.month - 1]} ${t.day} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: fontFamily,
      fontSize: 12.5,
      height: 1.7,
      color: ink.withValues(alpha: 0.86),
    );
    final now = _now();
    final lines = console.lines;
    // Each line gets an equal slice of the first 80%, so the prompt sits for a
    // beat with its cursor before the desktop arrives.
    final slice = 0.8 / lines.length;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final v = controller.value;
        final elapsedMs = v * durationMs;
        final cursorOn = (elapsedMs ~/ 530).isEven;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++)
              Opacity(
                opacity: ((v - i * slice) / slice).clamp(0.0, 1.0),
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (lines[i].head case final head?)
                        TextSpan(
                          text: head,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      TextSpan(text: lines[i].text.replaceAll('{now}', now)),
                      if (console.cursor && i == lines.length - 1)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Opacity(
                            opacity: cursorOn ? 1 : 0,
                            child: Container(
                              width: 8,
                              height: 14,
                              color: ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                  style: style,
                ),
              ),
          ],
        );
      },
    );
  }
}
