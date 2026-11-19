import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import 'bench_engine.dart';
import 'phone_spec.dart';

/// An x-ray of this phone: its own shape, front camera opening, rear lenses,
/// processor cores grouped by speed, memory, storage and battery, each
/// labelled with what the phone reports. The part being tested lights up:
/// a fast core for the one core step, every core for the next, then data
/// running out to memory and to storage. A scan line sweeps while it runs.
///
/// Parts sit where they usually sit inside a phone; the drawing is not a
/// teardown of this model.
class PhoneXray extends ConsumerStatefulWidget {
  const PhoneXray({required this.stage, this.labels = true, super.key});

  final BenchStage stage;

  /// Part names and figures; off where the drawing is too small to read.
  final bool labels;

  @override
  ConsumerState<PhoneXray> createState() => _PhoneXrayState();
}

class _PhoneXrayState extends ConsumerState<PhoneXray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _live =>
      widget.stage != BenchStage.idle && widget.stage != BenchStage.done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PhoneXray old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final bool move = _live && !MediaQuery.disableAnimationsOf(context);
    if (move && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!move && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final PhoneSpec spec =
        (ref.watch(phoneSpecProvider).value ?? PhoneSpec.fallback).withScreen(
          View.of(context),
          MediaQuery.displayFeaturesOf(context),
        );
    return Semantics(
      label: switch (widget.stage) {
        BenchStage.single => 'Testing one fast processor core',
        BenchStage.multi => 'Testing all ${spec.cores} processor cores',
        BenchStage.memory => 'Testing memory',
        BenchStage.storage => 'Testing storage',
        BenchStage.gpu => 'Testing graphics',
        BenchStage.done => 'Test finished',
        BenchStage.idle => 'The parts inside this phone',
      },
      child: AspectRatio(
        aspectRatio: 1 / spec.aspect,
        child: AnimatedBuilder(
          animation: _clock,
          builder: (BuildContext context, Widget? _) => CustomPaint(
            painter: _XrayPainter(
              spec: spec,
              stage: widget.stage,
              labels: widget.labels,
              t: _clock.value,
              accent: g.accent,
              line: g.text.withValues(alpha: 0.18),
              dim: g.text.withValues(alpha: 0.07),
              label: g.muted,
              labelOn: g.text,
              textStyle: g.caption(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marketed sizes: the system reports a little less than the box says,
/// because some is kept for itself, so round up to the next common size.
String _gb(int bytes, List<int> sizes) {
  final double gb = bytes / (1 << 30);
  for (final int s in sizes) {
    if (gb <= s) return s >= 1024 ? '${s ~/ 1024} TB' : '$s GB';
  }
  return '${gb.round()} GB';
}

const List<int> _ramSizes = <int>[1, 2, 3, 4, 6, 8, 10, 12, 16, 18, 24, 32];
const List<int> _storageSizes = <int>[8, 16, 32, 64, 128, 256, 512, 1024, 2048];

class _XrayPainter extends CustomPainter {
  _XrayPainter({
    required this.spec,
    required this.stage,
    required this.labels,
    required this.t,
    required this.accent,
    required this.line,
    required this.dim,
    required this.label,
    required this.labelOn,
    required this.textStyle,
  });

  final PhoneSpec spec;
  final BenchStage stage;
  final bool labels;
  final double t;
  final Color accent;
  final Color line;
  final Color dim;
  final Color label;
  final Color labelOn;
  final TextStyle textStyle;

  Paint get _stroke => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = line;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final bool cpuOn = stage == BenchStage.single || stage == BenchStage.multi;
    final bool ramOn = stage == BenchStage.memory;
    final bool flashOn = stage == BenchStage.storage;
    final bool gpuOn = stage == BenchStage.gpu;
    final bool done = stage == BenchStage.done;

    // Body.
    final RRect body = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(w * 0.13),
    );
    canvas.drawRRect(body, _stroke..strokeWidth = 2);

    // Board layout.
    final Rect soc = Rect.fromLTWH(w * 0.34, h * 0.105, w * 0.46, w * 0.46);
    final Rect ram = Rect.fromLTWH(w * 0.83, soc.top, w * 0.1, soc.height);
    final Rect flash = Rect.fromLTWH(
      soc.left,
      soc.bottom + h * 0.045,
      soc.width,
      h * 0.055,
    );
    final Rect battery = Rect.fromLTRB(
      w * 0.1,
      flash.bottom + h * 0.075,
      w * 0.9,
      h * 0.92,
    );

    _rearCameras(
      canvas,
      Rect.fromLTWH(w * 0.07, h * 0.035, w * 0.22, soc.height),
    );
    _frontCamera(canvas, size);

    // Traces from the processor to memory and storage.
    for (final double d in <double>[-0.06, 0, 0.06]) {
      canvas.drawLine(
        Offset(soc.right, soc.center.dy + w * d),
        Offset(ram.left, soc.center.dy + w * d),
        _stroke..color = ramOn ? accent.withValues(alpha: 0.5) : line,
      );
      canvas.drawLine(
        Offset(soc.center.dx + w * d, soc.bottom),
        Offset(soc.center.dx + w * d, flash.top),
        _stroke..color = flashOn ? accent.withValues(alpha: 0.5) : line,
      );
    }
    if (ramOn) {
      _packets(
        canvas,
        Offset(soc.right, soc.center.dy),
        Offset(ram.left, soc.center.dy),
        w * 0.06,
        alongX: true,
      );
    }
    if (flashOn) {
      _packets(
        canvas,
        Offset(soc.center.dx, soc.bottom),
        Offset(soc.center.dx, flash.top),
        w * 0.06,
        alongX: false,
      );
    }

    // Battery.
    final RRect cell = RRect.fromRectAndRadius(
      battery,
      Radius.circular(w * 0.05),
    );
    canvas.drawRRect(cell, Paint()..color = dim);
    canvas.drawRRect(cell, _stroke);

    _part(canvas, ram, on: ramOn || done, pulse: ramOn);
    _part(canvas, flash, on: flashOn || done, pulse: flashOn);
    _part(canvas, soc, on: false, pulse: false);
    // The chip holds the cores and, below them, the graphics block.
    final Rect inner = soc.deflate(w * 0.04);
    final Rect coreArea = Rect.fromLTWH(
      inner.left,
      inner.top,
      inner.width,
      inner.height * 0.64,
    );
    final Rect gpuArea = Rect.fromLTRB(
      inner.left,
      coreArea.bottom + inner.height * 0.06,
      inner.right,
      inner.bottom,
    );
    _cores(canvas, coreArea, lit: cpuOn || done);
    _part(canvas, gpuArea, on: gpuOn || done, pulse: gpuOn);
    _label(canvas, 'GPU', gpuArea.center, gpuOn);

    // Labels: the real figures where the phone gives them.
    _label(
      canvas,
      spec.clusters.join(' + '),
      Offset(soc.center.dx, soc.top - 11),
      cpuOn,
    );
    _label(
      canvas,
      spec.ramBytes == null ? 'RAM' : _gb(spec.ramBytes!, _ramSizes),
      Offset(ram.center.dx, ram.bottom + 11),
      ramOn,
    );
    _label(
      canvas,
      spec.storageBytes == null
          ? 'Storage'
          : _gb(spec.storageBytes!, _storageSizes),
      Offset(flash.center.dx, flash.bottom + 11),
      flashOn,
    );
    _label(
      canvas,
      spec.batteryMah == null ? 'Battery' : '${spec.batteryMah!.round()} mAh',
      battery.center,
      false,
    );

    // Scan line while a test runs.
    if (stage != BenchStage.idle && !done) {
      final double y = h * t;
      final Rect band = Rect.fromLTWH(0, y - 30, w, 60);
      canvas
        ..save()
        ..clipRRect(body)
        ..drawRect(
          band,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                accent.withValues(alpha: 0),
                accent.withValues(alpha: 0.14),
                accent.withValues(alpha: 0),
              ],
            ).createShader(band),
        )
        ..restore();
    }
  }

  /// One lens per focal length, laid out the way phones usually group them:
  /// a column for up to three, a square for four.
  void _rearCameras(Canvas canvas, Rect area) {
    final int n = spec.rearCameras.isEmpty
        ? 1
        : math.min(spec.rearCameras.length, 4);
    final double r = area.width * 0.36;
    final List<Offset> at = n == 4
        ? <Offset>[
            area.topLeft + Offset(r, r),
            area.topLeft + Offset(r * 2.5, r),
            area.topLeft + Offset(r, r * 2.6),
            area.topLeft + Offset(r * 2.5, r * 2.6),
          ].map((Offset o) => o.translate(-r * 0.25, 0)).toList()
        : <Offset>[
            for (int i = 0; i < n; i++)
              area.topLeft + Offset(area.width / 2, r * 1.1 + i * r * 2.3),
          ];
    final double lens = n == 4 ? r * 0.7 : r;
    for (final Offset c in at) {
      canvas
        ..drawCircle(c, lens, _stroke)
        ..drawCircle(c, lens * 0.45, Paint()..color = dim);
    }
  }

  /// The front camera opening where the screen reports it.
  void _frontCamera(Canvas canvas, Size size) {
    final FrontCutout? cut = spec.cutout;
    if (cut == null) return;
    final Offset c = Offset(
      cut.center.dx * size.width,
      math.max(cut.center.dy * size.height, size.width * 0.05),
    );
    if (cut.isNotch) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx, size.width * 0.03),
            width: cut.width * size.width,
            height: size.width * 0.07,
          ),
          Radius.circular(size.width * 0.035),
        ),
        _stroke,
      );
    } else {
      canvas.drawCircle(c, size.width * 0.025, _stroke);
    }
  }

  void _part(Canvas canvas, Rect r, {required bool on, required bool pulse}) {
    final RRect shape = RRect.fromRectAndRadius(r, const Radius.circular(6));
    if (on) {
      final double a = pulse ? 0.55 + 0.35 * math.sin(t * math.pi * 2) : 0.5;
      canvas
        ..drawRRect(
          shape.inflate(4),
          Paint()
            ..color = accent.withValues(alpha: a * 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        )
        ..drawRRect(shape, Paint()..color = accent.withValues(alpha: a));
    } else {
      canvas.drawRRect(shape, Paint()..color = dim);
    }
    canvas.drawRRect(shape, _stroke..color = on ? accent : line);
  }

  /// One row per cluster, fastest on top with the biggest cells. The one
  /// core step lights a single fast core, hopping between them; the all
  /// cores step lights every cell.
  void _cores(Canvas canvas, Rect area, {required bool lit}) {
    final List<int> rows = spec.clusters.take(4).toList();
    final int widest = rows.fold(1, (int a, int b) => math.max(a, b));
    final double gap = area.width * 0.05;
    final double rowH = (area.height - gap * (rows.length - 1)) / rows.length;
    final int hop =
        (t * spec.fastCores * 2).floor() % math.max(spec.fastCores, 1);
    int index = 0;
    for (int r = 0; r < rows.length; r++) {
      final int count = rows[r];
      // Fast cores are drawn wider, as they are physically larger.
      final double cw = (area.width - gap * (widest - 1)) / widest;
      final double rowWidth = count * cw + (count - 1) * gap;
      final double left = area.left + (area.width - rowWidth) / 2;
      for (int c = 0; c < count; c++, index++) {
        final Rect cell = Rect.fromLTWH(
          left + c * (cw + gap),
          area.top + r * (rowH + gap),
          cw,
          rowH,
        );
        final double a = switch (stage) {
          BenchStage.single => r == 0 && c == hop ? 1.0 : 0.1,
          BenchStage.multi =>
            0.6 + 0.4 * math.sin((t * 2 + index * 0.37) * math.pi * 2).abs(),
          _ => lit ? 0.45 : 0.0,
        };
        final RRect shape = RRect.fromRectAndRadius(
          cell,
          const Radius.circular(3),
        );
        if (a > 0.5) {
          canvas.drawRRect(
            shape.inflate(2),
            Paint()
              ..color = accent.withValues(alpha: a * 0.6)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }
        canvas
          ..drawRRect(
            shape,
            Paint()..color = a > 0 ? accent.withValues(alpha: a) : dim,
          )
          ..drawRRect(shape, _stroke..strokeWidth = 1);
      }
    }
  }

  /// Small squares travelling both ways along a trace.
  void _packets(
    Canvas canvas,
    Offset from,
    Offset to,
    double spread, {
    required bool alongX,
  }) {
    final Paint p = Paint()..color = accent;
    for (int lane = -1; lane <= 1; lane++) {
      for (int k = 0; k < 3; k++) {
        double f = (t * 2 + k / 3 + lane * 0.17) % 1.0;
        if (lane == 0) f = 1 - f;
        final Offset at = Offset.lerp(from, to, f)!;
        final Offset shift = alongX
            ? Offset(0, lane * spread)
            : Offset(lane * spread, 0);
        canvas.drawRect(
          Rect.fromCenter(center: at + shift, width: 5, height: 5),
          p,
        );
      }
    }
  }

  void _label(Canvas canvas, String text, Offset center, bool on) {
    if (!labels) return;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(
          color: on ? labelOn : label,
          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_XrayPainter old) =>
      old.t != t ||
      old.stage != stage ||
      old.accent != accent ||
      old.spec.cores != spec.cores ||
      old.spec.aspect != spec.aspect ||
      old.spec.cutout?.center != spec.cutout?.center ||
      old.spec.rearCameras.length != spec.rearCameras.length ||
      old.spec.ramBytes != spec.ramBytes ||
      old.spec.batteryMah != spec.batteryMah;
}
