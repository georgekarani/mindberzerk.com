part of 'wallpaper_screen.dart';

// ─── THE WALLPAPER PAGE, IMMERSIVE ──────────────────────────────────────────
//
// The page used to be a settings list with six shelves of thumbnails in two
// sizes, a help sheet per shelf for the gestures, and the wallpaper itself
// shown only as two small previews in a card. Now the wallpaper in use IS the
// page: blurred full bleed behind everything, the lock and home previews on
// top of it, one row of sources and one grid of tiles that are all the same
// phone shape.
//
// Nothing explains itself in text. Hidden presets leave the grid instead of
// sitting there dimmed, Edit makes hide, remove and drag visible on the tiles
// rather than behind a long press, and a tap opens the wallpaper full screen
// before it is set.
//
// Every control is drawn in the active distro's own idiom by [_Kit]: Adwaita
// pills on GNOME, Breeze rectangles on Plasma, glass capsules on Aqua, sharp
// outlines on the tiling and terminal desktops. No label has a line limit or
// an ellipsis; a long translation wraps and the control grows.

/// The sources the page can show, in tab order.
enum _Source { distro, others, photos, collections, live }

/// The active distro's control idiom.
class _Kit {
  const _Kit({
    required this.shell,
    required this.accent,
    required this.onAccent,
    required this.font,
    required this.scale,
  });

  factory _Kit.of(EffectiveTheme t) {
    final accent = t.palette.accent;
    final mono = t.shell == ShellKind.tiling || t.shell == ShellKind.tui;
    return _Kit(
      shell: t.shell,
      accent: accent,
      onAccent: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white // theme-exempt: legible ink on the accent
          : const Color(0xFF111111), // theme-exempt: legible ink
      font: mono ? t.typography.mono : t.typography.display,
      scale: t.textScale,
    );
  }

  final ShellKind shell;
  final Color accent;
  final Color onAccent;
  final String? font;
  final double scale;

  static const _ink = Colors.white; // theme-exempt: ink over a photo

  bool get _aqua => shell == ShellKind.aqua;
  bool get _breeze => shell == ShellKind.plasma;
  bool get _sharp => shell == ShellKind.tiling || shell == ShellKind.tui;

  /// Corner radius of a button.
  double get radius => switch (shell) {
        ShellKind.gnome => 24,
        ShellKind.plasma => 5,
        ShellKind.aqua => 25,
        ShellKind.tiling => 4,
        ShellKind.tui => 0,
      };

  double get tileRadius => switch (shell) {
        ShellKind.gnome => 12,
        ShellKind.plasma => 6,
        ShellKind.aqua => 18,
        ShellKind.tiling => 4,
        ShellKind.tui => 0,
      };

  double get sheetRadius => switch (shell) {
        ShellKind.gnome => 28,
        ShellKind.plasma => 12,
        ShellKind.aqua => 34,
        ShellKind.tiling => 8,
        ShellKind.tui => 0,
      };

  /// An idle control over the photo.
  Color get glass => _breeze
      ? const Color(0xE02A2E32) // theme-exempt: Breeze button face
      : _sharp
          ? Colors.black.withValues(alpha: 0.45) // theme-exempt: scrim
          : _ink.withValues(alpha: _aqua ? 0.22 : 0.16);

  BorderSide get glassBorder => _breeze || _sharp
      ? BorderSide(color: _ink.withValues(alpha: _sharp ? 0.4 : 0.22))
      : BorderSide.none;

  /// The one action a screen exists for. Aqua draws it white, as iOS does.
  Color get primaryFill => _aqua ? _ink : accent;
  Color get primaryInk =>
      _aqua ? const Color(0xFF111111) : onAccent; // theme-exempt: iOS ink

  /// The ring around the wallpaper in use.
  BorderSide get ring => BorderSide(
        color: _aqua ? _ink : accent,
        width: _breeze || _sharp ? 2 : 3,
      );

