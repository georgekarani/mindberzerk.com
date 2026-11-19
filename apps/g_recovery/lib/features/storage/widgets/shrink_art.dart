import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/compress_api.g.dart';
import '../../../bridge/compress_bridge.dart';
import '../../../core/format.dart';
import '../../../ui/file_thumbnail.dart';
import '../state/storage_providers.dart';

/// The Make smaller card's picture: one of the user's own large photos
/// shrinking in place while its real file size counts down.
///
/// The blurred photo fills the card; the sharp copy draws in on a spring,
/// corner marks closing with it, and a glass pill counts from the original
/// size to the size a re-encode at the current quality actually produced.
/// Both figures are measured for this file. Until the measurement lands the
/// pill shows only the original size, and under reduced motion the picture
/// rests in its shrunk state.
class ShrinkArt extends ConsumerStatefulWidget {
  const ShrinkArt({super.key, this.compact = false});

  /// Small card: tighter pill, no percentage.
  final bool compact;

  @override
  ConsumerState<ShrinkArt> createState() => _ShrinkArtState();
}

class _ShrinkArtState extends ConsumerState<ShrinkArt>
    with SingleTickerProviderStateMixin {
  /// One loop: rest, shrink, hold, spring back.
  static const Duration _loop = Duration(milliseconds: 3600);

  /// How far the photo draws in, matching a typical re-encode by eye.
  static const double _shrunk = 0.74;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _loop,
  );

  late final Animation<double> _squeeze =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(tween: ConstantTween<double>(0), weight: 14),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0,
            end: 1,
          ).chain(CurveTween(curve: Springs.standardCurve)),
          weight: 30,
        ),
        TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 36),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 0,
          ).chain(CurveTween(curve: Springs.softCurve)),
          weight: 20,
        ),
      ]).animate(_clock);

  /// The counter runs a little behind the picture so the eye reads both.
  late final Animation<double> _count = CurvedAnimation(
    parent: _clock,
    curve: const Interval(0.18, 0.50, curve: Curves.easeOutCubic),
  );

  /// Ids for the preview request, kept as one list instance so the family
  /// key stays equal between builds and the measurement runs once.
  List<String>? _ids;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _clock
        ..stop()
        ..value = 0.6;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// The largest still photo on offer, which shows the change best.
  static CompressCandidate? _pick(List<CompressCandidate> all) {
    CompressCandidate? best;
    for (final CompressCandidate c in all) {
      if (c.kind == 'video') continue;
      if (best == null || c.sizeBytes > best.sizeBytes) best = c;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final CompressCandidate? photo = _pick(
      ref.watch(compressCandidatesProvider).value ??
          const <CompressCandidate>[],
    );
    if (photo == null) return _Fallback(g: g);

    if (_ids == null || _ids!.single != photo.fileId) {
      _ids = <String>[photo.fileId];
    }
    final int quality = ref.watch(compressQualityProvider);
    final CompressPreview? measured = ref
        .watch(compressPreviewProvider((ids: _ids!, quality: quality)))
        .value
        ?.firstOrNull;
    final int before = photo.sizeBytes;
    final int? after = measured == null || measured.newBytes >= before
        ? null
        : measured.newBytes;

    final ImageProvider image = FileThumbnail(
      fileId: photo.fileId,
      bridge: ref.watch(storageBridgeProvider),
      maxPixels: 720,
    );

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The same photo, blurred and dimmed, as the ground it shrinks on.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: SizedPhoto(image: image),
          ),
          ColoredBox(color: g.scrim),
          AnimatedBuilder(
            animation: _clock,
            builder: (BuildContext context, Widget? child) {
              final double t = _squeeze.value;
              final double scale = 1 - (1 - _shrunk) * t;
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Transform.scale(
                    scale: scale,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        GDesign.tileRadius * t,
                      ),
                      child: child,
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _Corners(
                        inset: scale,
                        color: g.onAccent,
                        opacity: t,
                      ),
                    ),
                  ),
                ],
              );
            },
            child: SizedPhoto(image: image),
          ),
          PositionedDirectional(
            start: GDesign.space8,
            end: GDesign.space8,
            bottom: GDesign.space8,
            child: Center(
              child: AnimatedBuilder(
                animation: _count,
                builder: (BuildContext context, _) => _Pill(
                  before: before,
                  after: after,
                  progress: _count.value * (_squeeze.value > 0 ? 1 : 0),
                  compact: widget.compact,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The size counter: original size, ticking to the measured result.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.before,
    required this.after,
    required this.progress,
    required this.compact,
  });

  final int before;
  final int? after;
  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int? target = after;
    final int now = target == null
        ? before
        : (before - (before - target) * progress).round();
    final bool done = target != null && progress >= 0.999;
    final TextStyle style = g.figures(
      g.footnote(color: g.text, weight: FontWeight.w600),
    );

    return GlassSurface(
      borderRadius: BorderRadius.circular(GDesign.chipRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GDesign.space12,
          vertical: GDesign.space4 + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(GFormat.bytes(now), style: style),
            if (!compact && target != null) ...<Widget>[
              const SizedBox(width: GDesign.space8),
              AnimatedOpacity(
                opacity: done ? 1 : 0,
                duration: GDesign.motion(context, GDesign.fast),
                child: Text(
                  '-${(100 * (1 - target / before)).round()}%',
                  style: style.copyWith(color: g.accentText),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Four corner marks that close in with the photo, like a crop frame.
class _Corners extends CustomPainter {
  const _Corners({
    required this.inset,
    required this.color,
    required this.opacity,
  });

  /// The photo's current scale; the marks sit just outside its edges.
  final double inset;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    final double w = size.width * inset;
    final double h = size.height * inset;
    final Rect box = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: w + 10,
      height: h + 10,
    );
    final double arm = math.min(18, box.shortestSide / 5);
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.9 * opacity.clamp(0.0, 1.0))
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final (Offset corner, double dx, double dy)
        in <(Offset, double, double)>[
          (box.topLeft, 1, 1),
          (box.topRight, -1, 1),
          (box.bottomLeft, 1, -1),
          (box.bottomRight, -1, -1),
        ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + arm * dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx + arm * dx, corner.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Corners old) =>
      old.inset != inset || old.opacity != opacity || old.color != color;
}

/// No photo worth shrinking: a quiet glyph rather than an empty box.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.g});

  final GDesignTheme g;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: g.isDark ? g.card : g.fill,
    child: Center(child: Icon(GIcons.archive, size: 40, color: g.muted)),
  );
}
