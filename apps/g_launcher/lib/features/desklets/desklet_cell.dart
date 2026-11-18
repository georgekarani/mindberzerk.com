/// The desktop cell, as MEASURED, published for the surfaces that cannot see it.
///
/// ─── WHY THIS IS NOT AN ESTIMATE ────────────────────────────────────────────
///
/// `DeskletSurfaceView.estimateCell` used to answer this from
/// `MediaQuery.sizeOf` minus the view padding, and its own doc comment admitted
/// it was approximate. That was acceptable while the error was small. It is not
/// acceptable now, because the workspace is NOT the screen: panels are siblings
/// of it and take their own space out of it, and the dock sits inside it. On a
/// GNOME-style distro that is roughly 100dp the estimate never knew about, so
/// `cell.h` read about 55dp where the real cell measured about 47. Every widget
/// sized through the dp path was seeded close to a fifth short, and the error
/// moved when you switched distros.
///
/// The surface already measures the truth inside its own `LayoutBuilder`. It
/// publishes it here, once per real change, and the picker reads it back. The
/// value is the surface's, not a second opinion about it.
///
/// ─── WHY cols AND rows RIDE ALONG ───────────────────────────────────────────
///
/// A reader that holds a cell width from one distro and a column count from
/// another produces spans that are wrong in a way nothing downstream can
/// detect. Carrying all of it as one record makes that combination
/// unrepresentable rather than merely discouraged.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/widget_span.dart';

/// The last measured desktop cell, or null before any surface has laid out.
///
/// Null is a real state and callers must handle it. It happens on a cold start
/// where the first thing built is not a graphical shell, and on the pane
/// surface, which has no grid at all.
class DeskletCellNotifier extends Notifier<DeskletCell?> {
  @override
  DeskletCell? build() => null;

  /// `.set`, never `.update`, per the standing rule. Records compare
  /// structurally, so the equality guard here is exact rather than approximate
  /// and a re-layout at the same size does not churn every reader.
  void set(DeskletCell next) {
    if (state == next) return;
    state = next;
  }
}

final deskletCellProvider = NotifierProvider<DeskletCellNotifier, DeskletCell?>(
  DeskletCellNotifier.new,
);

/// Cells (`row * cols + col`) under the dock on the desktop, published by the
/// desklet surface so the editor can refuse or redirect a drop onto them.
class DeskletDockCellsNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void set(Set<int> next) {
    if (next.length == state.length && next.containsAll(state)) return;
    state = next;
  }
}

final deskletDockCellsProvider =
    NotifierProvider<DeskletDockCellsNotifier, Set<int>>(
  DeskletDockCellsNotifier.new,
);

/// The widget grid cells under an app icon or folder, by workspace page.
///
/// ─── TWO GRIDS, ONE DESKTOP ─────────────────────────────────────────────────
///
/// A distro with desktop icons lays them out on the icon grid, and widgets
/// live on the finer widget grid in the same box. Neither knew about the
/// other, so a new widget took the first cell free of WIDGETS and landed on
/// top of whatever icons were there: ours covered them, and a hosted
/// AppWidget, which sits behind Flutter, had them painted across its face.
///
/// `HomeGrid` reports here, because it is the only place that knows where an
/// icon really is; the picker and the editor read it. Cell ids are
/// `row * cols + col`, the same scheme `dockCells` uses.
class DeskletIconCellsNotifier extends Notifier<Map<int, Set<int>>> {
  @override
  Map<int, Set<int>> build() => const {};

  void set(int page, Set<int> next) {
    final had = state[page] ?? const <int>{};
    if (had.length == next.length && had.containsAll(next)) return;
    state = {...state, page: next};
  }
}

final deskletIconCellsProvider =
    NotifierProvider<DeskletIconCellsNotifier, Map<int, Set<int>>>(
  DeskletIconCellsNotifier.new,
);

/// Config key set once a drawn desklet's footprint has been fitted to its
/// content. From then on the content scales up as well as down with the tile.
const String deskletFittedKey = 'fitted';

/// A drawn desklet's content as the desktop measured it.
///
/// ─── THE FRAME IS THE CARD ──────────────────────────────────────────────────
///
/// A tile is a whole number of grid cells; what it draws is whatever size the
/// kind authored, scaled into those cells and aligned by its surface. The two
/// rarely match, so the edit frame drawn around the cells sat far outside the
/// card, and the handles hung off empty space. Publishing the content's own
/// size lets the editor draw the frame, and place the handles, around what is
/// actually painted, and lets a resize keep the card's shape.
class DeskletContentBox {
  const DeskletContentBox({
    required this.natural,
    required this.alignment,
    required this.grows,
  });

  /// The content's size before the tile scales it, in logical pixels.
  final Size natural;

  /// Where the surface puts the content inside its tile.
  final Alignment alignment;

  /// True once fitted: the content scales to fill its box (contain), up as
  /// well as down. Before that it only ever shrinks, as it always has.
  final bool grows;

  /// The scale the tile applies inside [box].
  double scaleIn(Size box) {
    if (natural.width <= 0 || natural.height <= 0) return 1;
    final s = math.min(box.width / natural.width, box.height / natural.height);
    return grows ? s : math.min(s, 1);
  }

  /// The painted content inside [box], positioned by [alignment].
  Rect paintedIn(Size box) =>
      alignment.inscribe(natural * scaleIn(box), Offset.zero & box);

  /// Same box to within half a pixel. Text whose width moves by a sub-pixel
  /// between ticks must not republish and rebuild every editor on the page.
  bool sameAs(DeskletContentBox other) =>
      grows == other.grows &&
      alignment == other.alignment &&
      (natural.width - other.natural.width).abs() < 0.5 &&
      (natural.height - other.natural.height).abs() < 0.5;
}

/// The measured content of every drawn desklet on screen, by desklet id.
///
/// Hosted AppWidgets, stacks and window-framed tiles fill their cells, so they
/// never appear here and the editor frames their whole tile.
class DeskletContentNotifier extends Notifier<Map<String, DeskletContentBox>> {
  @override
  Map<String, DeskletContentBox> build() => const {};

  void set(String id, DeskletContentBox box) {
    final had = state[id];
    if (had != null && had.sameAs(box)) return;
    state = {...state, id: box};
  }
}

final deskletContentProvider =
    NotifierProvider<DeskletContentNotifier, Map<String, DeskletContentBox>>(
  DeskletContentNotifier.new,
);
