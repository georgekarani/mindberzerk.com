import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// The Wi-Fi fan: three arcs and a dot, lit up to [signal] (0 to 1). Arcs
/// ease to new readings, and the outermost lit arc breathes while connected.
class WifiArcs extends StatefulWidget {
  const WifiArcs({required this.signal, super.key, this.size = 72});

  /// 0 to 1, or null when the phone does not say.
  final double? signal;
  final double size;

  @override
  State<WifiArcs> createState() => _WifiArcsState();
}

class _WifiArcsState extends State<WifiArcs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return SizedBox.square(
      dimension: widget.size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: (widget.signal ?? 0).clamp(0.0, 1.0)),
        duration: GDesign.motion(context, GDesign.slow),
        curve: GDesign.enter,
        builder: (BuildContext context, double level, Widget? _) =>
            AnimatedBuilder(
              animation: _breath,
              builder: (BuildContext context, Widget? _) => CustomPaint(
                painter: _ArcsPainter(
                  level: widget.signal == null ? null : level,
                  breath: _breath.value,
                  on: g.accent,
                  off: g.text.withValues(alpha: 0.12),
                ),
              ),
            ),
      ),
    );
  }
}

class _ArcsPainter extends CustomPainter {
  const _ArcsPainter({
    required this.level,
    required this.breath,
    required this.on,
    required this.off,
  });

  final double? level;
  final double breath;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset base = Offset(size.width / 2, size.height * 0.86);
    const double sweep = math.pi / 2;
    const double start = -math.pi / 2 - sweep / 2;
    final double step = size.height * 0.24;
    // Dot plus three arcs: four steps of signal.
    final int lit = level == null ? 0 : (level! * 4).ceil().clamp(1, 4);

    canvas.drawCircle(base, step * 0.28, Paint()..color = lit >= 1 ? on : off);
    for (int i = 1; i <= 3; i++) {
      final bool isLit = i < lit;
      // The outermost lit arc breathes.
      final double alpha = isLit && i == lit - 1 ? 0.55 + 0.45 * breath : 1;
      canvas.drawArc(
        Rect.fromCircle(center: base, radius: step * i + step * 0.2),
        start,
        sweep,
        false,
        Paint()
          ..color = isLit ? on.withValues(alpha: alpha) : off
          ..style = PaintingStyle.stroke
          ..strokeWidth = step * 0.42
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcsPainter old) =>
      old.level != level || old.breath != breath || old.on != on;
}

/// One lens on the [CameraModule].
class ModuleLens {
  const ModuleLens({required this.label, required this.megapixels});

  final String label;
  final double megapixels;
}

/// The back camera bump: a rounded module with one ring per lens, sized by
/// megapixels and labelled, each one dropping in with a short stagger.
class CameraModule extends StatelessWidget {
  const CameraModule({required this.lenses, super.key, this.front});

  final List<ModuleLens> lenses;

  /// The selfie camera, drawn as a punch hole beside the module.
  final ModuleLens? front;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    double biggest = 1;
    for (final ModuleLens l in lenses) {
      biggest = math.max(biggest, l.megapixels);
    }
    double diameter(double mp) => 44 + 30 * math.sqrt(mp / biggest);

    // Module on top, selfie camera under it: side by side overflows a
    // phone-width card once lenses are labelled.
    return Column(
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: g.fill,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Padding(
            padding: const EdgeInsets.all(GDesign.space12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < lenses.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: GDesign.space8),
                  Reveal(
                    index: i,
                    child: _Lens(
                      lens: lenses[i],
                      diameter: diameter(lenses[i].megapixels),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (front != null) ...<Widget>[
          const SizedBox(height: GDesign.space12),
          Reveal(
            index: lenses.length,
            child: _Lens(lens: front!, diameter: 36),
          ),
        ],
      ],
    );
  }
}

class _Lens extends StatelessWidget {
  const _Lens({required this.lens, required this.diameter});

