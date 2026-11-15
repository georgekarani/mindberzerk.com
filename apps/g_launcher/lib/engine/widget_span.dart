/// How big a hosted Android AppWidget should be, in OUR fine grid cells.
///
/// ─── THE ASYMMETRY THIS FILE EXISTS FOR ─────────────────────────────────────
///
/// A provider declares its footprint in one of two units, and they are NOT
/// interchangeable:
///
///   minWidthDp / minHeightDp        ABSOLUTE, in dp. Grid-agnostic. Convert by
///                                   dividing by what a cell measures here.
///
///   targetCellWidth / Height (31+)  RELATIVE, in LAUNCHER GRID CELLS. Authored
///                                   against a conventional 4 or 5 column grid.
///                                   Convert by multiplying into our finer one.
///
/// The bug this replaces multiplied `targetCellWidth` by a nominal 70dp and
/// then divided by the real cell. Its comment justified the 70 as "a standard
/// launcher's cells, which are roughly square and roughly 70dp". That premise
/// is false twice over. The 70 in Android's published `70n - 30` relationship
/// is a 2010-era 320dp-screen artifact that exists only to GENERATE the
/// declared dp a developer writes in XML; it has never described a modern cell,
/// which is about 100dp wide and about 150dp tall and nowhere near square.
///
/// Measured on a 411dp phone with a 4x5 icon grid, Spotify's 4x2 media widget
/// came out at 75% of its authored width and 50% of its height. It rendered
/// perfectly. It was simply handed the wrong rectangle.
///
/// ─── WHY THE GRID PATH NEEDS NO MEASUREMENT AT ALL ──────────────────────────
///
/// `targetCellWidth: 4` means "four of the launcher's columns". Our fine grid
/// is the icon grid times [DeskletLayout.colFactor] by [DeskletLayout.rowFactor],
/// so four icon columns is exactly `4 * colFactor` fine columns. No dp, no cell
/// measurement, no estimate, and it stays correct when the user changes their
/// column count or switches to a distro with a different grid: a widget that
/// filled the width still fills it.
///
/// ─── AND THE DP PATH GOES THROUGH LAUNCHER CELLS TOO ────────────────────────
///
/// It used to divide the declared dp by our cell, on the reasoning that a
/// legacy provider "declared a minimum, not a target". That handed the widget
/// its bare minimum, which no other launcher does: a provider writing 250dp by
/// 110dp is saying "4 by 2 cells" in the only unit it had, and every launcher
/// reads it back with the same `70n - 30` relationship and then gives it four
/// columns and two rows of ITS cells, which on a modern phone is far more than
/// 250 by 110. Layouts are designed for that room. Given the minimum instead,
/// Apple Music's 4 x 2 list came out about 260dp by 88dp with its second row
/// cut in half, under a picker preview showing four rows.
///
/// So dp is converted to launcher cells first and then multiplied into the
/// fine grid, exactly like the grid path. The placed widget is the size the
/// picker's label has always claimed.
///
/// ─── PURE, SO IT CAN BE TESTED WITHOUT A PHONE ──────────────────────────────
///
/// Same treatment `LayoutResolver` and `HomeLayout` already get. Nothing here
/// imports Flutter, Riverpod or the Pigeon api: [resolve] takes plain numbers
/// and the two adapters below convert. A grid arithmetic bug that only shows up
/// on one device is exactly the class of bug a unit test should catch first.
library;

/// A resolved footprint plus the limits a resize drag must respect.
class WidgetSpan {
  const WidgetSpan({
    required this.spanX,
    required this.spanY,
    required this.minSpanX,
    required this.minSpanY,
    required this.maxSpanX,
    required this.maxSpanY,
  });

  /// The footprint to place at, in fine grid cells. Always >= 1.
  final int spanX;
  final int spanY;

  /// How small a resize drag may go. Derived from `minResize*Dp`, and equal to
  /// [spanX] / [spanY] on an axis the provider declared non-resizable.
  final int minSpanX;
  final int minSpanY;

  /// How large a resize drag may go. The grid's own edge normally, and pinned
  /// to [spanX] / [spanY] on a non-resizable axis.
  ///
  /// NOT `maxResizeWidth`/`maxResizeHeight`. Those are API 31+ and are not in
  /// the Pigeon schema yet; adding them is two appended ints and belongs with
  /// the next schema change that has to happen anyway. Until then a widget can
  /// be stretched further than its author intended, which is the smaller of the
  /// two failures and the one users can undo.
  final int maxSpanX;
  final int maxSpanY;

