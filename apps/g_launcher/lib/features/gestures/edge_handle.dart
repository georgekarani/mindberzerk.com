import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../engine/effective_theme.dart';
import '../../engine/theme_spec.dart' show ShellKind;
import '../../system/wallpaper_pan.dart';
import 'gesture_actions.dart';

/// The edge handle: a thin grip on one side of the home screen with three
/// moves, each bound like any other gesture. PHASE 8.
///
/// ─── IT HAS TO TAKE ITS STRIP BACK FROM ANDROID ─────────────────────────────
///
/// With gesture navigation, a swipe in from either edge is Android's back
/// gesture, and it wins before Flutter sees the pointer. The handle claims its
/// own strip with a system gesture exclusion, which Android honours for at
/// most 200dp per edge, so the handle is [height] tall and back still works on
/// the rest of that edge. The rect is sent after layout and cleared when the
/// handle goes, so an edge the user turned off belongs to Android again.
///
/// ─── DRAWN AS EACH SHELL DRAWS ITS EDGES ────────────────────────────────────
///
/// GNOME a soft pill, Plasma a Breeze grip with an accent edge, tiling a flat
/// focused-border bar, the terminal a box-drawing scrollbar, Aqua and Pocket a
/// glass pill. The touch strip is [touchWidth] wide however thin the drawing
/// is, because a 5dp target is not one a thumb can find.
class EdgeHandle extends StatefulWidget {
  const EdgeHandle({
    super.key,
    required this.theme,
    required this.onGesture,
    this.enabled = true,
  });

  final EffectiveTheme theme;

  /// Runs the binding for one of the handle's moves.
  final ValueChanged<Gesture> onGesture;

  /// False while the desktop is being edited: the strip stays mounted (so the
  /// tree keeps its shape) but claims no pointer and no edge.
  final bool enabled;

  /// Under Android's 200dp cap, with room to spare for rounding.
  static const height = 160.0;
  static const touchWidth = 24.0;

  @override
  State<EdgeHandle> createState() => _EdgeHandleState();
}

class _EdgeHandleState extends State<EdgeHandle> {
  final _strip = GlobalKey();
  Rect? _excluded;

  /// How far the current drag has travelled on each axis, in logical pixels.
  ///
  /// ─── DISTANCE AS WELL AS SPEED ────────────────────────────────────────
  ///
  /// The end velocity alone is not enough here. A swipe that starts inside
  /// the back-gesture zone can reach Flutter with its last samples stacked at
  /// one point, and the velocity tracker then reports zero for a swipe that
  /// plainly crossed the screen. So a move counts if it was fast OR if it
  /// went far enough to be deliberate.
  double _dx = 0;
  double _dy = 0;

  /// A drag this long is a swipe whatever its speed.
  static const _travel = 36.0;

  /// A fling this fast is a swipe however short.
  static const _fling = 250.0;

  bool get _active => widget.enabled && widget.theme.edgeHandleSide != 'off';

  @override
  void dispose() {
    if (_excluded != null) {
      LauncherWindow.setGestureExclusion(const []);
    }
    super.dispose();
  }

  /// Send the strip's on-screen rect, or clear it, once it has changed.
  void _syncExclusion() {
    if (!mounted) return;
    Rect? next;
    if (_active) {
      final box = _strip.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.attached) {
        next = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    if (next == _excluded) return;
    _excluded = next;
    LauncherWindow.setGestureExclusion(next == null ? const [] : [next]);
  }

  void _fire(Gesture g) {
    HapticFeedback.selectionClick();
    widget.onGesture(g);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncExclusion());
    if (widget.theme.edgeHandleSide == 'off') return const SizedBox.shrink();

    final right = widget.theme.edgeHandleSide == 'right';
    return LayoutBuilder(
      builder: (context, box) {
        // The centre of the chosen third, kept clear of both ends.
        final fraction = switch (widget.theme.edgeHandlePosition) {
          'top' => 1 / 6,
          'bottom' => 5 / 6,
          _ => 1 / 2,
        };
        final maxTop = (box.maxHeight - EdgeHandle.height).clamp(0.0, double.infinity);
        final top = (box.maxHeight * fraction - EdgeHandle.height / 2)
            .clamp(0.0, maxTop);

        return Stack(
          children: [
            Positioned(
              top: top,
              left: right ? null : 0,
              right: right ? 0 : null,
              width: EdgeHandle.touchWidth,
              height: EdgeHandle.height,
              child: Semantics(
                label: tr('settings.edgeHandle'),
                child: GestureDetector(
                  key: _strip,
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart:
                      !widget.enabled ? null : (_) => _dx = 0,
                  onHorizontalDragUpdate: !widget.enabled
                      ? null
                      : (d) => _dx += d.primaryDelta ?? 0,
                  onHorizontalDragEnd: !widget.enabled
                      ? null
                      : (d) {
                          final v = d.primaryVelocity ?? 0;
                          // Inward is leftward on the right edge.
                          final inward = right
                              ? (v < -_fling || _dx < -_travel)
                              : (v > _fling || _dx > _travel);
                          if (inward) _fire(Gesture.edgeSwipeIn);
                        },
                  onVerticalDragStart:
                      !widget.enabled ? null : (_) => _dy = 0,
                  onVerticalDragUpdate: !widget.enabled
                      ? null
                      : (d) => _dy += d.primaryDelta ?? 0,
                  onVerticalDragEnd: !widget.enabled
                      ? null
                      : (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v < -_fling || _dy < -_travel) {
                            _fire(Gesture.edgeSwipeUp);
                          } else if (v > _fling || _dy > _travel) {
                            _fire(Gesture.edgeSwipeDown);
                          }
                        },
                  child: widget.theme.edgeHandleVisible && widget.enabled
                      ? Align(
                          alignment: right
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _HandleLook(theme: widget.theme, right: right),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The handle as the shell would draw it.
class _HandleLook extends StatelessWidget {
  const _HandleLook({required this.theme, required this.right});

  final EffectiveTheme theme;
  final bool right;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    const h = EdgeHandle.height;
    // The side facing the screen edge is square on the flush styles, so the
    // handle reads as attached to the edge rather than floating near it.
    final inner = right
        ? const BorderRadius.horizontal(left: Radius.circular(3))
        : const BorderRadius.horizontal(right: Radius.circular(3));

    return switch (theme.shell) {
      ShellKind.gnome => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            width: 5,
            height: h,
            decoration: BoxDecoration(
              color: p.onDark.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ShellKind.plasma => Container(
          width: 10,
          height: h,
          decoration: BoxDecoration(
            color: p.bar.withValues(alpha: 0.92),
            borderRadius: inner,
            border: right
                ? Border(left: BorderSide(color: p.accent, width: 2))
                : Border(right: BorderSide(color: p.accent, width: 2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: p.onDark.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ShellKind.tiling => Container(width: 6, height: h, color: p.accent),
      ShellKind.tui => SizedBox(
          height: h,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in const ['│', '│', '├', '│', '│'])
                  Text(
                    c,
                    style: TextStyle(
                      fontFamily: theme.typography.mono,
                      fontSize: 14,
                      height: 1,
                      color: p.accent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ShellKind.aqua => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Container(
            width: 6,
            height: h,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
        ),
    };
  }
}
