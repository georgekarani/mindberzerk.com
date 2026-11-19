import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';
import 'package:video_player/video_player.dart';

import '../../../bridge/compress_api.g.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../state/storage_providers.dart';

/// The encoded sample against the original, full screen, on black.
///
/// The sample is the first seconds of the clip really encoded at the chosen
/// settings, which is what the estimate was worked out from. Switching
/// between the two keeps the playback position, so the same frame can be
/// compared.
class VideoPreviewPage extends ConsumerStatefulWidget {
  const VideoPreviewPage({
    required this.clip,
    required this.estimate,
    super.key,
  });

  final VideoCandidate clip;
  final VideoEstimate estimate;

  static Route<void> route({
    required VideoCandidate clip,
    required VideoEstimate estimate,
  }) => PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (BuildContext context, Animation<double> a, _) =>
        FadeTransition(
          opacity: a,
          child: VideoPreviewPage(clip: clip, estimate: estimate),
        ),
  );

  @override
  ConsumerState<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends ConsumerState<VideoPreviewPage> {
  VideoPlayerController? _controller;
  bool _original = false;
  bool _failed = false;

  /// Guards against an older load finishing after a newer one started.
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load(Duration.zero);
  }

  @override
  void dispose() {
    _token++;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load(Duration at) async {
    final int token = ++_token;
    final VideoPlayerController? old = _controller;
    setState(() {
      _controller = null;
      _failed = false;
    });
    await old?.dispose();

    final VideoPlayerController? next = _original
        ? await _originalSource()
        : _sampleSource();
    if (next == null) {
      if (mounted && token == _token) setState(() => _failed = true);
      return;
    }
    try {
      await next.initialize();
    } on Object {
      await next.dispose();
      if (mounted && token == _token) setState(() => _failed = true);
      return;
    }
    if (!mounted || token != _token) {
      await next.dispose();
      return;
    }
    setState(() => _controller = next);
    await next.setLooping(true);
    await next.seekTo(at);
    await next.play();
  }

  VideoPlayerController? _sampleSource() {
    final String? path = widget.estimate.samplePath;
    if (path == null) return null;
    final File file = File(path);
    return file.existsSync() ? VideoPlayerController.file(file) : null;
  }

  Future<VideoPlayerController?> _originalSource() async {
    final String? uri = await ref
        .read(storageBridgeProvider)
        .contentUri(widget.clip.fileId);
    return uri == null
        ? null
        : VideoPlayerController.contentUri(Uri.parse(uri));
  }

  Future<void> _show({required bool original}) async {
    if (original == _original) return;
    Haptics.select();
    final Duration at = _controller?.value.position ?? Duration.zero;
    setState(() => _original = original);
    await _load(at);
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    final VideoPlayerController? c = _controller;
    final bool ready = c != null && c.value.isInitialized;
    final int saving =
        widget.estimate.originalBytes - widget.estimate.estimatedBytes;

    return Material(
      color: const Color(0xFF000000),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            top: inset.top + 64,
            bottom: inset.bottom + 176,
            child: _failed
                ? Center(
                    child: Text(
                      _original
                          ? context.s('This phone cannot play the original')
                          : context.s('The sample is gone. Measure again.'),
                      style: g.body(color: g.muted),
                    ),
                  )
                : !ready
                ? Center(
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        color: g.accent,
                        strokeWidth: 2.2,
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: () => setState(
                      () => c.value.isPlaying ? c.pause() : c.play(),
                    ),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),
                    ),
                  ),
          ),
          Positioned(
            left: GDesign.space12,
            right: GDesign.space12,
            top: inset.top + GDesign.space8,
            child: Row(
              children: <Widget>[
                FloatIconButton(
                  icon: GIcons.back,
                  semanticLabel: MaterialLocalizations.of(
                    context,
                  ).backButtonTooltip,
                  onTap: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Center(
                    child: PhotoChip(
                      _original
                          ? context.s('Original')
                          : context.s1(
                              'After, first {} seconds',
                              widget.estimate.sampledMillis ~/ 1000,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: GDesign.touch),
              ],
            ),
          ),
          Positioned(
            left: GDesign.gutter,
            right: GDesign.gutter,
            bottom: inset.bottom + GDesign.space16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (ready)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: VideoProgressIndicator(
                      c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      colors: VideoProgressColors(
                        playedColor: g.accent,
                        bufferedColor: g.fill,
                        backgroundColor: g.hairline,
                      ),
                    ),
                  ),
                const SizedBox(height: GDesign.space12),
                Center(
                  child: PhotoChip(
                    saving > 0
                        ? '${GFormat.bytes(widget.estimate.originalBytes)} to '
                              'about ${GFormat.bytes(widget.estimate.estimatedBytes)}'
                        : context.s('No gain on this clip'),
                  ),
                ),
                const SizedBox(height: GDesign.space16),
                Segmented<bool>(
                  semanticLabel: context.s('Which version'),
                  segments: <(bool, String)>[
                    (true, context.s('Original')),
                    (false, context.s('After')),
                  ],
                  value: _original,
                  onChanged: (bool v) => _show(original: v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
