import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:g_design/g_design.dart';

/// What the graphics test measured.
@immutable
class GpuOutcome {
  const GpuOutcome({required this.score, required this.fps, required this.iters});

  /// Relative to a Galaxy S22 at 1000.
  final double score;

  /// Frames per second the scene held at its final weight.
  final double fps;

  /// How heavy the scene got, in iterations per pixel.
  final double iters;
}

/// The graphics test: a full screen scene that gets heavier until the frame
/// rate falls below the screen's own rate, so the chip, not the screen, is
/// the limit. It then holds that weight and counts frames. Work per second
/// is pixels x iterations x frames per second.
class GpuBench extends StatefulWidget {
  const GpuBench({required this.onProgress, required this.onDone, super.key});

  /// 0 to 1 through the test, with the frame rate right now.
  final void Function(double progress, double fps) onProgress;

  final ValueChanged<GpuOutcome> onDone;

  /// Pixel iterations per second a Galaxy S22 reaches. Measured on a
  /// Galaxy S22+ (same chip) on 20 Nov 2026.
  static const double referenceRate = 3.02e9;

  @override
  State<GpuBench> createState() => _GpuBenchState();
}

class _GpuBenchState extends State<GpuBench>
    with SingleTickerProviderStateMixin {
  static const double _maxIters = 2048;
  static const Duration _rampStep = Duration(milliseconds: 450);
  static const Duration _measure = Duration(seconds: 4);
  static const Duration _limit = Duration(seconds: 12);

  ui.FragmentShader? _shader;
  late final Ticker _ticker = createTicker(_onFrame);

  double _iters = 24;
  bool _ramping = true;
  int _frames = 0;
  Duration _windowStart = Duration.zero;
  Duration _now = Duration.zero;
  double _screenHz = 60;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    ui.FragmentProgram.fromAsset('shaders/bench.frag').then((ui.FragmentProgram p) {
      if (!mounted) return;
      setState(() => _shader = p.fragmentShader());
      _ticker.start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenHz = View.of(context).display.refreshRate.clamp(30, 240);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    if (_finished) return;
    _now = elapsed;
    _frames++;
    final Duration window = elapsed - _windowStart;
    final double fps = _frames / (window.inMicroseconds / 1e6).clamp(1e-3, 1e9);

    if (_ramping && window >= _rampStep) {
      // Still keeping up with the screen: add weight. Otherwise the chip is
      // the limit, so hold this weight and start counting.
      if (fps > _screenHz * 0.8 && _iters < _maxIters) {
        _iters = (_iters * 1.6).clamp(1, _maxIters);
      } else {
        _ramping = false;
      }
      _frames = 0;
      _windowStart = elapsed;
      widget.onProgress((elapsed.inMilliseconds / _limit.inMilliseconds).clamp(0, 0.6), fps);
    } else if (!_ramping) {
      widget.onProgress(0.6 + 0.4 * (window.inMilliseconds / _measure.inMilliseconds).clamp(0, 1), fps);
      if (window >= _measure || elapsed >= _limit) _finish(fps);
    } else if (elapsed >= _limit) {
      _finish(fps);
    }
    setState(() {});
  }

  void _finish(double fps) {
    _finished = true;
    _ticker.stop();
    final Size size = context.size ?? Size.zero;
    final double ratio = View.of(context).devicePixelRatio;
    final double pixels = size.width * size.height * ratio * ratio;
    final double rate = pixels * _iters * fps;
    widget.onDone(
      GpuOutcome(
        score: rate / GpuBench.referenceRate * 1000,
        fps: fps,
        iters: _iters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentShader? shader = _shader;
    if (shader == null) return const SizedBox.expand();
    final GDesignTheme g = GDesignTheme.of(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _ScenePainter(
        shader: shader,
        time: _now.inMicroseconds / 1e6,
        iters: _iters,
        base: g.ground,
        tint: g.accent,
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.shader,
    required this.time,
    required this.iters,
    required this.base,
    required this.tint,
  });

  final ui.FragmentShader shader;
  final double time;
  final double iters;
  final Color base;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, iters)
      ..setFloat(4, base.r)
      ..setFloat(5, base.g)
      ..setFloat(6, base.b)
      ..setFloat(7, tint.r)
      ..setFloat(8, tint.g)
      ..setFloat(9, tint.b);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}