  TextStyle label(Color color, {double size = 15, FontWeight? weight}) =>
      TextStyle(
        fontFamily: font,
        fontSize: size * scale,
        height: 1.25,
        fontWeight: weight ?? (_breeze ? FontWeight.w600 : FontWeight.w700),
        color: color,
      );

  ShapeBorder shape(double r, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);
}

/// A 44dp icon button over the photo.
class _KitIcon extends StatelessWidget {
  const _KitIcon({
    required this.kit,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final _Kit kit;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = kit._breeze || kit._sharp ? kit.radius : 22.0;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 44,
          height: 44,
          child: _Glass(
            enabled: kit._aqua,
            radius: r,
            child: Material(
              color: kit.glass,
              shape: kit.shape(r, kit.glassBorder),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Icon(icon, size: 20, color: _Kit._ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled button over the photo: primary (the accent) or secondary.
class _KitButton extends StatelessWidget {
  const _KitButton({
    required this.kit,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  final _Kit kit;
  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = primary ? kit.primaryInk : _Kit._ink;
    final side = primary
        ? (kit._breeze ? BorderSide(color: kit.accent) : BorderSide.none)
        : kit.glassBorder;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: _Glass(
        enabled: kit._aqua && !primary,
        radius: kit.radius,
        child: Material(
          color: primary ? kit.primaryFill : kit.glass,
          shape: kit.shape(kit.radius, side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: ink),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: kit.label(ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A frosted backing, Aqua only. Elsewhere the child is drawn as it is.
class _Glass extends StatelessWidget {
  const _Glass({
    required this.enabled,
    required this.radius,
    required this.child,
  });

  final bool enabled;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => !enabled
      ? child
      : ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: child,
          ),
        );
}

/// The source tabs, on the sheet, in the distro's tab idiom: pills (GNOME),
/// an underlined tab bar (Plasma), a segmented track (Aqua), outlined boxes
/// (tiling, terminal). Scrolls sideways rather than squeezing a long name.
class _KitTabs extends StatelessWidget {
  const _KitTabs({
    required this.kit,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final _Kit kit;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;

    Widget tab(int i) {
      final on = i == selected;
      final Color fill;
      final Color ink;
      BorderSide side = BorderSide.none;
      if (kit._breeze) {
        fill = Colors.transparent;
        ink = on ? c.text : c.textMuted;
      } else if (kit._aqua) {
        fill = on ? c.text : Colors.transparent;
        ink = on ? c.bg : c.text;
      } else if (kit._sharp) {
        fill = on ? kit.accent : Colors.transparent;
        ink = on ? kit.onAccent : c.text;
        side = BorderSide(color: on ? kit.accent : c.line);
      } else {
        fill = on ? kit.accent : c.text.withValues(alpha: 0.08);
        ink = on ? kit.onAccent : c.text;
      }
      final r = kit._breeze ? 0.0 : (kit._aqua ? 17.0 : kit.radius);

      return Semantics(
        selected: on,
        button: true,
        child: Material(
          color: fill,
          shape: kit.shape(r, side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(i);
            },
            child: Container(
              constraints: BoxConstraints(minHeight: kit._aqua ? 36 : 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: kit._breeze
                  ? BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: on ? kit.accent : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    )
                  : null,
              child: Text(labels[i], style: kit.label(ink, size: 14)),
            ),
          ),
        ),
      );
    }

    final row = Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) SizedBox(width: kit._breeze || kit._aqua ? 2 : 8),
          tab(i),
        ],
      ],
    );

    final Widget track = kit._aqua
        ? Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.text.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: row,
          )
        : kit._breeze
            ? DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: row,
              )
            : row;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: track,
    );
  }
}

/// Home, Lock, Both: a joined control over the photo.
class _KitSegment extends StatelessWidget {
  const _KitSegment({
    required this.kit,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final _Kit kit;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final aqua = kit._aqua;
    final r = aqua ? 22.0 : (kit._breeze || kit._sharp ? kit.radius : 12.0);

    Widget seg(int i) {
      final on = i == selected;
      final fill = on
          ? (aqua ? _Kit._ink : kit.accent)
          : (aqua ? Colors.transparent : _Kit._ink.withValues(alpha: 0.10));
      final ink = on ? (aqua ? kit.primaryInk : kit.onAccent) : _Kit._ink;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: fill,
            shape: aqua ? kit.shape(19) : const RoundedRectangleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(i);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: kit.label(ink, size: 14),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(aqua ? 3 : 0),
      decoration: BoxDecoration(
        color: aqua ? _Kit._ink.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(r),
        border: kit._breeze || kit._sharp
            ? Border.all(color: kit.glassBorder.color)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(aqua ? 19 : r),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) SizedBox(width: aqua ? 2 : 1),
                seg(i),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A wallpaper as an image, whatever kind of reference it is: a theme asset
/// (bundled or from an installed pack), a CDN thumbnail, or the user's own
/// file. The same resolution the old strip used, shared by grid and preview.
Widget _wallpaperImage(String src, ThemeSource source) {
  final isRemote = src.startsWith('http');
  final themed =
      !isRemote && isThemeAssetRef(src) ? source.asset(src) : null;
  if (themed != null) {
    return Image(
      image: themed.image,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const _Missing(Icons.image_not_supported_outlined),
    );
  }
  if (isRemote) {
    return Image.network(
      src,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(child: ThemedProgress.circular(size: 20)),
      errorBuilder: (_, __, ___) => const _Missing(Icons.cloud_off_outlined),
    );
  }
  return Image.file(
    File(src),
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const _Missing(Icons.broken_image_outlined),
  );
}

/// One grid of same-shape tiles for a source.
///
/// In edit mode a tile shows what can be done to it: an eye on the distro's
/// own (hidden rather than deleted), a cross on the user's photos, and a grip
/// to drag it to a new place. Out of edit mode a tap opens the preview.
class _WallpaperGrid extends StatelessWidget {
  const _WallpaperGrid({
    required this.kit,
    required this.sources,
    required this.sourceFor,
    required this.current,
    required this.onOpen,
    this.editing = false,
    this.hidden = const {},
    this.onHide,
    this.onRemove,
    this.onReorder,
    this.onAdd,
    this.addLabel,
  });

  final _Kit kit;
  final List<String> sources;
  final ThemeSource Function(String src) sourceFor;
  final String? current;
  final void Function(int index) onOpen;
  final bool editing;
  final Set<String> hidden;
  final void Function(String src, bool hide)? onHide;
  final void Function(String src)? onRemove;
  final void Function(int from, int to)? onReorder;
  final VoidCallback? onAdd;
  final String? addLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final cell = _phoneCells(box.maxWidth, gap: gap);
      final w = cell.w;
      final h = cell.h;
      final add = onAdd;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < sources.length; i++)
            SizedBox(width: w, height: h, child: _tile(context, i, Size(w, h))),
          if (add != null && !editing)
            SizedBox(width: w, height: h, child: _addTile(context, add)),
        ],
      );
    });
  }

  Widget _addTile(BuildContext context, VoidCallback add) =>
      _AddCell(kit: kit, label: addLabel, onTap: add);

  Widget _tile(BuildContext context, int i, Size size) {
    final src = sources[i];
    final isHidden = hidden.contains(src);
    final selected = !editing && src == current;
    final hide = onHide;
    final remove = onRemove;
    final reorder = onReorder;

    Widget face = ClipRRect(
      borderRadius: BorderRadius.circular(kit.tileRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _wallpaperImage(src, sourceFor(src)),
          if (isHidden)
            ColoredBox(color: Colors.black.withValues(alpha: 0.6)), // theme-exempt: dims a photo
          if (editing && reorder != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 30,
                color: Colors.black.withValues(alpha: 0.42), // theme-exempt: scrim
                child: const Icon(Icons.drag_indicator, size: 18, color: _Kit._ink),
              ),
            ),
        ],
      ),
    );

