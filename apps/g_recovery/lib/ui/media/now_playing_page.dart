import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../core/i18n/g_strings.dart';
import 'media_stage.dart';
import 'now_playing.dart';
import 'playable_media.dart';

/// The full player for whatever is playing, opened from the mini player on
/// any screen. Closing it leaves the audio playing in the capsule.
class NowPlayingPage extends ConsumerWidget {
  const NowPlayingPage({required this.media, super.key});

  final PlayableMedia media;

  /// Slides up over the tab bar, like the capsule growing into a page.
  static Route<void> route(PlayableMedia media) => PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: GDesign.slow,
    reverseTransitionDuration: GDesign.normal,
    pageBuilder: (_, _, _) => NowPlayingPage(media: media),
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> a,
          Animation<double> _,
          Widget child,
        ) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: GDesign.enter)),
          child: child,
        ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);

    // Stopped from elsewhere, or moved on to another file: nothing to show.
    ref.listen<NowPlaying?>(nowPlayingProvider, (_, NowPlaying? next) {
      if (next == null || next.media != media) Navigator.of(context).maybePop();
    });

    return Material(
      color: g.ground,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: GDesign.navBarHeight),
                child: MediaStage(
                  media: media,
                  bottomInset: GDesign.space16,
                  fallback: Center(
                    child: Icon(GIcons.audio, size: 48, color: g.muted),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SizedBox(
              height: GDesign.navBarHeight,
              child: Row(
                children: <Widget>[
                  NavAction.icon(
                    icon: GIcons.down,
                    semanticLabel: context.s('Close'),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: g.body(weight: FontWeight.w600),
                    ),
                  ),
                  // Balances the close button so the title stays centred.
                  const SizedBox(width: GDesign.touch),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