  final ModuleLens lens;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox.square(
          dimension: 74,
          child: Center(
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: g.hairline, width: 3),
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.35),
                  radius: 0.9,
                  colors: <Color>[
                    g.accent.withValues(alpha: 0.45),
                    const Color(0xFF0A0A0C),
                  ],
                  stops: const <double>[0, 0.55],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: GDesign.space8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(lens.label, style: g.footnote(weight: FontWeight.w600)),
            Text(
              '${lens.megapixels.toStringAsFixed(lens.megapixels < 10 ? 1 : 0)} MP',
              style: g.figures(g.footnote()),
            ),
          ],
        ),
      ],
    );
  }
}

/// One thermal zone on the [HeatColumns].
class HeatZone {
  const HeatZone({required this.label, required this.celsius});

  final String label;
  final double celsius;
}

/// Zones as columns rising to their temperature on a 20 to 70 °C scale,
/// warming from the accent's pale end to full accent, then danger past 55.
class HeatColumns extends StatelessWidget {
  const HeatColumns({required this.zones, super.key, this.height = 150});

  final List<HeatZone> zones;
  final double height;

  static const double _floor = 20;
  static const double _ceiling = 70;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return SizedBox(
      // Room for the figure above and the label below each column.
      height: height + 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int i = 0; i < zones.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: GDesign.space8),
            Expanded(
              child: _Column(zone: zones[i], height: height, g: g),
            ),
          ],
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.zone, required this.height, required this.g});

  final HeatZone zone;
  final double height;
  final GDesignTheme g;

  @override
  Widget build(BuildContext context) {
    final double t =
        ((zone.celsius - HeatColumns._floor) /
                (HeatColumns._ceiling - HeatColumns._floor))
            .clamp(0.04, 1.0);
    final Color top = zone.celsius >= 55
        ? g.danger
        : Color.lerp(g.accent.withValues(alpha: 0.35), g.accent, t)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Text(
          '${zone.celsius.round()}°',
          style: g.figures(g.footnote(color: g.text, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: t),
          duration: GDesign.motion(context, const Duration(milliseconds: 700)),
          curve: GDesign.enter,
          builder: (BuildContext context, double v, Widget? _) => Container(
            height: height * v,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: <Color>[g.accent.withValues(alpha: 0.25), top],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          zone.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: g.caption(color: g.muted),
        ),
      ],
    );
  }
}

/// A spirit level driven by the accelerometer: the bubble drifts to the high
/// side as the phone tilts, and the ring turns accent when it is level.
class BubbleLevel extends StatelessWidget {
  const BubbleLevel({required this.x, required this.y, super.key});

  /// Accelerometer x and y in m/s2. Gravity is about 9.8.
  final double x;
  final double y;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    // Android reports +g along whichever axis points up, and the bubble
    // floats to the high side. Right edge down makes x negative, so the
    // bubble goes left; top edge up makes y positive, so it goes up, which
    // is negative in screen coordinates.
    final double dx = (x / 9.8).clamp(-1.0, 1.0);
    final double dy = (-y / 9.8).clamp(-1.0, 1.0);
    final bool level = dx.abs() < 0.05 && dy.abs() < 0.05;
    return AspectRatio(
      aspectRatio: 1.6,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double r = box.maxHeight / 2 - 4;
          const double bubble = 34;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: g.text.withValues(alpha: 0.12),
                    width: 2,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: GDesign.motion(context, GDesign.fast),
                width: bubble + 8,
                height: bubble + 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: level ? g.accent : g.text.withValues(alpha: 0.25),
                    width: 2,
                  ),
                ),
              ),
              AnimatedSlide(
                // Fractions of the bubble's own size, so it can reach the rim.
                offset:
                    Offset(dx * (r - bubble / 2), dy * (r - bubble / 2)) /
                    bubble,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Container(
                  width: bubble,
                  height: bubble,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: g.accent.withValues(alpha: level ? 1 : 0.8),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: g.accent.withValues(alpha: 0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
