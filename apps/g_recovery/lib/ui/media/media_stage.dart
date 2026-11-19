import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';
import 'package:video_player/video_player.dart';

import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import 'now_playing.dart';
import 'playable_media.dart';

/// A video or audio file, playing, with its controls.
///
/// Video fills the stage; audio shows its cover over a waveform. The
/// controls sit [bottomInset] above the bottom so a viewer's own bars stay
/// clear. In [compact] form (a peek) there are no controls and the sound is
/// off. Video stops when the stage closes; audio keeps playing and moves to
/// the mini player.
class MediaStage extends ConsumerStatefulWidget {
  const MediaStage({
    required this.media,
    required this.fallback,
    super.key,
    this.bottomInset = 0,
    this.compact = false,
  });

  final PlayableMedia media;

  /// Shown when the phone cannot play the file.
  final Widget fallback;
  final double bottomInset;
  final bool compact;

  @override
  ConsumerState<MediaStage> createState() => _MediaStageState();
}

class _MediaStageState extends ConsumerState<MediaStage>
    with SingleTickerProviderStateMixin {
  late final NowPlayingController _player;

  /// Drives the waveform's idle movement while audio plays.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _player = ref.read(nowPlayingProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reopening what is already playing (from the mini player) must not
      // pause it: start() toggles when handed the current media.
      if (ref.read(nowPlayingProvider)?.media == widget.media) return;
      _player.start(widget.media, muted: widget.compact);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    if (widget.media.isVideo || widget.compact) {
      // After the frame: providers must not change while the tree unmounts.
      final PlayableMedia media = widget.media;
      final NowPlayingController player = _player;
      WidgetsBinding.instance.addPostFrameCallback((_) => player.stopIf(media));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NowPlaying? now = ref.watch(nowPlayingProvider);
    final bool mine = now != null && now.media == widget.media;
    if (mine && now.failed) return widget.fallback;

    final VideoPlayerController? c = mine ? now.controller : null;
    if (c == null || !c.value.isInitialized) {
      return _Poster(
        media: widget.media,
        loading: mine,
        onPlay: () => _player.start(widget.media, muted: widget.compact),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (BuildContext context, VideoPlayerValue v, _) {
        if (!widget.media.isVideo) {
          if (v.isPlaying && !_pulse.isAnimating) {
            _pulse.repeat(reverse: true);
          } else if (!v.isPlaying && _pulse.isAnimating) {
            _pulse.stop();
          }
        }
        final Widget picture = widget.media.isVideo
            ? Center(
                child: AspectRatio(
                  aspectRatio: v.aspectRatio,
                  child: VideoPlayer(c),
                ),
              )
            : _AudioFace(media: widget.media, value: v, pulse: _pulse);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _player.toggle,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              picture,
              if (widget.media.isVideo)
                Center(child: _PauseMark(visible: !v.isPlaying)),
              if (!widget.compact)
                Positioned(
                  left: GDesign.gutter,
                  right: GDesign.gutter,
                  bottom: widget.bottomInset + GDesign.space16,
                  child: _Controls(value: v, player: _player),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Before playback: the cover with a play button, or a quiet spinner while
/// the file opens.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.media,
    required this.loading,
    required this.onPlay,
  });

  final PlayableMedia media;
  final bool loading;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : onPlay,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (media.art != null)
            Center(
              child: media.isVideo
                  ? Image(
                      image: media.art!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : _Cover(image: media.art),
            ),
          Center(
            child: loading
                ? SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: g.text,
                    ),
                  )
                : const _PauseMark(visible: true),
          ),
        ],
      ),
    );
  }
}

