/// How much of its edge the dock is ACTUALLY taking, measured.
///
/// ─── THE STRIP OF DEAD DESKTOP ─────────────────────────────────────────────
///
/// `DockMetrics.reserve` is computed at `maxSlot`, the largest a slot can ever
/// be, and its own doc admits the cost: "the worst error is a packed dock
/// leaving an 18dp strip of unused desktop beside it". The dock is fit-to-run,
/// so slots shrink from 64 toward 46 as it fills, and every dp of that shrink
/// became a gap between the last row of apps and the dock.
///
/// 18 is the floor of that error, not the size of it. `AquaDockMetrics.reserve`
/// is computed at its own base slot and a magnified dock swells past it, so
/// Aqua could reserve too LITTLE at the moment the row is lifted.
///
/// ─── MEASURED, NOT RE-DERIVED ──────────────────────────────────────────────
///
/// The tempting fix is to call `DockMetrics.slotFor` from the desktop with the
/// same count. That means the grid reconstructing the dock's capacity logic,
/// which differs per shell: three shells build their entry lists differently,
/// Aqua adds a Launchpad slot to the run, and the grid button is counted on
/// some distros and not others. Two copies of that arithmetic would agree on
/// the day they were written and not much longer.
///
/// The dock knows its own size once it has been laid out. Asking it costs one
/// wrapper and cannot drift.
///
/// The reserve constants stay, and are still right: they are what the desktop
/// uses for the first frame, before any dock has been measured. Over-reserving
/// for one frame is invisible; under-reserving would put apps behind the dock.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The dock's measured cross-axis extent in dp, or null before the first
/// layout. Excludes the gap the shell positions it away from the edge, which
/// the shell owns and `dockInsets` adds back.
final dockExtentProvider =
    NotifierProvider<DockExtentController, double?>(DockExtentController.new);

class DockExtentController extends Notifier<double?> {
  @override
  double? build() => null;

  /// The probe that wrote [state], so only that probe can clear it.
  Object? _owner;

  void report(double extent, {Object? owner}) {
    _owner = owner;
    // Half a dp of hysteresis. A measurement that oscillates on a rounding
    // boundary would relayout the desktop every frame, which is the cost the
    // constant was avoiding by being wrong in a fixed direction.
    if (state != null && (state! - extent).abs() < 0.5) return;
    state = extent;
  }

  /// Called when the dock leaves, so the desktop stops reserving for a dock
  /// that is not there. `dockReveal: 'apps'` docks come and go.
  ///
  /// ─── ONLY THE PROBE THAT WROTE IT ─────────────────────────────────────
  ///
  /// A distro switch mounts the new shell's dock in the same frame the old
  /// one is disposed, and the old probe clears after that frame. Unowned,
  /// that clear could land after the new dock's first report and erase it,
  /// leaving the desktop on the stand-in reserve until something relaid the
  /// dock. With an [owner], a clear is ignored once another probe has
  /// reported; without one it clears unconditionally.
  void clear({Object? owner}) {
    if (owner != null && !identical(owner, _owner)) return;
    _owner = null;
    state = null;
  }
}

/// Reports [child]'s cross-axis size into [dockExtentProvider].
///
/// Wraps the dock inside the dock's own build rather than at each shell's
/// `Positioned`, so all four shells that mount one get this without knowing it
/// exists, and a fifth cannot forget.
/// The dock's box on screen, in global coordinates; null while no dock is
/// shown. Desklets avoid exactly this box rather than a whole strip down one
/// side (see features/desklets/dock_avoid.dart).
final dockRectProvider =
    NotifierProvider<DockRectController, Rect?>(DockRectController.new);

class DockRectController extends Notifier<Rect?> {
  @override
  Rect? build() => null;

  void report(Rect rect) {
    final was = state;
    if (was != null &&
        (was.left - rect.left).abs() < 0.5 &&
        (was.top - rect.top).abs() < 0.5 &&
        (was.width - rect.width).abs() < 0.5 &&
        (was.height - rect.height).abs() < 0.5) {
      return;
    }
    state = rect;
  }

  void clear() => state = null;
}

class DockExtentProbe extends ConsumerStatefulWidget {
  const DockExtentProbe({
    super.key,
    required this.vertical,
    required this.child,
  });

  /// True for a left or right dock, where the extent is the WIDTH. Measuring
  /// the wrong axis on a vertical dock would report the length of the run and
  /// reserve most of the screen.
  final bool vertical;

  final Widget child;

