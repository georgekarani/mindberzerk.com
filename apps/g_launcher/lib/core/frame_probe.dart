/// TEMPORARY. How many frames the launcher draws while nobody is touching it.
///
/// ─── WHY THIS IS THE NUMBER THAT MATTERS ────────────────────────────────────
///
/// Samsung's own per-app figures put G Launcher at 4.9% for 20 minutes on
/// screen and 6.4% for 46 minutes, which is TikTok territory per minute and far
/// above what One UI Home costs. The background pollers are already gated on
/// lifecycle, so the cost is on-screen, per frame.
///
/// Per frame is expensive here for a structural reason: `getBackgroundMode()`
/// returns transparent so the system wallpaper shows through, which puts
/// Flutter on a FlutterTextureView, which WidgetStage then depends on for
/// hosting third-party widgets behind FlutterView. That path cannot be swapped
/// for a SurfaceView without breaking widgets, so the only lever left is
/// drawing fewer frames.
///
/// A static home screen should produce ZERO frames per second: Flutter
/// schedules a frame only when something marks itself dirty. Anything above
/// zero with the phone untouched is a widget animating or rebuilding on a
/// timer, and each of those frames pays the full composite.
///
/// DELETE once the offender is found. Debug and profile only; [start] returns
/// immediately in release.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

abstract final class FrameProbe {
  /// Long enough that a once-a-minute clock tick does not read as a rate, short
  /// enough to bisect a configuration without waiting around.
  static const _window = Duration(seconds: 10);

  static Timer? _report;
  static AppLifecycleListener? _lifecycle;
  static int _frames = 0;
  static int _buildMicros = 0;
  static int _rasterMicros = 0;
  static bool _running = false;

  /// Which widgets rebuilt in this window, by type. Debug only: Flutter calls
  /// [debugOnRebuildDirtyWidget] in debug builds and nowhere else. This is the
  /// part that NAMES the offender, so a non-zero idle rate is a list of
  /// suspects rather than a number to bisect by hand.
  static final Map<String, int> _rebuilds = {};

  /// Elements already built once. An Expando, so it never keeps one alive.
  static final Expando<bool> _seen = Expando<bool>('frame probe');

  /// Which running animations were seen this window, keyed by the line in this
  /// app that started them. Debug only. This is the half that names a
  /// REPAINT-ONLY offender: an AnimationController driving a painter or a
  /// transition never rebuilds a widget, so [_rebuilds] stays empty for it.
  static final Map<String, int> _animations = {};