  bool get resizableX => maxSpanX > minSpanX;

  bool get resizableY => maxSpanY > minSpanY;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetSpan &&
          other.spanX == spanX &&
          other.spanY == spanY &&
          other.minSpanX == minSpanX &&
          other.minSpanY == minSpanY &&
          other.maxSpanX == maxSpanX &&
          other.maxSpanY == maxSpanY;

  @override
  int get hashCode =>
      Object.hash(spanX, spanY, minSpanX, minSpanY, maxSpanX, maxSpanY);

  @override
  String toString() => 'WidgetSpan($spanX x $spanY, min $minSpanX x $minSpanY, '
      'max $maxSpanX x $maxSpanY)';
}

/// Android's `AppWidgetProviderInfo.resizeMode` bitmask.
abstract final class WidgetResize {
  static const int none = 0;
  static const int horizontal = 1;
  static const int vertical = 2;

  static bool canResizeX(int mode) => mode & horizontal != 0;

  static bool canResizeY(int mode) => mode & vertical != 0;
}

/// The measured desktop cell, and the grid it belongs to.
///
/// Carried as one record rather than four loose doubles because every function
/// here needs all of it, and because a caller holding a cell from one distro
/// and a column count from another is a real mistake that this shape prevents.
typedef DeskletCell = ({
  double w,
  double h,
  int cols,
  int rows,
  double gutter,
});

/// Everything a footprint can be derived from, already flattened out of both
/// the Pigeon class and the stored config so [resolve] never sees either.
typedef WidgetFootprint = ({
  int minWidthDp,
  int minHeightDp,
  int minResizeWidthDp,
  int minResizeHeightDp,
  int targetCellWidth,
  int targetCellHeight,
  int resizeMode,
});

/// The config keys an `appwidget` desklet stores. One place, because the
/// picker writes them and the surface reads them back, and a typo in either
/// half is silent: the widget simply keeps whatever span it was born with.
abstract final class WidgetConfigKeys {
  static const widgetId = 'widgetId';
  static const providerKey = 'providerKey';
  static const label = 'label';
  static const minWidthDp = 'minWidthDp';
  static const minHeightDp = 'minHeightDp';
  static const minResizeWidthDp = 'minResizeWidthDp';
  static const minResizeHeightDp = 'minResizeHeightDp';
  static const targetCellWidth = 'targetCellWidth';
  static const targetCellHeight = 'targetCellHeight';
  static const resizeMode = 'resizeMode';

  /// Set the moment the user drags a resize handle. From then on the automatic
  /// re-derive leaves this widget alone.
  ///
  /// Without it, changing your column count would silently undo every manual
  /// resize on the desktop, which is a worse betrayal than the wrong initial
  /// size this whole file exists to fix.
  static const userSized = 'userSized';
}

abstract final class WidgetSpanResolver {
  /// The one rule. Everything else in this file adapts into it.
  ///
  /// [colFactor] / [rowFactor] are `DeskletLayout`'s, passed in rather than
  /// imported so this stays a pure function of its arguments.
  static WidgetSpan resolve(
    WidgetFootprint f, {
    required DeskletCell cell,
    required int colFactor,
    required int rowFactor,
  }) {
    final cols = cell.cols < 1 ? 1 : cell.cols;
    final rows = cell.rows < 1 ? 1 : cell.rows;

    // ─── THE FOOTPRINT ────────────────────────────────────────────────────
    //
    // Launcher cells either way: the provider's own when it gave them, the
    // ones its dp stands for otherwise. Then into the fine grid. A provider
    // that reported nothing keeps one fine cell rather than a whole icon cell.
    //
    // A cell that has not been measured yet (zero or not finite) also answers
    // one: there is no desktop to size against, and the next layout pass
    // re-derives with a real cell.
    bool measured(double size) => size.isFinite && size > 0;
    final sx = f.targetCellWidth > 0
        ? f.targetCellWidth * colFactor
        : (f.minWidthDp > 0 && measured(cell.w)
            ? launcherCells(f.minWidthDp) * colFactor
            : 1);
    final sy = f.targetCellHeight > 0
        ? f.targetCellHeight * rowFactor
        : (f.minHeightDp > 0 && measured(cell.h)
            ? launcherCells(f.minHeightDp) * rowFactor
            : 1);

    final spanX = sx.clamp(1, cols);
    final spanY = sy.clamp(1, rows);

    // ─── THE LIMITS ───────────────────────────────────────────────────────
    //
    // `minResize*Dp` is always in dp, even on providers that expressed their
    // footprint in cells, so it always goes through the dp path. The Pigeon
    // doc guarantees it equals the min size on a non-resizable axis, but the
    // resizeMode bit is checked anyway: a provider that reports both is not
    // obliged to keep them consistent, and a resize handle that appears on a
    // RESIZE_NONE widget is a visible bug either way.
    final floorX =
        _cellsForDp(f.minResizeWidthDp, cell.w, cell.gutter).clamp(1, spanX);
    final floorY =
        _cellsForDp(f.minResizeHeightDp, cell.h, cell.gutter).clamp(1, spanY);

    final canX = WidgetResize.canResizeX(f.resizeMode);
    final canY = WidgetResize.canResizeY(f.resizeMode);

    return WidgetSpan(
      spanX: spanX,
      spanY: spanY,
      minSpanX: canX ? floorX : spanX,
      minSpanY: canY ? floorY : spanY,
      maxSpanX: canX ? cols : spanX,
      maxSpanY: canY ? rows : spanY,
    );
  }

