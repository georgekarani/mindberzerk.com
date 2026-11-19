import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// One cluster on the [CpuDie]: its name, its top speed, and each core's
/// current speed as a fraction of that top (null when unknown or offline).
class DieCluster {
  const DieCluster({required this.label, required this.cores, this.peak});

  final String label;
  final String? peak;
  final List<double?> cores;
}

/// The processor drawn as a chip: pins round the edge, one block per
/// cluster, one square per core lit by how fast it is running right now.
///
/// Each square eases to its new brightness, so the 2 Hz readings read as a
/// living chip rather than a flickering table.
class CpuDie extends StatelessWidget {
  const CpuDie({required this.clusters, super.key});

  final List<DieCluster> clusters;

  /// Pins drawn along each edge.
  static const int _pins = 14;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return CustomPaint(
      painter: _PinPainter(color: g.faint, pins: _pins),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: g.fill,
            borderRadius: BorderRadius.circular(GDesign.tileRadius),
            border: Border.all(color: g.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(GDesign.space12),
            child: Column(
              children: <Widget>[
                for (int c = 0; c < clusters.length; c++) ...<Widget>[
                  if (c > 0) const SizedBox(height: GDesign.space12),
                  _ClusterBlock(cluster: clusters[c]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClusterBlock extends StatelessWidget {
  const _ClusterBlock({required this.cluster});

  final DieCluster cluster;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                cluster.label,
                style: g.footnote(weight: FontWeight.w600),
              ),
            ),
            if (cluster.peak != null)
              Text(cluster.peak!, style: g.figures(g.footnote())),
          ],
        ),
        const SizedBox(height: GDesign.space8),
        Row(
          children: <Widget>[
            for (int i = 0; i < cluster.cores.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _Core(fraction: cluster.cores[i])),
            ],
            // Keep squares a sensible size in a one or two core cluster.
            for (int i = cluster.cores.length; i < 4; i++) ...<Widget>[
              const SizedBox(width: 6),
              const Expanded(child: SizedBox()),
            ],
          ],
        ),
      ],
    );
  }
}

