/// Where every hosted widget is on screen, and whether the stage should show it.
///
/// ─── THE SHAPE OF THIS, AND WHY IT IS BACKWARDS FROM THE OBVIOUS ────────────
///
/// The obvious design computes each widget's rectangle from the grid: page,
/// column, row, cell size, done. It is wrong here, and expensively so. A tile's
/// real position on screen also depends on the shell's panel, its dock, the
/// system insets, the workspace surface's own margin, and which page the
/// PageView has scrolled to. Reproducing all of that would be a second layout
/// engine that has to agree with the first, and the day it stops agreeing every
/// widget sits a few dp off with nothing to point at.
///
/// So each tile MEASURES ITSELF. `AppWidgetDesklet` is a transparent hole in the
/// Flutter tree that reserves exactly the right space and reports its own global
/// rectangle through [stageRectsProvider]. Whatever the layout did, that is
/// where the widget goes.
///
/// ─── VISIBILITY IS A PRODUCT DECISION, NOT AN OPTIMISATION ──────────────────
///
/// The stage is behind Flutter, so Flutter chrome draws over it, which is right
/// for a dock and a top bar. It is wrong for anything full-screen: the drawer
/// paints a 0.92 wash, so a widget under it would bleed through at 8% and read
/// as dirt rather than as translucency. The GNOME shell already documents that
/// exact problem for its own chrome.
///
/// Native also cannot follow Flutter's scroll without a message per frame, and
/// one frame of lag is tens of pixels of shear against the desklets beside it.
///
/// So the stage hides during a workspace swipe, during edit mode, and whenever
/// the drawer is open. Hiding for motion is not a compromise: it is what lets
/// hosted widgets be hidden and OUR desklets keep parallaxing, which is the
/// contrast worth having.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../drawer/drawer_state.dart';
import 'desklet_edit.dart';

const _channel = MethodChannel('g_launcher/widget_stage');

/// The last hosted widget the user held, and a nonce so repeats fire.
///
/// ─── WHY A COUNTER AND NOT JUST THE ID ──────────────────────────────────────
///
/// Holding the same widget twice in a row would write the same id, Riverpod
/// would see no change, and the second hold would open nothing. The counter
/// makes every press a distinct value, which is the same trick a "signal"
/// provider always needs and the same reason `StageRects` keys on the desklet
/// rather than the widget.
/// [at] is the press point in LOGICAL pixels, global to the screen, ready to
/// hand straight to `AnchoredMenu` as a one-pixel anchor rect.
typedef StageLongPress = ({int widgetId, Offset at, int nonce});

class StageLongPresses extends Notifier<StageLongPress?> {
  @override
  StageLongPress? build() => null;

  var _nonce = 0;

  void fire(int widgetId, Offset at) {
    _nonce++;
    state = (widgetId: widgetId, at: at, nonce: _nonce);
  }
}

final stageLongPressProvider =
    NotifierProvider<StageLongPresses, StageLongPress?>(StageLongPresses.new);

/// One placed widget's global rectangle, in dp, and who reported it.
///
/// [owner] is the reporting State object's identity. It exists because a forget
/// is DEFERRED (see [StageRects.forget]) and a desklet can be torn down and
/// rebuilt in a different page element within the same frame. Without it, the
/// old State's deferred forget would delete the rect the new State had just
/// reported, and the widget would vanish until something moved.
typedef StageRect = ({
  int widgetId,
  Rect rect,
  Object owner,
  StageLook look,
});

/// How native draws a hosted widget inside its rectangle. PHASE 4.
///
/// [scalePct] is content scale as a whole percent (100 is as the app drew
/// it). [radius] rounds the corners in dp, 0 leaving them alone. [argb] is a
/// backing drawn behind the widget, alpha 0 drawing nothing. Native applies
/// all three because the stage sits behind Flutter, where nothing Flutter
/// paints can be under the widget.
typedef StageLook = ({int scalePct, double radius, int argb});

/// A hosted widget exactly as its app drew it.
const StageLook plainStageLook = (scalePct: 100, radius: 0, argb: 0);