    face = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: kit.shape(kit.tileRadius, selected ? kit.ring : BorderSide.none),
      ),
      child: face,
    );

    final tile = Semantics(
      button: true,
      selected: selected,
      label: '${i + 1}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (editing) {
            // In edit mode a tap on a hidden one brings it back; anything
            // else is left to the badges.
            if (isHidden && hide != null) hide(src, false);
            return;
          }
          onOpen(i);
        },
        // A hold hides the picture from this tab. In Edit the hold belongs
        // to dragging, and a hidden one comes back with a tap there.
        onLongPress: !editing && hide != null && !isHidden
            ? () {
                HapticFeedback.mediumImpact();
                hide(src, true);
              }
            : null,
        child: face,
      ),
    );

    final badgeAction = editing
        ? (remove != null
            ? () => remove(src)
            : hide != null
                ? () => hide(src, !isHidden)
                : null)
        : null;
    final withBadge = badgeAction == null
        ? tile
        : Stack(
            fit: StackFit.expand,
            children: [
              tile,
              Positioned(
                top: 0,
                right: 0,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: _KitIcon(
                        kit: kit,
                        icon: remove != null
                            ? Icons.close
                            : (isHidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                        label: remove != null
                            ? context.t('desklets.remove')
                            : context.t(isHidden ? 'wallpaper.show' : 'wallpaper.hide'),
                        onTap: badgeAction,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

    if (!editing || reorder == null) return withBadge;

    // ─── A HOLD LIFTS, A DROP ON ANOTHER TILE MOVES ───────────────────────
    //
    // Flutter has no reorderable grid, so each tile is both a draggable and a
    // target. Dropping on tile `to` moves the dragged one into that place,
    // which is the after-removal index the callers' insert already expects.
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) {
        HapticFeedback.selectionClick();
        reorder(d.data, i);
      },
      builder: (context, candidates, _) => LongPressDraggable<int>(
        data: i,
        delay: const Duration(milliseconds: 180),
        hapticFeedbackOnStart: true,
        feedback: Transform.scale(
          scale: 1.06,
          child: SizedBox.fromSize(
            size: size,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kit.tileRadius),
              child: _wallpaperImage(src, sourceFor(src)),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: withBadge),
        child: AnimatedScale(
          scale: candidates.isNotEmpty ? 0.94 : 1,
          duration: const Duration(milliseconds: 120),
          child: withBadge,
        ),
      ),
    );
  }
}

/// The dashed-in "add" cell every grid on this page ends with.
class _AddCell extends StatelessWidget {
  const _AddCell({
    required this.kit,
    required this.onTap,
    this.label,
    this.icon = Icons.add,
  });

  final _Kit kit;
  final VoidCallback onTap;
  final String? label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.text.withValues(alpha: 0.06),
        shape: kit.shape(kit.tileRadius, BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Center(child: Icon(icon, size: 28, color: c.textMuted)),
        ),
      ),
    );
  }
}

