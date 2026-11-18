/// Guides drawn while a desklet is being dragged. PHASE 3a.
///
/// ─── THE PREVIEW IS THE DROP ────────────────────────────────────────────────
///
/// The tile follows the finger freely and snaps only on release (see
/// desklet_editor.dart), which left the person guessing where it would land
/// and whether it would land at all. The landing published here is computed by
/// the SAME function the drop commits through, so the outline on screen and
/// the place the tile ends up can never disagree, including the dock and icon
/// relocation and the engine's refusal.
///
/// ─── ALIGNMENT, NOT MAGNETISM ───────────────────────────────────────────────
///
/// On a cell grid every edge already lands on a cell boundary, so there is
/// nothing for a magnet to pull towards. What a grid does not tell you is that
/// this clock now lines up with that weather tile three rows down. The lines
/// say exactly that, and only when it is true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/prefs/launcher_prefs.dart' show Desklet;
import '../../design/tokens/colors.dart';
import '../../engine/effective_theme.dart';

/// Where the desklet being dragged would land if released now.
@immutable
class DeskletLanding {
  const DeskletLanding({
    required this.id,
    required this.page,
    required this.col,
    required this.row,
    required this.spanX,
    required this.spanY,
    required this.legal,
    this.companions = const [],
  });

  final String id;
  final int page;
  final int col;
  final int row;
  final int spanX;
  final int spanY;

  /// False when the engine would refuse the drop and the tile would spring
  /// back. Drawn in the danger red so the refusal is visible before release.
  final bool legal;

  /// Where the rest of the dragged tile's group lands, in cells. Empty for a
  /// tile with no group. Drawn like the main outline; alignment lines come
  /// from the main tile alone, so a group does not light up against itself.
  final List<({int col, int row, int spanX, int spanY})> companions;

  bool samePlace(DeskletLanding o) =>
      o.id == id &&
      o.page == page &&
      o.col == col &&
      o.row == row &&
      o.spanX == spanX &&
      o.spanY == spanY &&
      o.legal == legal &&
      o.companions.length == companions.length;
}

/// The in-flight landing, or null when nothing is being dragged. Never
/// persisted: a guide is a property of a finger, not of the desktop.
final deskletLandingProvider =
    NotifierProvider<DeskletLandingNotifier, DeskletLanding?>(
  DeskletLandingNotifier.new,
);

/// The live finger offset of a group drag, for the members not under the
/// finger. PHASE 3c.
///
/// Separate from [deskletLandingProvider], which changes once per cell: the
/// members follow the finger every frame, so the group moves as one piece
/// rather than the held tile gliding while the rest jump cell to cell.
final deskletGroupDragProvider =
    NotifierProvider<DeskletGroupDrag, ({Set<String> ids, Offset offset})?>(
  DeskletGroupDrag.new,
);

class DeskletGroupDrag
    extends Notifier<({Set<String> ids, Offset offset})?> {
  @override
  ({Set<String> ids, Offset offset})? build() => null;

  void update(Set<String> ids, Offset offset) =>
      state = (ids: ids, offset: offset);

  void clear() {
    if (state != null) state = null;
  }
}

class DeskletLandingNotifier extends Notifier<DeskletLanding?> {
  @override
  DeskletLanding? build() => null;

  /// Publishes [next], returning true when the landing moved to a new cell.
  /// The caller ticks a haptic on true, which is what makes the free drag feel
  /// snapped without fighting the thumb.
  bool show(DeskletLanding next) {
    final current = state;
    if (current != null && current.samePlace(next)) return false;
    state = next;
    return true;
  }

  void clear() {
    if (state != null) state = null;
  }
}

/// The landing outline and alignment lines for one page.
///
/// Sits between the grid and the tiles in the surface's Stack, and ignores
/// pointers so it can never steal the drag it is drawing for.
class DeskletGuides extends ConsumerWidget {
  const DeskletGuides({
    super.key,
    required this.theme,
    required this.page,
    required this.items,
    required this.cellW,
    required this.cellH,
  });