  /// Read a footprint straight out of a stored desklet config.
  ///
  /// Tolerant in the same way `Desklet.fromJson` is: absent keys read as zero
  /// and fall through to the next rule rather than throwing. A placement
  /// written by an older build simply has less to go on, not a crash.
  static WidgetFootprint footprintFromConfig(Map<String, Object?> config) {
    int read(String key) => (config[key] as num?)?.toInt() ?? 0;
    return (
      minWidthDp: read(WidgetConfigKeys.minWidthDp),
      minHeightDp: read(WidgetConfigKeys.minHeightDp),
      minResizeWidthDp: read(WidgetConfigKeys.minResizeWidthDp),
      minResizeHeightDp: read(WidgetConfigKeys.minResizeHeightDp),
      targetCellWidth: read(WidgetConfigKeys.targetCellWidth),
      targetCellHeight: read(WidgetConfigKeys.targetCellHeight),
      resizeMode: read(WidgetConfigKeys.resizeMode),
    );
  }

  /// Has the user resized this one by hand?
  static bool isUserSized(Map<String, Object?> config) =>
      config[WidgetConfigKeys.userSized] == true;

  /// The rectangle a span occupies, in dp, gutter removed.
  ///
  /// This is the widget's real CONTENT box: what the host will report to the
  /// provider through `updateAppWidgetOptions`, and what the picker must ask
  /// the preview renderer for so that what you see is what you place.
  static ({double w, double h}) contentBox(
    int spanX,
    int spanY, {
    required DeskletCell cell,
  }) {
    final w = spanX * cell.w - cell.gutter;
    final h = spanY * cell.h - cell.gutter;
    return (w: w < 1 ? 1 : w, h: h < 1 ? 1 : h);
  }

  /// Width over height of the rectangle a span occupies. Falls back to 1
  /// rather than dividing by zero before the surface has measured.
  static double aspectOf(int spanX, int spanY, {required DeskletCell cell}) {
    final box = contentBox(spanX, spanY, cell: cell);
    if (box.h <= 0) return 1;
    final a = box.w / box.h;
    return a.isFinite && a > 0 ? a : 1;
  }

  /// How many LAUNCHER cells a declared dp stands for.
  ///
  /// The inverse of Android's `70n - 30`, rounded up, which is how every
  /// launcher reads a provider that predates `targetCellWidth`: 250dp is four
  /// cells, 110dp is two.
  static int launcherCells(int dp) {
    if (dp <= 0) return 1;
    final n = ((dp + 30) / 70).ceil();
    return n < 1 ? 1 : n;
  }

  /// dp to cells, with the gutter accounted for. For resize floors only: the
  /// smallest a widget may be dragged to is a real dp limit, not a cell count.
  ///
  /// A tile of n cells is drawn inside `n * cell - gutter` of usable space, so
  /// dividing the raw dp by the raw cell is short by up to a full cell on a
  /// fine grid. Ceil rather than round, because a widget given LESS than it
  /// asked for clips its own layout, and a little slack around it costs
  /// nothing.
  static int _cellsForDp(int dp, double cellSize, double gutter) {
    if (dp <= 0 || !cellSize.isFinite || cellSize <= 0) return 1;
    final n = ((dp + gutter) / cellSize).ceil();
    return n < 1 ? 1 : n;
  }
}