/// Every hosted widget currently laid out, by desklet id.
///
/// Keyed by DESKLET id rather than widget id so a tile that is rebuilt with a
/// new widget id (a re-bind after the provider was reinstalled) replaces its own
/// entry instead of leaving the old one stranded and visible forever.
class StageRects extends Notifier<Map<String, StageRect>> {
  @override
  Map<String, StageRect> build() => const {};

  void report(
    String deskletId,
    Object owner,
    int widgetId,
    Rect rect, {
    StageLook look = plainStageLook,
  }) {
    final existing = state[deskletId];
    if (existing != null &&
        existing.owner == owner &&
        existing.widgetId == widgetId &&
        existing.look == look &&
        _close(existing.rect, rect)) {
      return;
    }
    state = {
      ...state,
      deskletId: (widgetId: widgetId, rect: rect, owner: owner, look: look),
    };
  }

  /// Drop a rect, but only if [owner] is still the one that reported it.
  ///
  /// ─── WHY THIS IS DEFERRED AND WHY IT IS GUARDED ───────────────────────
  ///
  /// The caller is a State being torn down, and a State inside a
  /// `PageView.builder` is torn down DURING LAYOUT: the sliver collects garbage
  /// from inside `performLayout`, which is a build-tree lifecycle, and writing
  /// provider state there throws "Tried to modify a provider while the widget
  /// tree was building". So the write waits for the frame to end.
  ///
  /// Waiting introduces the race the owner check closes. Between the teardown
  /// and the callback, the same desklet can be rebuilt in another element and
  /// report a fresh rect. An unguarded forget would then delete a live entry.
  void forget(String deskletId, Object owner) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state[deskletId]?.owner != owner) return;
      state = {...state}..remove(deskletId);
    });
  }

  /// Sub-pixel equality, because `localToGlobal` returns doubles and a rect that
  /// differs in the eighth decimal is the same rect. Without this the map is a
  /// new object on every frame and the sync below never stops firing.
  static bool _close(Rect a, Rect b) =>
      (a.left - b.left).abs() < 0.5 &&
      (a.top - b.top).abs() < 0.5 &&
      (a.width - b.width).abs() < 0.5 &&
      (a.height - b.height).abs() < 0.5;
}

final stageRectsProvider =
    NotifierProvider<StageRects, Map<String, StageRect>>(StageRects.new);

/// Is the desktop still enough to show live widgets?
///
/// ─── MOVING EXPIRES ON ITS OWN ──────────────────────────────────────────────
///
/// `true` is only ever cleared by a ScrollEndNotification, and a pager that is
/// unmounted mid-swipe (a shell rebuilt by a theme switch, a page removed)
/// never sends one. Left alone that hides every hosted widget until the next
/// swipe. So each report of motion re-arms a short timer, and motion that
/// stops being reported is treated as over. A drag or a fling reports on every
/// frame, so the timer cannot fire while the desktop is really moving.
class StageMotion extends Notifier<bool> {
  /// Longer than any gap between two frames of a live scroll, shorter than a
  /// person would notice a widget staying hidden.
  static const _expiry = Duration(milliseconds: 300);

  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void set(bool moving) {
    _timer?.cancel();
    _timer = moving ? Timer(_expiry, () => state = false) : null;
    if (state == moving) return;
    state = moving;
  }
}

final stageMovingProvider =
    NotifierProvider<StageMotion, bool>(StageMotion.new);