  /// Sampled at most this often, so attribution costs nothing per frame.
  static const _sampleEvery = Duration(milliseconds: 500);
  static DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);

  /// A static method, so every tear-off of it is the same object and the
  /// identity check in [_flush] can tell whether someone replaced it.
  static void _hook(Element element, bool builtOnce) {
    // First builds are a page opening, not idle churn. Tracked here rather
    // than read from `builtOnce`, which Flutter only ever sets while
    // debugPrintRebuildDirtyWidgets is on, so it arrives false every time and
    // filtered out every rebuild the probe existed to count.
    if (_seen[element] == null) {
      _seen[element] = true;
      return;
    }
    final name = element.widget.runtimeType.toString();
    _rebuilds[name] = (_rebuilds[name] ?? 0) + 1;
  }

  static void start() {
    if (_running || kReleaseMode) return;
    _running = true;

    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    if (kDebugMode) debugOnRebuildDirtyWidget = _hook;
    // Flush on the way out so a window that ends with the screen off does not
    // report the frames before it as the idle rate. Then stop the timer: a
    // backgrounded probe printing "0 frames" every ten seconds is a wakeup that
    // inflates the very background CPU figure it sits next to in logcat.
    _lifecycle = AppLifecycleListener(
      onPause: _pause,
      onHide: _pause,
      onResume: _resume,
    );
    _resume();
  }

  static void _resume() {
    _report?.cancel();
    _report = Timer.periodic(_window, (_) => _flush());
  }

  static void _pause() {
    final report = _report;
    if (report == null) return;
    report.cancel();
    _report = null;
    _flush();
  }

  static void stop() {
    if (!_running) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    if (kDebugMode) debugOnRebuildDirtyWidget = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _report?.cancel();
    _report = null;
    _running = false;
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames++;
      _buildMicros += t.buildDuration.inMicroseconds;
      _rasterMicros += t.rasterDuration.inMicroseconds;
    }
    if (kDebugMode) _sampleAnimations();
  }

  /// Names every animation running right now by where this app started it.
  ///
  /// Flutter records, in debug, the stack that registered each transient frame
  /// callback, and a ticker that reschedules itself carries the ORIGINAL stack
  /// forward. `debugAssertNoTransientCallbacks` is the only public way to read
  /// those stacks: it reports an error that lists them. Intercepting it turns
  /// that into "home_grid.dart:133 is animating", which is the whole question.
  static void _sampleAnimations() {
    final now = DateTime.now();
    if (now.difference(_lastSample) < _sampleEvery) return;
    _lastSample = now;
    if (SchedulerBinding.instance.transientCallbackCount == 0) return;

    // It REPORTS rather than throws, through FlutterError.onError, which is
    // wired to Crashlytics. Swap the handler for the length of one synchronous
    // call so the listing lands here and nowhere else.
    List<String>? callbacks;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final info = details.informationCollector?.call() ?? const [];
      // One DiagnosticsStackTrace per running callback.
      callbacks = [for (final n in info) n.toStringDeep()];
    };
    try {
      SchedulerBinding.instance.debugAssertNoTransientCallbacks('frame probe');
    } finally {
      FlutterError.onError = previous;
    }
    final found = callbacks;
    if (found == null) return;

    // Per callback, the first frame in OUR code that is not this file. The
    // description nodes carry no stack and simply match nothing.
    final site = RegExp(r'package:g_launcher/([^\s)]+\.dart):(\d+)');
    // A Flutter widget that animates by itself (an indeterminate spinner, say)
    // has no frame of ours on the stack, so it is named by its State instead.
    final state = RegExp(r'#\d+\s+(_?\w+State)\.\w+ \(package:flutter/');
    for (final section in found) {
      String? key;
      for (final m in site.allMatches(section)) {
        if (m.group(1)!.endsWith('frame_probe.dart')) continue;
        key = '${m.group(1)}:${m.group(2)}';
        break;
      }
      key ??= state.firstMatch(section)?.group(1);
      if (key != null) _animations[key] = (_animations[key] ?? 0) + 1;
    }
  }

  /// `debugPrint`, not the app logger: this is scaffolding read in logcat next
  /// to a stopwatch, and routing it through Crashlytics would dress up
  /// something with a known expiry.
  static void _flush() {
    final frames = _frames;
    _frames = 0;
    final buildMicros = _buildMicros;
    _buildMicros = 0;
    final rasterMicros = _rasterMicros;
    _rasterMicros = 0;

    final top = (_rebuilds.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(6)
        .map((e) => '${e.key} x${e.value}')
        .join(', ');
    _rebuilds.clear();

    final anims = (_animations.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(6)
        .map((e) => e.key)
        .join(', ');
    _animations.clear();

    // DevTools and the IDE switch widget-rebuild tracking off on attach by
    // setting this hook to null, which silently blinds the probe. Put it back.
    if (kDebugMode && debugOnRebuildDirtyWidget != _hook) {
      debugOnRebuildDirtyWidget = _hook;
    }

    if (frames == 0) {
      debugPrint(
        'frame probe: 0 frames in ${_window.inSeconds}s (idle, as it should be)',
      );
      return;
    }
    final fps = (frames / _window.inSeconds).toStringAsFixed(1);
    final build = (buildMicros / frames / 1000).toStringAsFixed(1);
    final raster = (rasterMicros / frames / 1000).toStringAsFixed(1);
    debugPrint(
      'frame probe: $frames frames in ${_window.inSeconds}s ($fps fps), '
      'build ${build}ms, raster ${raster}ms'
      '${top.isEmpty ? ', no rebuilds' : ', rebuilt: $top'}'
      '${anims.isEmpty ? '' : ', animating: $anims'}',
    );
  }
}