/// The round play mark over a paused video, fading and growing in.
class _PauseMark extends StatelessWidget {
  const _PauseMark({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return IgnorePointer(
      child: AnimatedScale(
        scale: visible ? 1 : 0.7,
        duration: GDesign.motion(context, Springs.snappyCurve.settle),
        curve: Springs.snappyCurve,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: GDesign.motion(context, GDesign.fast),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(36),
            child: SizedBox.square(
              dimension: 72,
              child: Icon(Icons.play_arrow_rounded, size: 40, color: g.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Audio: the cover, the title, and a waveform that fills as it plays and
/// breathes while it does.
class _AudioFace extends StatelessWidget {
  const _AudioFace({
    required this.media,
    required this.value,
    required this.pulse,
  });

  final PlayableMedia media;
  final VideoPlayerValue value;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double played = _fraction(value);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedScale(
            scale: value.isPlaying ? 1 : 0.92,
            duration: GDesign.motion(context, Springs.softCurve.settle),
            curve: Springs.softCurve,
            child: _Cover(image: media.art),
          ),
          const SizedBox(height: GDesign.space24),
          Text(
            media.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: g.headline(),
          ),
          const SizedBox(height: GDesign.space24),
          SizedBox(
            height: 56,
            child: AnimatedBuilder(
              animation: pulse,
              builder: (BuildContext context, _) => CustomPaint(
                size: Size.infinite,
                painter: Waveform(
                  seed: media.id.hashCode,
                  played: played,
                  breath: value.isPlaying ? pulse.value : 0,
                  on: g.accent,
                  off: g.isDark ? g.hairline : g.fill,
                ),
              ),
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}

/// A square cover with rounded corners, or the audio glyph without one.
class _Cover extends StatelessWidget {
  const _Cover({required this.image});

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Widget glyph = ColoredBox(
      color: g.isDark ? g.card : g.fill,
      child: Icon(GIcons.audio, size: 64, color: g.muted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(GDesign.cardRadius),
      child: SizedBox.square(
        dimension: 220,
        child: image == null
            ? glyph
            : Image(
                image: image!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => glyph,
              ),
      ),
    );
  }
}

/// Bars of a stand-in waveform, the same for the same file every time,
/// filled up to [played] and swaying a little with [breath].
class Waveform extends CustomPainter {
  const Waveform({
    required this.seed,
    required this.played,
    required this.on,
    required this.off,
    this.breath = 0,
    this.bars = 48,
  });

  final int seed;
  final double played;
  final double breath;
  final Color on;
  final Color off;
  final int bars;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random random = math.Random(seed);
    const double gap = 3;
    final double width = (size.width - gap * (bars - 1)) / bars;
    final Paint paint = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < bars; i++) {
      final double base = 0.25 + random.nextDouble() * 0.75;
      final double sway =
          1 + 0.12 * breath * math.sin(i * 0.9 + breath * math.pi);
      final double h = (size.height * base * sway).clamp(4, size.height);
      final double x = i * (width + gap);
      paint.color = (i + 0.5) / bars <= played ? on : off;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, width, h),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(Waveform old) =>
      old.played != played ||
      old.breath != breath ||
      old.seed != seed ||
      old.on != on;
}

double _fraction(VideoPlayerValue v) {
  final int total = v.duration.inMilliseconds;
  if (total <= 0) return 0;
  return (v.position.inMilliseconds / total).clamp(0.0, 1.0);
}

/// Scrubber, times, and the buttons: mute, back 15, play, ahead 15, speed.
class _Controls extends StatelessWidget {
  const _Controls({required this.value, required this.player});

  final VideoPlayerValue value;
  final NowPlayingController player;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final TextStyle time = g.figures(g.footnote(color: g.text));
    final Duration left = value.duration - value.position;
    final bool muted = value.volume == 0;

    return GlassSurface(
      borderRadius: BorderRadius.circular(GDesign.cardRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GDesign.space16,
          GDesign.space8,
          GDesign.space16,
          GDesign.space4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Scrubber(
              fraction: _fraction(value),
              onSeek: (double f) => player.seekTo(value.duration * f),
            ),
            Row(
              children: <Widget>[
                Text(GFormat.duration(value.position), style: time),
                const Spacer(),
                Text('-${GFormat.duration(left)}', style: time),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _Round(
                  icon: muted ? Icons.volume_off_rounded : GIcons.volume,
                  label: muted ? context.s('Sound on') : context.s('Mute'),
                  dim: muted,
                  onTap: () => player.setMuted(muted: !muted),
                ),
                _Round(
                  icon: GIcons.undo,
                  label: context.s('Back 15 seconds'),
                  onTap: () => player.seekBy(const Duration(seconds: -15)),
                ),
                _Round(
                  icon: value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  label: value.isPlaying
                      ? context.s('Pause')
                      : context.s('Play'),
                  big: true,
                  onTap: player.toggle,
                ),
                _Round(
                  icon: GIcons.refresh,
                  label: context.s('Ahead 15 seconds'),
                  onTap: () => player.seekBy(const Duration(seconds: 15)),
                ),
                Pressable(
                  onTap: player.nextSpeed,
                  semanticLabel: context.s('Speed'),
                  child: SizedBox(
                    width: GDesign.touch,
                    height: GDesign.touch,
                    child: Center(
                      child: Text(
                        '${_speed(value.playbackSpeed)}x',
                        style: g.figures(
                          g.footnote(color: g.text, weight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _speed(double s) =>
      s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.label,
    required this.onTap,
    this.big = false,
    this.dim = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool big;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      scale: 0.88,
      child: SizedBox.square(
        dimension: big ? 56 : GDesign.touch,
        child: Icon(icon, size: big ? 36 : 22, color: dim ? g.muted : g.text),
      ),
    );
  }
}

/// A slim progress bar that thickens under the finger and seeks on release.
class Scrubber extends StatefulWidget {
  const Scrubber({required this.fraction, required this.onSeek, super.key});

  final double fraction;
  final ValueChanged<double> onSeek;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  /// Where the finger is, while dragging.
  double? _drag;

  double _at(Offset local, double width) => (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = box.maxWidth;
        final double shown = _drag ?? widget.fraction;
        final bool active = _drag != null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (DragStartDetails d) {
            Haptics.select();
            setState(() => _drag = _at(d.localPosition, w));
          },
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              setState(() => _drag = _at(d.localPosition, w)),
          onHorizontalDragEnd: (_) {
            final double f = _drag ?? widget.fraction;
            setState(() => _drag = null);
            widget.onSeek(f);
          },
          onTapUp: (TapUpDetails d) => widget.onSeek(_at(d.localPosition, w)),
          child: SizedBox(
            height: 28,
            child: Center(
              child: AnimatedContainer(
                duration: GDesign.motion(context, GDesign.fast),
                height: active ? 8 : 4,
                decoration: BoxDecoration(
                  color: g.text.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: shown,
                  child: Container(
                    decoration: BoxDecoration(
                      color: g.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A round play button with a ring that fills as the file plays, for rows
/// of audio and video. Tapping plays here without leaving the list.
class PlayRing extends ConsumerWidget {
  const PlayRing({required this.media, super.key, this.size = 40});

  final PlayableMedia media;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final NowPlaying? now = ref.watch(nowPlayingProvider);
    final bool mine = now != null && now.media == media;
    final VideoPlayerController? c = mine ? now.controller : null;

    Widget ring(double fraction, bool playing) => Pressable(
      onTap: () => ref.read(nowPlayingProvider.notifier).start(media),
      semanticLabel: playing ? context.s('Pause') : context.s('Play'),
      scale: 0.88,
      child: SizedBox.square(
        dimension: GDesign.touch,
        child: Center(
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _Ring(
                fraction: fraction,
                track: g.isDark ? g.hairline : g.fill,
                fill: g.accent,
              ),
              child: Center(
                child: mine && c == null && !now.failed
                    ? SizedBox.square(
                        dimension: size * 0.4,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: g.accentText,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: size * 0.55,
                        color: g.accentText,
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    if (c == null) return ring(0, false);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (BuildContext context, VideoPlayerValue v, _) =>
          ring(_fraction(v), v.isPlaying),
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = (Offset.zero & size).deflate(1.5);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(box, 0, math.pi * 2, false, p..color = track);
    if (fraction > 0) {
      canvas.drawArc(
        box,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        p..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}
