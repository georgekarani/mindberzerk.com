import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// Which moving picture an empty category shows.
enum EmptyKind { photos, video, statuses, messages, docs, audio, previews }

/// A small looping scene for an empty category, so an empty page still
/// moves. Each kind gets its own picture of what would be there.
///
/// [photos] are the user's own recent pictures, still on the phone; the
/// photo and preview scenes use them when there are any. With reduced
/// motion every scene holds one still frame.
class EmptyScene extends StatefulWidget {
  const EmptyScene({
    required this.kind,
    super.key,
    this.photos = const <ImageProvider>[],
  });

  final EmptyKind kind;
  final List<ImageProvider> photos;

  /// Height every scene is drawn in.
  static const double height = 168;

  @override
  State<EmptyScene> createState() => _EmptySceneState();
}

class _EmptySceneState extends State<EmptyScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: _period(widget.kind),
  );

  /// Loop length per scene: slow drifts, quicker chatter.
  static Duration _period(EmptyKind kind) => switch (kind) {
    EmptyKind.messages => const Duration(milliseconds: 4200),
    EmptyKind.audio => const Duration(milliseconds: 2400),
    EmptyKind.previews => const Duration(milliseconds: 5200),
    _ => const Duration(seconds: 6),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      // A representative still frame.
      _loop
        ..stop()
        ..value = 0.3;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void didUpdateWidget(EmptyScene old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind) _loop.duration = _period(widget.kind);
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: EmptyScene.height,
      child: AnimatedBuilder(
        animation: _loop,
        builder: (BuildContext context, Widget? _) {
          final double t = _loop.value;
          return switch (widget.kind) {
            EmptyKind.photos => _PhotoStack(t: t, photos: widget.photos),
            EmptyKind.video => _PhotoStack(
              t: t,
              photos: widget.photos,
              video: true,
            ),
            EmptyKind.statuses => _StatusRings(t: t),
            EmptyKind.messages => _Bubbles(t: t),
            EmptyKind.docs => _PagesFan(t: t),
            EmptyKind.audio => _Waveform(t: t),
            EmptyKind.previews => _Pixels(
              t: t,
              photo: widget.photos.firstOrNull,
            ),
          };
        },
      ),
    );
  }
}

/// Four prints in a loose pile, each drifting and tilting on its own phase.
/// For video the top print carries a play mark.
class _PhotoStack extends StatelessWidget {
  const _PhotoStack({
    required this.t,
    required this.photos,
    this.video = false,
  });

  final double t;
  final List<ImageProvider> photos;
  final bool video;