/// One core: a square whose fill eases to [fraction] of full brightness.
class _Core extends StatelessWidget {
  const _Core({required this.fraction});

  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double target = (fraction ?? 0).clamp(0.0, 1.0);
    return AspectRatio(
      aspectRatio: 1,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: target),
        duration: GDesign.motion(context, GDesign.slow),
        curve: GDesign.enter,
        builder: (BuildContext context, double v, Widget? _) => DecoratedBox(
          decoration: BoxDecoration(
            color: fraction == null
                ? g.hairline
                : Color.lerp(g.card, g.accent, 0.12 + v * 0.88),
            borderRadius: BorderRadius.circular(6),
            boxShadow: v > 0.75
                ? <BoxShadow>[
                    BoxShadow(
                      color: g.accent.withValues(alpha: (v - 0.75) * 1.6),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// The short gold legs round a chip package.
class _PinPainter extends CustomPainter {
  const _PinPainter({required this.color, required this.pins});

  final Color color;
  final int pins;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const double inset = 22;
    const double leg = 6;
    for (int i = 0; i < pins; i++) {
      final double x = inset + (size.width - inset * 2) * i / (pins - 1);
      canvas
        ..drawLine(Offset(x, 1), Offset(x, 1 + leg), paint)
        ..drawLine(
          Offset(x, size.height - 1),
          Offset(x, size.height - 1 - leg),
          paint,
        );
    }
    final int side = math.max(4, (pins * size.height / size.width).round());
    for (int i = 0; i < side; i++) {
      final double y = inset + (size.height - inset * 2) * i / (side - 1);
      canvas
        ..drawLine(Offset(1, y), Offset(1 + leg, y), paint)
        ..drawLine(
          Offset(size.width - 1, y),
          Offset(size.width - 1 - leg, y),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color || old.pins != pins;
}

/// Charge as an outer ring and health as an inner one, the charge figure in
/// the middle. While charging, a bright spark runs round the charge ring.
class ChargeRing extends StatefulWidget {
  const ChargeRing({
    required this.percent,
    required this.charging,
    required this.caption,
    super.key,
    this.health,
  });

  final int? percent;
  final int? health;
  final bool charging;

  /// One line under the figure, such as "Charging".
  final String caption;

  @override
  State<ChargeRing> createState() => _ChargeRingState();
}

class _ChargeRingState extends State<ChargeRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spark = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ChargeRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Runs the spark only while charging and motion is allowed.
  void _sync() {
    final bool run =
        widget.charging && !MediaQuery.disableAnimationsOf(context);
    if (run && !_spark.isAnimating) {
      _spark.repeat();
    } else if (!run && _spark.isAnimating) {
      _spark.stop();
    }
  }

  @override
  void dispose() {
    _spark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double charge = (widget.percent ?? 0) / 100;
    final double? health = widget.health == null ? null : widget.health! / 100;
    return AspectRatio(
      aspectRatio: 1.5,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: GDesign.motion(context, const Duration(milliseconds: 900)),
        curve: GDesign.enter,
        builder: (BuildContext context, double grow, Widget? _) =>
            AnimatedBuilder(
              animation: _spark,
              builder: (BuildContext context, Widget? _) => CustomPaint(
                painter: _RingPainter(
                  charge: charge * grow,
                  health: health == null ? null : health * grow,
                  spark: widget.charging ? _spark.value : null,
                  // g.fill disappears on a dark card; a text tint shows.
                  track: g.text.withValues(alpha: 0.12),
                  chargeColor: g.accent,
                  healthColor: g.text.withValues(alpha: 0.55),
                  sparkColor: g.onAccent,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CountUpText(
                        value: widget.percent ?? 0,
                        format: (num v) => '${v.round()}%',
                        style: g.figures(g.largeTitle()),
                      ),
                      Text(widget.caption, style: g.footnote()),
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.charge,
    required this.health,
    required this.spark,
    required this.track,
    required this.chargeColor,
    required this.healthColor,
    required this.sparkColor,
  });

  final double charge;
  final double? health;
  final double? spark;
  final Color track;
  final Color chargeColor;
  final Color healthColor;
  final Color sparkColor;

  static const double _outer = 14;
  static const double _inner = 6;
  static const double _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2 - _outer / 2;
    final Rect outer = Rect.fromCircle(center: c, radius: r);
    final Rect inner = Rect.fromCircle(center: c, radius: r - _outer - 6);

    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    canvas
      ..drawArc(outer, 0, math.pi * 2, false, stroke(track, _outer))
      ..drawArc(
        outer,
        _start,
        math.pi * 2 * charge.clamp(0.0, 1.0),
        false,
        stroke(chargeColor, _outer),
      );

    if (health != null) {
      canvas
        ..drawArc(inner, 0, math.pi * 2, false, stroke(track, _inner))
        ..drawArc(
          inner,
          _start,
          math.pi * 2 * health!.clamp(0.0, 1.0),
          false,
          stroke(healthColor, _inner),
        );
    }

    // The spark travels the filled part of the charge ring only.
    if (spark != null && charge > 0.02) {
      final double angle = _start + math.pi * 2 * charge * spark!;
      final Offset at = c + Offset(math.cos(angle), math.sin(angle)) * r;
      canvas.drawCircle(
        at,
        _outer / 2 - 2,
        Paint()
          ..color = sparkColor.withValues(alpha: 0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.charge != charge ||
      old.health != health ||
      old.spark != spark ||
      old.track != track ||
      old.chargeColor != chargeColor;
}

/// A bar of equal segments, the first [fraction] of them lit, easing to new
/// readings. Used for memory, where a block count reads faster than a
/// percentage.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    required this.fraction,
    super.key,
    this.segments = 24,
    this.height = 28,
    this.alert = false,
  });

  final double fraction;
  final int segments;
  final double height;

  /// Lights the segments in the danger colour.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Color on = alert ? g.danger : g.accent;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: fraction.clamp(0.0, 1.0)),
      duration: GDesign.motion(context, GDesign.slow),
      curve: GDesign.enter,
      builder: (BuildContext context, double v, Widget? _) {
        final double lit = v * segments;
        return SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < segments; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // The boundary segment is partly lit.
                      color: Color.lerp(
                        g.text.withValues(alpha: 0.12),
                        on,
                        (lit - i).clamp(0.0, 1.0),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The screen drawn to its true shape, with a scan line sweeping down at a
/// speed tied to the refresh rate: twice as fast at 120 Hz as at 60 Hz.
class ScreenScale extends StatefulWidget {
  const ScreenScale({
    required this.widthPx,
    required this.heightPx,
    required this.refreshHz,
    super.key,
  });

  final int widthPx;
  final int heightPx;
  final double refreshHz;

  @override
  State<ScreenScale> createState() => _ScreenScaleState();
}

class _ScreenScaleState extends State<ScreenScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ScreenScale old) {
    super.didUpdateWidget(old);
    if (old.refreshHz != widget.refreshHz) _sync();
  }

  void _sync() {
    // 60 Hz sweeps once a second; faster panels sweep proportionally faster.
    final double hz = widget.refreshHz <= 0 ? 60 : widget.refreshHz;
    _scan.duration = Duration(milliseconds: (60000 / hz).round());
    if (MediaQuery.disableAnimationsOf(context)) {
      _scan.stop();
    } else {
      _scan.repeat();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int w = math.min(widget.widthPx, widget.heightPx);
    final int h = math.max(widget.widthPx, widget.heightPx);
    return SizedBox(
      height: 240,
      child: Center(
        child: AspectRatio(
          aspectRatio: w / h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: g.text,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            g.accent.withValues(alpha: 0.85),
                            g.accent.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _scan,
                      builder: (BuildContext context, Widget? _) => Align(
                        alignment: Alignment(0, -1 + 2 * _scan.value),
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                g.onAccent.withValues(alpha: 0),
                                g.onAccent.withValues(alpha: 0.45),
                                g.onAccent.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        '${widget.refreshHz.round()} Hz',
                        style: g.figures(g.headline(color: g.onAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A SIM card drawn as one: the clipped corner, the gold contact pad, and
/// the carrier printed on it. eSIMs are drawn as a small soldered chip.
class SimCardArt extends StatelessWidget {
  const SimCardArt({
    required this.carrier,
    required this.slot,
    required this.embedded,
    super.key,
  });

  final String carrier;
  final String slot;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    // Ink that reads on either card colour.
    final Color ink = embedded ? g.card : g.onAccent;
    return AspectRatio(
      aspectRatio: 0.75,
      child: ClipPath(
        clipper: embedded ? null : const _CutCorner(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: embedded ? g.text : g.accent,
            borderRadius: BorderRadius.circular(embedded ? 10 : 8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(GDesign.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(slot, style: g.caption(color: ink)),
                const Spacer(),
                Center(child: _Contacts(color: ink)),
                const Spacer(),
                Text(
                  carrier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: g.footnote(color: ink, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The six pad contact grid.
class _Contacts extends StatelessWidget {
  const _Contacts({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 34,
    child: CustomPaint(painter: _ContactPainter(color)),
  );
}

class _ContactPainter extends CustomPainter {
  const _ContactPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final RRect pad = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(pad, line)
      ..drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        line,
      )
      ..drawLine(
        Offset(0, size.height / 3),
        Offset(size.width, size.height / 3),
        line,
      )
      ..drawLine(
        Offset(0, size.height * 2 / 3),
        Offset(size.width, size.height * 2 / 3),
        line,
      );
  }

  @override
  bool shouldRepaint(_ContactPainter old) => old.color != color;
}

/// The diagonal clip on a SIM card's top right corner.
class _CutCorner extends CustomClipper<Path> {
  const _CutCorner();

  @override
  Path getClip(Size size) {
    final double cut = size.width * 0.22;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_CutCorner old) => false;
}