/// How many routes are stacked over the desktop.
///
/// ─── WHY A NAVIGATOR OBSERVER AND NOT A PROVIDER PER SURFACE ────────────────
///
/// `LauncherActivity.dispatchTouchEvent` asks `WidgetStage.hitTest` on every
/// press, so a press inside a widget's rectangle goes to that widget BEFORE
/// Flutter sees it. Correct on a desktop at rest, wrong the moment anything is
/// drawn over it, and the failure is invisible: the tap simply does nothing,
/// or worse, quietly presses a media button under the panel you were aiming at.
///
/// The desklet menu made it obvious because it opens ANCHORED TO THE WIDGET,
/// so its rows sit on the hit rect and could not be tapped. But it was never
/// only the menu. Settings, the widget picker, the wallpaper screen and every
/// other pushed route had the same hole wherever a widget happened to sit on
/// the desktop underneath.
///
/// Which is why this counts ROUTES rather than adding a flag per surface. A
/// flag per surface is a list that has to be maintained, and the next screen
/// someone adds inherits the bug by default. The Navigator already knows the
/// answer for every route that will ever exist.
///
/// A plain [ValueNotifier] rather than a provider because a [NavigatorObserver]
/// is constructed by `MaterialApp`, outside any `ProviderScope`, and has no
/// `ref` to write with.
///
/// ─── A SCREEN HIDES THE STAGE; A MENU DOES NOT ──────────────────────────────
///
/// Covered only stops the stage taking presses, because a menu or sheet over
/// the desktop is ABOUT what is under it and the widget should stay in view.
/// A full screen (Settings, the widget picker) is not, and several draw a
/// see-through background over the wallpaper, so a hosted widget showed
/// through them as a ghost. [screened] counts page routes for that: the
/// stage hides while any is up. Popups and sheets are not page routes.
class StageRouteObserver extends NavigatorObserver {
  /// True while at least one route sits above the desktop.
  final ValueNotifier<bool> covered = ValueNotifier<bool>(false);

  /// True while at least one full-screen page sits above the desktop.
  final ValueNotifier<bool> screened = ValueNotifier<bool>(false);

  var _depth = 0;
  var _pages = 0;

  void _set(int next) {
    _depth = next < 0 ? 0 : next;
    covered.value = _depth > 0;
  }

  void _setPages(int next) {
    _pages = next < 0 ? 0 : next;
    screened.value = _pages > 0;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // `previous == null` is the FIRST route, which IS the desktop rather than
    // something over it. Counting it would leave the stage permanently deaf.
    if (previousRoute == null) return;
    _set(_depth + 1);
    if (route is PageRoute) _setPages(_pages + 1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(_depth - 1);
    if (route is PageRoute) _setPages(_pages - 1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _set(_depth - 1);
    if (route is PageRoute) _setPages(_pages - 1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // One out, one in. The depth is unchanged and saying so beats letting the
    // pair of callbacks drift it. The page count changes only if the pair
    // differs in kind.
    final delta =
        (newRoute is PageRoute ? 1 : 0) - (oldRoute is PageRoute ? 1 : 0);
    if (delta != 0) _setPages(_pages + delta);
  }
}

/// The one instance, handed to `MaterialApp.navigatorObservers` in app.dart.
final stageRouteObserver = StageRouteObserver();

/// Should the stage be visible right now?
final stageVisibleProvider = Provider<bool>((ref) {
  if (ref.watch(stageMovingProvider)) return false;
  if (ref.watch(deskletEditProvider).active) return false;
  if (ref.watch(activitiesOpenProvider)) return false;
  return true;
});

/// Tell the stage the widget is gone for good.
///
/// Distinct from simply stopping reporting a rect, and the distinction is the
/// whole reason the churn is fixed: an unreported widget is HIDDEN and keeps its
/// host view, a released one is destroyed. A page scrolling out of a PageView
/// must do the first and only removal does the second.
Future<void> releaseStageWidget(int widgetId) async {
  try {
    await _channel.invokeMethod<void>('release', {'widgetId': widgetId});
  } on PlatformException {
    // The stage not existing is not an error worth surfacing: the widget is
    // being removed either way, and its host id is freed by removeWidget.
  }
}

/// Mounts once, near the root of a shell, and pushes every change to native.
///
/// A widget rather than a listener set up in an initState because it has to live
/// exactly as long as the desktop does, and because putting it in the tree is
/// what makes it obvious that removing the desktop removes the sync.
class WidgetStageSync extends ConsumerStatefulWidget {
  const WidgetStageSync({super.key});

  @override
  ConsumerState<WidgetStageSync> createState() => _WidgetStageSyncState();
}

class _WidgetStageSyncState extends ConsumerState<WidgetStageSync> {
  List<double> _lastFlat = const [];
  bool? _lastVisible;
  bool? _lastInteractive;

  @override
  void initState() {
    super.initState();

    // ─── THE ONE THING NATIVE TELLS US ──────────────────────────────────────
    //
    // Registered here rather than at the app root because this widget already
    // exists for exactly as long as the desktop does, which is the window in
    // which a hold on a hosted widget means anything. `setMethodCallHandler`
    // REPLACES, so a shell rebuilt after a theme switch swaps the handler
    // rather than stacking a second one.
    // Rebuild when a route opens or closes over the desktop, so the stage is
    // told to stop taking touches. See [StageRouteObserver].
    stageRouteObserver.covered.addListener(_onCoveredChanged);
    stageRouteObserver.screened.addListener(_onCoveredChanged);

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'longPress') return null;

      final args = call.arguments as Map?;
      final id = args?['widgetId'];
      if (id is! int) return null;

      // Native sends DEVICE pixels, which is the only unit it has. The ratio is
      // read here rather than passed, because this widget is in the tree and
      // therefore has a MediaQuery, and a number crossing the channel is a
      // number that can go stale.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final x = (args?['x'] as num?)?.toDouble() ?? 0;
      final y = (args?['y'] as num?)?.toDouble() ?? 0;

      ref
          .read(stageLongPressProvider.notifier)
          .fire(id, Offset(x / dpr, y / dpr));
      return null;
    });
  }