  /// Resting offset and angle of each print, back to front.
  static const List<(double, double, double)> _rest =
      <(double, double, double)>[
        (-46, 6, -0.22),
        (40, 2, 0.18),
        (-14, -4, -0.06),
        (12, 4, 0.08),
      ];

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double a = t * math.pi * 2;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        for (int i = 0; i < _rest.length; i++)
          Transform.translate(
            offset: Offset(
              _rest[i].$1 + 4 * math.sin(a + i * 1.3),
              _rest[i].$2 + 5 * math.cos(a + i * 0.9),
            ),
            child: Transform.rotate(
              angle: _rest[i].$3 + 0.05 * math.sin(a + i * 2.1),
              child: Container(
                width: 92,
                height: 116,
                decoration: BoxDecoration(
                  color: g.fill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: g.card, width: 3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: g.shadow,
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (photos.isNotEmpty)
                      SizedPhoto(image: photos[i % photos.length])
                    else
                      Icon(
                        video ? GIcons.video : GIcons.photos,
                        size: 28,
                        color: g.faint,
                      ),
                    if (video && i == _rest.length - 1)
                      Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: g.scrim,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            GIcons.video,
                            size: 18,
                            color: g.onAccent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A status ring of dashes, slowly turning, with two softer rings breathing
/// out from it.
class _StatusRings extends StatelessWidget {
  const _StatusRings({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return CustomPaint(
      painter: _RingsPainter(t: t, ring: g.accent),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: g.fill, shape: BoxShape.circle),
          child: Icon(GIcons.status, size: 28, color: g.muted),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.t, required this.ring});

  final double t;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    // Two breathing halos, half a loop apart.
    for (int i = 0; i < 2; i++) {
      final double p = (t + i / 2) % 1;
      canvas.drawCircle(
        c,
        42 + 34 * p,
        Paint()
          ..color = ring.withValues(alpha: 0.35 * (1 - p))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // The dashed status ring, one dash per status, turning.
    const int dashes = 6;
    const double gap = 0.18;
    final Rect box = Rect.fromCircle(center: c, radius: 40);
    final Paint dash = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < dashes; i++) {
      final double start = t * math.pi * 2 + i * math.pi * 2 / dashes;
      canvas.drawArc(box, start, math.pi * 2 / dashes - gap, false, dash);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.ring != ring;
}

/// Chat bubbles popping in one after another, then clearing, like a
/// conversation that keeps starting.
class _Bubbles extends StatelessWidget {
  const _Bubbles({required this.t});

  final double t;

  /// Side (true is the user's) and width of each bubble.
  static const List<(bool, double)> _lines = <(bool, double)>[
    (false, 132),
    (true, 96),
    (false, 168),
    (true, 72),
  ];

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < _lines.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 8),
            Align(
              alignment: _lines[i].$1
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Transform.scale(
                scale: _pop(i),
                alignment: _lines[i].$1
                    ? Alignment.bottomRight
                    : Alignment.bottomLeft,
                child: Opacity(
                  opacity: _pop(i).clamp(0.0, 1.0),
                  child: Container(
                    width: _lines[i].$2,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _lines[i].$1 ? g.accent : g.fill,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(_lines[i].$1 ? 14 : 4),
                        bottomRight: Radius.circular(_lines[i].$1 ? 4 : 14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Bubble i appears at its slot with a slight overshoot, and everything
  /// fades out together near the end of the loop.
  double _pop(int i) {
    final double start = 0.08 + i * 0.16;
    if (t < start) return 0;
    if (t > 0.9) return math.max(0, 1 - (t - 0.9) / 0.1);
    final double p = ((t - start) / 0.1).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(p);
  }
}

/// Three pages fanning open from a corner and closing again.
class _PagesFan extends StatelessWidget {
  const _PagesFan({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    // Open for the middle of the loop, closed at the ends.
    final double open = Curves.easeInOutCubic.transform(
      (math.sin(t * math.pi * 2 - math.pi / 2) + 1) / 2,
    );
    return Center(
      child: SizedBox(
        width: 120,
        height: 140,
        child: Stack(
          children: <Widget>[
            for (int i = 0; i < 3; i++)
              Positioned.fill(
                child: Transform.rotate(
                  alignment: Alignment.bottomLeft,
                  angle: (i - 2) * 0.22 * open,
                  child: _Page(g: g, top: i == 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.g, required this.top});

  final GDesignTheme g;
  final bool top;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: top ? g.card : g.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: g.hairline),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: g.shadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 52,
            height: 7,
            color: g.accent.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 10),
          for (final double w in <double>[1, 0.86, 0.94, 0.6, 0.9, 0.72])
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: FractionallySizedBox(
                widthFactor: w,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: g.text.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A voice note waveform bouncing gently, as if it were playing.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.t});

  final double t;

  static const int _bars = 22;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double a = t * math.pi * 2;
    return Center(
      child: SizedBox(
        height: 96,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < _bars; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 4),
              Container(
                width: 5,
                // Two waves of different speed, so it never looks mechanical.
                height:
                    14 +
                    70 *
                        (0.5 +
                                0.3 * math.sin(a * 2 + i * 0.55) +
                                0.2 * math.sin(a * 3 - i * 0.9))
                            .clamp(0.05, 1.0),
                decoration: BoxDecoration(
                  color: g.accent.withValues(
                    alpha: 0.45 + 0.55 * ((i / _bars - t).abs() < 0.15 ? 1 : 0),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A picture resolving from coarse blocks to sharp and back, the way a
/// preview is a small copy of something larger. Uses one of the user's own
/// photos when there is one, a grid of tinted blocks otherwise.
class _Pixels extends StatelessWidget {
  const _Pixels({required this.t, required this.photo});

  final double t;
  final ImageProvider? photo;

  /// Block counts across, coarse to fine and back.
  static const List<int> _steps = <int>[4, 8, 16, 32, 96, 32, 16, 8];

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int n = _steps[(t * _steps.length).floor() % _steps.length];
    final ImageProvider? source = photo;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox.square(
          dimension: 140,
          child: source == null
              ? _Blocks(n: math.min(n, 12), g: g, t: t)
              : Image(
                  // Decoding at n pixels and drawing without smoothing is
                  // what makes the blocks.
                  image: ResizeImage(source, width: n, height: n),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                  gaplessPlayback: true,
                ),
        ),
      ),
    );
  }
}

/// Fallback pixel art: a grid whose cells pulse in accent tints.
class _Blocks extends StatelessWidget {
  const _Blocks({required this.n, required this.g, required this.t});

  final int n;
  final GDesignTheme g;
  final double t;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: n,
      children: <Widget>[
        for (int i = 0; i < n * n; i++)
          ColoredBox(
            color: g.accent.withValues(
              alpha:
                  0.15 +
                  0.6 *
                      ((math.sin(i * 1.7 + t * math.pi * 2) + 1) / 2) *
                      ((i % 3) / 2),
            ),
          ),
      ],
    );
  }
}