/// Columns and cell size for a grid of phone-shaped tiles, the same answer
/// for every source so the tabs line up when you switch between them.
({int cols, double w, double h}) _phoneCells(double width, {double gap = 8}) {
  final cols = width >= 600 ? 5 : 3;
  final w = (width - gap * (cols - 1)) / cols;
  return (cols: cols, w: w, h: w * 2.05);
}

/// Collections as albums: a mosaic of the first photos over the name.
///
/// The collection rotation draws from carries the accent's shuffle mark, so
/// which set is live is visible without a line saying so. An empty set shows
/// a plain face rather than a broken image: it is a real state, and one you
/// have to be able to open to fix.
class _CollectionsGrid extends StatelessWidget {
  const _CollectionsGrid({
    required this.kit,
    required this.collections,
    required this.rotationSource,
    required this.onOpen,
    required this.onNew,
  });

  final _Kit kit;
  final List<WallpaperCollection> collections;
  final String? rotationSource;
  final void Function(String id) onOpen;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return LayoutBuilder(builder: (context, box) {
      const gap = 10.0;
      final cols = box.maxWidth >= 600 ? 3 : 2;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      final radius = kit.tileRadius + 4;

      Widget card({
        required Widget face,
        required Widget caption,
        required VoidCallback onTap,
        String? semantics,
      }) =>
          SizedBox(
            width: w,
            child: Semantics(
              button: true,
              label: semantics,
              child: Material(
                color: c.text.withValues(alpha: 0.06),
                shape: kit.shape(radius, BorderSide(color: c.line)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(aspectRatio: 1, child: face),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final col in collections)
            card(
              semantics: '${col.name}, ${col.paths.length}',
              onTap: () => onOpen(col.id),
              face: Stack(
                fit: StackFit.expand,
                children: [
                  _Mosaic(paths: col.paths, empty: c.surfaceAlt, ink: c.textMuted),
                  if (rotationSource == RotationSource.collections ||
                      rotationSource == RotationSource.collection(col.id))
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: kit.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.shuffle, size: 16, color: kit.onAccent),
                      ),
                    ),
                ],
              ),
              caption: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(col.name, style: kit.label(c.text, size: 14)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${col.paths.length}',
                    style: kit.label(c.textMuted, size: 13, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          card(
            semantics: context.t('settings.newCollection'),
            onTap: onNew,
            face: Center(
              child: Icon(Icons.add, size: 30, color: c.textMuted),
            ),
            caption: Text(
              context.t('settings.newCollection'),
              style: kit.label(c.textMuted, size: 14),
            ),
          ),
        ],
      );
    });
  }
}

