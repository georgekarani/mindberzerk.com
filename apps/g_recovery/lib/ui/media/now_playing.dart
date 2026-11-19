import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'playable_media.dart';

/// What is playing, app-wide. One thing at a time: starting another stops
/// the last, so a voice note never talks over a video.
@immutable
class NowPlaying {
  const NowPlaying({required this.media, this.controller, this.failed = false});

  final PlayableMedia media;

  /// Null while the file is being opened.
  final VideoPlayerController? controller;

  /// The phone could not open or decode it.
  final bool failed;

  bool get ready => controller != null && controller!.value.isInitialized;
}

class NowPlayingController extends Notifier<NowPlaying?> {
  /// Bumped on every start, so a slow open that finishes after the user
  /// moved on is thrown away instead of playing.
  int _token = 0;

  @override
  NowPlaying? build() {
    ref.onDispose(() => state?.controller?.dispose());
    return null;
  }

  /// Plays [media], or pauses and resumes it if it is already the current
  /// one. Video loops; audio plays once.
  Future<void> start(PlayableMedia media, {bool muted = false}) async {
    final NowPlaying? now = state;
    if (now != null && now.media == media) {
      if (now.ready) toggle();
      return;
    }
    await stop();
    final int token = ++_token;
    state = NowPlaying(media: media);

    final String? uri = await media.resolve();
    if (token != _token) return;
    if (uri == null) {
      state = NowPlaying(media: media, failed: true);
      return;
    }

    final VideoPlayerController controller = VideoPlayerController.contentUri(
      Uri.parse(uri),
    );
    try {
      await controller.initialize();
    } catch (_) {
      // A codec this phone lacks, or a trashed row the system will not
      // decode. Both are ordinary; the caller shows its fallback.
      await controller.dispose();
      if (token == _token) state = NowPlaying(media: media, failed: true);
      return;
    }
    if (token != _token) {
      await controller.dispose();
      return;
    }
    await controller.setLooping(media.isVideo);
    await controller.setVolume(muted ? 0 : 1);
    await controller.play();
    state = NowPlaying(media: media, controller: controller);
  }

  /// Pauses or resumes the current media.
  void toggle() {
    final VideoPlayerController? c = state?.controller;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  Future<void> seekTo(Duration to) async {
    final VideoPlayerController? c = state?.controller;
    if (c == null) return;
    final Duration end = c.value.duration;
    await c.seekTo(to < Duration.zero ? Duration.zero : (to > end ? end : to));
  }

  Future<void> seekBy(Duration by) async {
    final VideoPlayerController? c = state?.controller;
    if (c == null) return;
    await seekTo(c.value.position + by);
  }

  Future<void> setMuted({required bool muted}) async =>
      state?.controller?.setVolume(muted ? 0 : 1);

  /// Cycles 1x, 1.5x, 2x.
  Future<void> nextSpeed() async {
    final VideoPlayerController? c = state?.controller;
    if (c == null) return;
    final double now = c.value.playbackSpeed;
    await c.setPlaybackSpeed(now < 1.25 ? 1.5 : (now < 1.75 ? 2 : 1));
  }

  /// Stops and releases whatever is playing.
  Future<void> stop() async {
    _token++;
    final VideoPlayerController? c = state?.controller;
    state = null;
    await c?.dispose();
  }

  /// Stops [media] only if it is the one playing, for screens closing.
  Future<void> stopIf(PlayableMedia media) async {
    if (state?.media == media) await stop();
  }
}

final NotifierProvider<NowPlayingController, NowPlaying?> nowPlayingProvider =
    NotifierProvider<NowPlayingController, NowPlaying?>(
      NowPlayingController.new,
    );
