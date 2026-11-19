import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';
import 'package:video_player/video_player.dart';

import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import 'media_stage.dart';
import 'now_playing.dart';
import 'now_playing_page.dart';

/// Audio that keeps playing after its screen closes, as a glass capsule
/// above the tab bar: cover, title, time left, play or pause, and close.
/// Slides up when audio starts and away when it stops.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NowPlaying? now = ref.watch(nowPlayingProvider);
    final bool show = now != null && !now.media.isVideo && now.ready;

    return AnimatedSwitcher(
      duration: GDesign.motion(context, Springs.standardCurve.settle),
      switchInCurve: Springs.standardCurve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.6),
            end: Offset.zero,
          ).animate(a),
          child: child,
        ),
      ),
      child: show
          ? _Capsule(key: ValueKey<String>(now.media.id), now: now)
          : const SizedBox.shrink(),
    );
  }
}

class _Capsule extends ConsumerWidget {
  const _Capsule({required this.now, super.key});

  final NowPlaying now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final VideoPlayerController c = now.controller!;
    final NowPlayingController player = ref.read(nowPlayingProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(GDesign.cardRadius),
        shadow: true,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (BuildContext context, VideoPlayerValue v, _) {
            final int total = v.duration.inMilliseconds;
            final double played = total <= 0
                ? 0
                : (v.position.inMilliseconds / total).clamp(0.0, 1.0);
            return Stack(
              children: <Widget>[
                // The capsule grows into the full player from any screen.
                Pressable(
                  onTap: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(NowPlayingPage.route(now.media)),
                  semanticLabel: context.s('Open player'),
                  scale: 0.98,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    child: Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox.square(
                            dimension: 40,
                            child: now.media.art == null
                                ? ColoredBox(
                                    color: g.fill,
                                    child: Icon(GIcons.audio, color: g.muted),
                                  )
                                : Image(
                                    image: now.media.art!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: g.fill,
                                      child: Icon(GIcons.audio, color: g.muted),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: GDesign.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                now.media.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: g.footnote(
                                  color: g.text,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '-${GFormat.duration(v.duration - v.position)}',
                                style: g.figures(g.footnote()),
                              ),
                            ],
                          ),
                        ),
                        PlayRing(media: now.media, size: 34),
                        NavAction.icon(
                          icon: GIcons.close,
                          semanticLabel: context.s('Stop'),
                          onTap: player.stop,
                        ),
                      ],
                    ),
                  ),
                ),
                // A hairline of progress along the bottom edge.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2,
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: played,
                    child: ColoredBox(color: g.accent),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
