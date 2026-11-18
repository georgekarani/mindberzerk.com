/// Wallpaper parallax and the edge handle's gesture exclusion. PHASE 8.
///
/// The wallpaper is drawn by WindowManager under a transparent window, so Dart
/// never holds it. Panning it means asking the wallpaper service, through the
/// Activity, because the call needs a window token. See `WallpaperOffsets.kt`
/// for the native half and for the phones where a pan correctly does nothing.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../shells/safe_page.dart';

/// The one channel. Matches `WallpaperOffsets.CHANNEL` in Kotlin.
const _channel = MethodChannel('g_launcher/wallpaper_offsets');

/// The calls the launcher makes on its own window.
abstract final class LauncherWindow {
  /// Pan the wallpaper; [x] is 0 for the far left, 1 for the far right.
  /// Fails quietly: a wallpaper that did not move is never worth a crash.
  static Future<void> setWallpaperOffset(double x) async {
    try {
      await _channel.invokeMethod<bool>('setOffset', {'x': x.clamp(0.0, 1.0)});
    } on PlatformException catch (e) {
      debugPrint('wallpaper offset failed: ${e.message}');
    } on MissingPluginException {
      // Tests and any host without the Activity half.
    }
  }

  /// Keep Android's back gesture off [rects], in logical pixels. An empty list
  /// gives every edge back to the system.
  static Future<void> setGestureExclusion(List<Rect> rects) async {
    try {
      await _channel.invokeMethod<bool>('setExclusion', {
        'rects': [
          for (final r in rects) [r.left, r.top, r.right, r.bottom],
        ],
      });
    } on PlatformException catch (e) {
      debugPrint('gesture exclusion failed: ${e.message}');
    } on MissingPluginException {
      // As above.
    }
  }
}

/// Where along the wallpaper a pager at [page] of [pages] sits: 0 on the
/// first page, 1 on the last, the middle when there is only one.
@visibleForTesting
double parallaxOffset(double page, int pages) =>
    pages <= 1 ? 0.5 : (page / (pages - 1)).clamp(0.0, 1.0);

/// Pans the wallpaper as [controller] scrolls, while [enabled].
///
/// Sits beside the pager rather than inside it, so it changes no layout and
/// no gesture arena. It paints nothing.
///
/// ─── OFF MEANS CENTRED, NOT LEFT WHERE IT WAS ───────────────────────────────
///
/// Turning the setting off, or leaving a distro that had it on, puts the
/// wallpaper back in the middle. Otherwise a page-three offset would stay
/// behind forever on a desktop that no longer moves it.
class WallpaperParallax extends StatefulWidget {
  const WallpaperParallax({
    super.key,
    required this.controller,
    required this.pages,
    required this.enabled,
  });

  final PageController controller;
  final int pages;
  final bool enabled;

  @override
  State<WallpaperParallax> createState() => _WallpaperParallaxState();
}

class _WallpaperParallaxState extends State<WallpaperParallax> {
  double? _sent;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_push);
    // After the first frame, when the pager has a position to read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(WallpaperParallax old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_push);
      widget.controller.addListener(_push);
    }
    if (old.enabled != widget.enabled || old.pages != widget.pages) _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_push);
    if (_sent != null && _sent != 0.5) {
      unawaited(LauncherWindow.setWallpaperOffset(0.5));
    }
    super.dispose();
  }

  /// Bring the wallpaper to where the setting says it should be right now.
  void _sync() {
    if (!mounted) return;
    if (widget.enabled) {
      _push();
    } else if (_sent != null && _sent != 0.5) {
      _send(0.5);
    }
  }

  void _push() {
    if (!widget.enabled) return;
    final page = widget.controller.pageOrNull;
    if (page == null) return;
    _send(parallaxOffset(page, widget.pages));
  }

  /// One binder call per visible change. A sub-pixel difference is skipped,
  /// so a settled pager costs nothing.
  void _send(double x) {
    if (_sent != null && (x - _sent!).abs() < 0.002) return;
    _sent = x;
    unawaited(LauncherWindow.setWallpaperOffset(x));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