  final EffectiveTheme theme;
  final int page;

  /// The page's desklets where they are SEEN, so lines match what is on
  /// screen rather than a stored spot the dock has pushed aside.
  final List<Desklet> items;

  final double cellW;
  final double cellH;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final landing = ref.watch(deskletLandingProvider);
    if (landing == null || landing.page != page) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GuidePainter(
          landing: landing,
          others: [
            for (final d in items)
              if (d.id != landing.id && !_inGroupOf(d, landing.id, items)) d,
          ],
          cellW: cellW,
          cellH: cellH,
          accent: theme.palette.accent,
        ),
      ),
    );
  }
}

/// Whether [d] shares a group with the tile [id]: the group moves together,
/// so lining up with itself is not news.
bool _inGroupOf(Desklet d, String id, List<Desklet> items) {
  final g = d.group;
  if (g == null) return false;
  for (final o in items) {
    if (o.id == id) return o.group == g;
  }
  return false;
}

/// The edges and centre of a rectangle on one axis, in cells. Centres are
/// doubled so a span of 3 has an exact integer centre.
List<int> _marks(int start, int span) =>
    [start * 2, start * 2 + span, (start + span) * 2];

class _GuidePainter extends CustomPainter {
  const _GuidePainter({
    required this.landing,
    required this.others,
    required this.cellW,
    required this.cellH,
    required this.accent,
  });

  final DeskletLanding landing;
  final List<Desklet> others;
  final double cellW;
  final double cellH;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = landing.legal ? accent : GColors.danger;
    final rect = Rect.fromLTWH(
      landing.col * cellW,
      landing.row * cellH,
      landing.spanX * cellW,
      landing.spanY * cellH,
    ).deflate(3);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    final fill = Paint()..color = ink.withValues(alpha: 0.16);
    final stroke = Paint()
      ..color = ink.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(shape, fill);
    canvas.drawRRect(shape, stroke);

    for (final c in landing.companions) {
      final other = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          c.col * cellW,
          c.row * cellH,
          c.spanX * cellW,
          c.spanY * cellH,
        ).deflate(3),
        const Radius.circular(12),
      );
      canvas.drawRRect(other, fill);
      canvas.drawRRect(other, stroke);
    }

    // A refused drop has nothing worth aligning to.
    if (!landing.legal) return;

    final line = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;

    final myX = _marks(landing.col, landing.spanX);
    final myY = _marks(landing.row, landing.spanY);

    for (final o in others) {
      final theirX = _marks(o.col, o.spanX);
      final theirY = _marks(o.row, o.spanY);

      // Vertical lines: a shared left edge, right edge or centre column.
      for (final x in myX) {
        if (!theirX.contains(x)) continue;
        final px = x / 2 * cellW;
        final top = (landing.row < o.row ? landing.row : o.row) * cellH;
        final bottom = ((landing.row + landing.spanY) > (o.row + o.spanY)
                ? landing.row + landing.spanY
                : o.row + o.spanY) *
            cellH;
        canvas.drawLine(Offset(px, top), Offset(px, bottom), line);
      }

      // Horizontal lines: a shared top edge, bottom edge or centre row.
      for (final y in myY) {
        if (!theirY.contains(y)) continue;
        final py = y / 2 * cellH;
        final left = (landing.col < o.col ? landing.col : o.col) * cellW;
        final right = ((landing.col + landing.spanX) > (o.col + o.spanX)
                ? landing.col + landing.spanX
                : o.col + o.spanX) *
            cellW;
        canvas.drawLine(Offset(left, py), Offset(right, py), line);
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      !old.landing.samePlace(landing) ||
      old.others != others ||
      old.cellW != cellW ||
      old.cellH != cellH ||
      old.accent != accent;
}