  void _onCoveredChanged() {
    // POST-FRAME, because a route can be pushed from inside a build and
    // `didPush` fires synchronously with it. Calling setState there throws
    // "setState() or markNeedsBuild() called during build", and the surface it
    // would take down is the desktop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    stageRouteObserver.covered.removeListener(_onCoveredChanged);
    stageRouteObserver.screened.removeListener(_onCoveredChanged);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rects = ref.watch(stageRectsProvider);
    final visible = ref.watch(stageVisibleProvider) &&
        !stageRouteObserver.screened.value;

    // ─── WHILE HIDDEN, POSITIONS ARE NOT NEWS ─────────────────────────────
    //
    // Rects change on every frame of a workspace swipe, because the tiles
    // genuinely move. The stage is hidden throughout, so sending them would be
    // a platform call per frame telling native where to put views nobody can
    // see. Send the hide once and go quiet until the desktop settles.
    final flat = visible ? _flatten(rects) : const <double>[];

    // VISIBLE but not necessarily touchable. A widget under an open menu keeps
    // drawing, because the menu is about it, and stops claiming presses so the
    // menu can be used. See [StageRouteObserver].
    final interactive = !stageRouteObserver.covered.value;

    if (visible == _lastVisible &&
        interactive == _lastInteractive &&
        _same(flat, _lastFlat)) {
      return const SizedBox.shrink();
    }
    _lastVisible = visible;
    _lastInteractive = interactive;
    _lastFlat = flat;

    // POST-FRAME, because this runs during build and a platform call from
    // inside build can reenter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channel.invokeMethod<void>('sync', {
        'rects': flat,
        'visible': visible,
        'interactive': interactive,
      }).catchError((_) {
        // Nothing to do and nothing to say. A failed sync leaves the stage
        // where it was, which is the last correct position, and the next
        // layout pass sends it again.
      });
    });

    return const SizedBox.shrink();
  }

  /// Eight values per widget, matching `StageBridge.parse`: id, x, y, w, h,
  /// scale percent, radius, background ARGB. The two sides change together.
  static List<double> _flatten(Map<String, StageRect> rects) {
    final flat = <double>[];
    for (final r in rects.values) {
      flat
        ..add(r.widgetId.toDouble())
        ..add(r.rect.left)
        ..add(r.rect.top)
        ..add(r.rect.width)
        ..add(r.rect.height)
        ..add(r.look.scalePct.toDouble())
        ..add(r.look.radius)
        ..add(r.look.argb.toDouble());
    }
    return flat;
  }

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() >= 0.5) return false;
    }
    return true;
  }
}
