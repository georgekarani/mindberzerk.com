import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// The first second: the app mark, picked up where Android's own launch
/// screen left it, with a scan ring sweeping once around it before the mark
/// lifts away into the app.
///
/// Drawn in code so it follows the accent and the light or dark ground with
/// no asset to recolour. [onDone] fires when the sweep ends or after a hard
/// stop, whichever comes first, so a slow phone never waits on the splash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run;
  bool _finished = false;

  /// Size of the mark, close to where Android's launch icon sits.
  static const double _mark = 96;

  @override
  void initState() {
    super.initState();
    _run = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    // The hard stop, in case the ticker is held (a screen off mid launch).
    Future<void>.delayed(const Duration(milliseconds: 2000), _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_run.isAnimating || _run.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    _run.forward().whenComplete(_finish);
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);

    // Three beats on one clock: the ring sweeps, a halo breathes out from
    // it, then the mark lifts and fades as the app arrives underneath.
    final Animation<double> sweep = CurvedAnimation(
      parent: _run,
      curve: const Interval(0.05, 0.6, curve: Curves.easeInOutCubic),
    );
    final Animation<double> halo = CurvedAnimation(
      parent: _run,
      curve: const Interval(0.5, 0.85, curve: Curves.easeOut),
    );
    final Animation<double> lift = CurvedAnimation(
      parent: _run,
      curve: const Interval(0.78, 1, curve: Curves.easeInCubic),
    );

    return ColoredBox(
      color: g.ground,
      child: Center(
        child: AnimatedBuilder(
          animation: _run,
          builder: (BuildContext context, Widget? mark) => Opacity(
            opacity: 1 - lift.value,
            child: Transform.scale(
              scale: 1 + 0.12 * lift.value,
              child: SizedBox.square(
                dimension: _mark * 2,
                child: CustomPaint(
                  painter: _ScanRing(
                    sweep: sweep.value,
                    halo: halo.value,
                    ink: g.accent,
                    track: g.text.withValues(alpha: 0.08),
                  ),
                  child: Center(child: mark),
                ),
              ),
            ),
          ),
          child: Semantics(
            label: 'G Recovery',
            image: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_mark * 0.24),
              child: Image.asset(
                'assets/icons/g_recovery.png',
                width: _mark,
                height: _mark,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    const SizedBox.square(dimension: _mark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin track around the mark, an accent arc sweeping once round it, and
/// a fading halo that rings out when the sweep closes.
class _ScanRing extends CustomPainter {
  _ScanRing({
    required this.sweep,
    required this.halo,
    required this.ink,
    required this.track,
  });

  final double sweep;
  final double halo;
  final Color ink;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide * 0.36;
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    canvas.drawCircle(c, r, line..color = track);
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        math.pi * 2 * sweep,
        false,
        line..color = ink,
      );
    }
    if (halo > 0 && halo < 1) {
      canvas.drawCircle(
        c,
        r + size.shortestSide * 0.14 * halo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ink.withValues(alpha: 0.5 * (1 - halo)),
      );
    }
  }

  @override
  bool shouldRepaint(_ScanRing old) =>
      old.sweep != sweep ||
      old.halo != halo ||
      old.ink != ink ||
      old.track != track;
}