/// One photo, or one large and two small, for a collection's face.
class _Mosaic extends StatelessWidget {
  const _Mosaic({required this.paths, required this.empty, required this.ink});

  final List<String> paths;
  final Color empty;
  final Color ink;

  Widget _photo(String path) => Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 360,
        errorBuilder: (_, __, ___) =>
            const _Missing(Icons.broken_image_outlined),
      );

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return ColoredBox(
        color: empty,
        child: Center(
          child: Icon(Icons.photo_library_outlined, size: 30, color: ink),
        ),
      );
    }
    if (paths.length < 3) return _photo(paths.first);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 2, child: _photo(paths[0])),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _photo(paths[1])),
              const SizedBox(height: 2),
              Expanded(child: _photo(paths[2])),
            ],
          ),
        ),
      ],
    );
  }
}

/// The motion wallpaper, on the same phone-shaped cells as the stills.
///
/// No thumbnail, deliberately: a frame out of the video would need a decoder
/// pass on the way into this page, and the file is already playing behind
/// everything once it is set. The ringed cell with its accent mark says the
/// only thing a thumbnail would: one is running.
class _LiveGrid extends ConsumerWidget {
  const _LiveGrid({required this.kit, required this.onPick});

  final _Kit kit;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ChromeScope.of(context).colors;
    final active = ref.watch(motionActiveProvider).value ?? false;
    final lockSet = ref.watch(lockMotionProvider).value ?? false;