  @override
  ConsumerState<DockExtentProbe> createState() => _DockExtentProbeState();
}

class _DockExtentProbeState extends ConsumerState<DockExtentProbe> {
  /// ─── CAPTURED, NOT READ IN dispose ─────────────────────────────────────
  ///
  /// `ref` is unusable once the widget is deactivated, and `dispose` is exactly
  /// that moment: Riverpod throws rather than returning something stale. The
  /// notifier itself outlives the widget, so holding it in a field is both safe
  /// and the fix Riverpod's own error message names.
  ///
  /// This is the second time this bug has been written in this codebase. It was
  /// `panel_bar.dart` calling `ref.read` after an await, and the symptom there
  /// was edit mode never switching off. Same shape, different verb.
  DockExtentController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ref.read(dockExtentProvider.notifier);
  }

  @override
  void dispose() {
    // A stale extent would keep a band reserved on a distro whose dock has just
    // been switched off. After the frame, because a notifier written during
    // unmount marks widgets dirty inside a teardown.
    final n = _controller;
    if (n != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => n.clear(owner: this));
    }
    // The BOX is deliberately kept. A dock hidden by Activities or an
    // edge-reveal comes back to the same place, and clearing it would make
    // every desklet beside it jump each time the drawer opened. A new dock
    // (theme change) reports its own box on its first layout.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Measure(
      onSize: (size) {
        if (!mounted) return;
        ref
            .read(dockExtentProvider.notifier)
            .report(widget.vertical ? size.width : size.height, owner: this);
      },
      onRect: (rect) {
        if (!mounted) return;
        ref.read(dockRectProvider.notifier).report(rect);
      },
      child: widget.child,
    );
  }
}

/// A proxy box that hands its child's size back after layout.
///
/// A `LayoutBuilder` cannot do this: it reports the constraints going IN, and
/// the dock's size is decided by its contents, not by what it was offered.
class _Measure extends SingleChildRenderObjectWidget {
  const _Measure(
      {required this.onSize, required this.onRect, required super.child});

  final ValueChanged<Size> onSize;
  final ValueChanged<Rect> onRect;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasure(onSize, onRect);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) {
    renderObject
      ..onSize = onSize
      ..onRect = onRect;
  }
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onSize, this.onRect);

  ValueChanged<Size> onSize;
  ValueChanged<Rect> onRect;
  Size? _last;

  /// How many drawn frames after a layout the box keeps being re-read.
  ///
  /// ─── A BOX READ ONCE IS READ MID-ANIMATION ────────────────────────────
  ///
  /// The dock arrives inside `DockEntrance`, which slides or scales it in
  /// over 420ms. Transforms above the dock move it without relaying it out,
  /// so a box read once, after the first layout, was the box a few frames
  /// into the slide: shifted toward the edge, or shrunk. The desktop then
  /// blocked too few cells and widgets sat under the real dock until a
  /// restart. So the box is re-read on every frame for a while after each
  /// layout. It rides frames that are already being drawn (the entrance is
  /// producing them) and never asks for one, so an idle dock costs nothing.
  ///
  /// ─── COUNTED IN FRAMES, NOT TIME ──────────────────────────────────────
  ///
  /// A launcher started behind another screen (Android's "Updating" screen
  /// after an install, a lock screen) draws no frames, and the entrance
  /// animation waits with it. A wall-clock window ran out during that pause,
  /// so the one read left was the dock's first, mid-slide box, and a widget
  /// added later was placed under the real dock. Frames advance only when
  /// the animation does, so 90 of them (about 1.5 s at 60 Hz) always cover
  /// the whole entrance.
  static const _followFrames = 90;

  int _framesLeft = 0;
  bool _pending = false;

  void _readBox() {
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      final box = child;
      if (!attached || box == null || !box.hasSize) return;
      // The controller drops repeats, so a settled dock writes nothing.
      onRect(box.localToGlobal(Offset.zero) & box.size);
      if (--_framesLeft > 0) _readBox();
    });
  }

  @override
  void performLayout() {
    super.performLayout();
    // The box, every layout: a dock can move without changing size (a
    // centred bottom dock on rotation). Read after the frame, when the
    // parents' offsets are final, and followed for [_followFrames] frames
    // in case an ancestor is still animating it into place.
    _framesLeft = _followFrames;
    _readBox();
    final s = child?.size;
    if (s == null || s == _last) return;
    _last = s;

    // AFTER the frame. Writing to a provider during layout marks widgets dirty
    // inside a build, which Flutter asserts on and which would turn a size
    // report into a crash.
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}