    Widget liveCell({
      required IconData icon,
      required String label,
      required IconData mark,
      VoidCallback? onTap,
      VoidCallback? onRemove,
    }) {
      final cell = Semantics(
        button: onTap != null,
        selected: true,
        label: label,
        excludeSemantics: true,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(shape: kit.shape(kit.tileRadius, kit.ring)),
          child: Material(
            color: c.surfaceAlt,
            shape: kit.shape(kit.tileRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(child: Icon(icon, size: 36, color: c.text)),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: kit.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(mark, size: 16, color: kit.onAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (onRemove == null) return cell;
      return Stack(
        fit: StackFit.expand,
        children: [
          cell,
          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: _KitIcon(
                    kit: kit,
                    icon: Icons.close,
                    label: context.t('desklets.remove'),
                    onTap: onRemove,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final cell = _phoneCells(box.maxWidth);
      SizedBox sized(Widget child) =>
          SizedBox(width: cell.w, height: cell.h, child: child);

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // ─── HOME, THEN LOCK ────────────────────────────────────────────
          //
          // The home video is the live wallpaper itself. A second video for
          // the lock screen is offered only once one is running, because the
          // service that plays it is the same one: it switches to the lock
          // video while the phone is locked.
          if (active)
            sized(liveCell(
              icon: Icons.play_circle_outline,
              label: context.t('settings.live'),
              mark: Icons.home_outlined,
            )),
          if (active && lockSet)
            sized(liveCell(
              icon: Icons.play_circle_outline,
              label: context.t('wallpaper.lock'),
              mark: Icons.lock_outline,
              onTap: () => pickLockMotion(context, ref),
              onRemove: () => clearLockMotion(ref),
            )),
          sized(_AddCell(
            kit: kit,
            icon: active ? Icons.swap_horiz : Icons.video_call_outlined,
            label: context.t(active ? 'settings.replace' : 'settings.addAVideo'),
            onTap: onPick,
          )),
          if (active && !lockSet)
            sized(_AddCell(
              kit: kit,
              icon: Icons.lock_outline,
              label: context.t('wallpaper.lockVideo'),
              onTap: () => pickLockMotion(context, ref),
            )),
        ],
      );
    });
  }
}

/// A wallpaper full screen before it is set, swiping through its source.
class _WallpaperPreviewPage extends ConsumerStatefulWidget {
  const _WallpaperPreviewPage({
    required this.theme,
    required this.sources,
    required this.initial,
    required this.sourceFor,
  });

  final EffectiveTheme theme;
  final List<String> sources;
  final int initial;
  final ThemeSource Function(String src) sourceFor;

  @override
  ConsumerState<_WallpaperPreviewPage> createState() =>
      _WallpaperPreviewPageState();
}

class _WallpaperPreviewPageState extends ConsumerState<_WallpaperPreviewPage> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  /// 0 home, 1 lock, 2 both. Starts on both when the launcher already owns
  /// the lock screen, else home.
  late int _target = (widget.theme.prefs.wallpaperLock ?? false) ? 2 : 0;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _set() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await applyWallpaper(
      context,
      ref,
      widget.theme,
      widget.sources[_index],
      targets: (home: _target != 1, lock: _target != 0),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kit = _Kit.of(widget.theme);
    final pad = MediaQuery.paddingOf(context);
    final many = widget.sources.length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black, // theme-exempt: behind a photo
        body: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pages,
                itemCount: many,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _wallpaperImage(
                  widget.sources[i],
                  widget.sourceFor(widget.sources[i]),
                ),
              ),
            ),
            Positioned(
              top: pad.top + 12,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  _KitIcon(
                    kit: kit,
                    icon: Icons.close,
                    label: context.t('common.close'),
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: many < 2 || many > 12
                        ? const SizedBox.shrink()
                        : ExcludeSemantics(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < many; i++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                    width: i == _index ? 16 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _Kit._ink.withValues(
                                          alpha: i == _index ? 1 : 0.5),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: pad.bottom + 12,
              child: _Glass(
                enabled: true,
                radius: kit.sheetRadius - 4,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42), // theme-exempt: scrim
                    borderRadius: BorderRadius.circular(kit.sheetRadius - 4),
                    border: Border.all(color: _Kit._ink.withValues(alpha: 0.14)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _KitSegment(
                        kit: kit,
                        labels: [
                          context.t('wallpaper.home'),
                          context.t('wallpaper.lock'),
                          context.t('wallpaper.both'),
                        ],
                        selected: _target,
                        onSelect: (i) => setState(() => _target = i),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Flexible(
                            child: _KitButton(
                            kit: kit,
                            icon: Icons.crop_free,
                            label: context.t('wallpaper.frame'),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => WallpaperFramingScreen(
                                  theme: widget.theme,
                                  source: widget.sources[_index],
                                ),
                              ),
                            ),
                          ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _KitButton(
                              kit: kit,
                              primary: true,
                              label: context.t('wallpaper.set'),
                              onTap: _busy ? null : _set,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
