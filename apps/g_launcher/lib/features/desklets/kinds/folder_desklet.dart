import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../../data/prefs/drawer_layout.dart';
import '../../../data/prefs/home_layout.dart';
import '../../../data/prefs/launcher_prefs.dart';
import '../../../data/repositories/shell_apps.dart';
import '../../../data/usage/usage_repository.dart';
import '../../../design/components/components.dart';
import '../../../engine/desklet_skin.dart';
import '../../../engine/desklet_spec.dart';
import '../../../engine/effective_theme.dart';
import '../../../engine/theme_spec.dart' show parseColor;
import '../../../platform/launcher_api.g.dart' show AppEntry;
import '../../drawer/app_icon.dart';
import '../../drawer/drawer_actions.dart';
import '../../drawer/drawer_items.dart'
    show FolderDrawerItem, countsAsRecentlyAdded;
import '../../drawer/folder_overlay.dart';

/// Where a large folder's apps come from. PHASE 7.
enum FolderSource {
  /// Newest installs first, from each package's own first-install time.
  recent('recent'),

  /// The usage ranking that orders the dock's defaults and Kickoff's
  /// Frequent rail.
  frequent('frequent'),

  /// One of the user's own folders, on the home screen or in the drawer.
  folder('folder');

  const FolderSource(this.id);

  final String id;

  static FolderSource parse(Object? raw) {
    for (final s in values) {
      if (s.id == raw) return s;
    }
    return recent;
  }
}

/// What a large folder shows, resolved once per build.
typedef FolderContents = ({
  String title,
  List<AppEntry> apps,

  /// The user folder behind it, for opening the real folder screen, or null
  /// for the two lists the launcher keeps itself.
  AppFolder? folder,
  bool inDrawer,
});

/// Resolve [desklet]'s source against the installed apps.
///
/// A folder that has since been deleted resolves to an empty list under its
/// last known purpose, not to an exception: the placement is the user's, and
/// it stays on the desktop until they remove or repoint it.
FolderContents resolveFolderContents(
  WidgetRef ref,
  EffectiveTheme theme,
  Desklet desklet,
) {
  final apps = ref.watch(shellAppsProvider(theme));
  final byKey = {for (final a in apps) a.componentKey: a};
  final config = desklet.config;

  switch (FolderSource.parse(config['source'])) {
    case FolderSource.recent:
      // System apps carry the factory image's date, and a shelf of
      // preinstalled apps is not what "recently added" means. Same rule as
      // the App Library's shelf in drawer_items.
      final recent = [
        for (final a in apps)
          if (countsAsRecentlyAdded(a)) a,
      ]..sort((a, b) => b.firstInstallTime.compareTo(a.firstInstallTime));
      return (
        title: tr('desklets.folder.recent'),
        apps: recent,
        folder: null,
        inDrawer: false,
      );
    case FolderSource.frequent:
      return (
        title: tr('desklets.folder.frequent'),
        apps: [
          for (final k in ref.watch(frequentAppsProvider))
            if (byKey[k] != null) byKey[k]!,
        ],
        folder: null,
        inDrawer: false,
      );
    case FolderSource.folder:
      final id = config['folderId'];
      final inDrawer = config['folderStore'] == 'drawer';
      final f = id is! String
          ? null
          : inDrawer
              ? DrawerLayout.folder(theme.prefs, id)
              : HomeLayout.folder(theme.prefs, id);
      return (
        title: f?.name ?? tr('desklets.folder.missing'),
        apps: [
          for (final k in f?.members ?? const <String>[])
            if (byKey[k] != null) byKey[k]!,
        ],
        folder: f,
        inDrawer: inDrawer,
      );
  }
}

/// A large folder on the desktop: a 2x2 or 3x3 grid of real app icons. Tap an
/// icon to launch it; tap the title, or the count in the last cell, for the
/// whole list.
///
/// ─── AUTHORED AT A NATURAL SIZE ─────────────────────────────────────────────
///
/// Like every drawn desklet, this lays out at a fixed size and the desktop's
/// FittedBox scales it into the tile, so the user's content scale and the
/// picker preview both work with no special case. The icon size is the
/// launcher's own, and the grid count only decides how many fit.
class FolderDesklet extends ConsumerWidget {
  const FolderDesklet({
    super.key,
    required this.theme,
    required this.desklet,
    required this.skin,
  });

  final EffectiveTheme theme;
  final Desklet desklet;
  final DeskletSkin skin;

  static const _icon = 52.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contents = resolveFolderContents(ref, theme, desklet);
    final grid = DeskletKinds.folder
        .read<num>(desklet.config, 'grid', 2)
        .toInt()
        .clamp(2, 3);
    final slots = grid * grid;

    // The last cell becomes a count once there are more apps than cells, so
    // the folder never pretends to be complete when it is not.
    final overflow = contents.apps.length > slots;
    final shown = contents.apps.take(overflow ? slots - 1 : slots).toList();
    final rest = contents.apps.length - shown.length;

    void openAll() => _openAll(context, ref, theme, contents);

    if (skin.surface == DeskletSurface.terminal) {
      return _TerminalListing(
        theme: theme,
        skin: skin,
        contents: contents,
        shown: shown,
        rest: rest,
        onOpen: openAll,
        onLaunch: (a) => launchDrawerApp(ref, a),
      );
    }

    final p = theme.palette;
    final accent = parseColor(skin.text('accentHex', '')) ?? p.accent;
    final labels = skin.flag('labels', skin.surface == DeskletSurface.card);
    final cellW = labels ? _icon + 16 : _icon;

    final cells = <Widget>[
      for (final a in shown)
        _IconCell(
          theme: theme,
          entry: a,
          size: _icon,
          width: cellW,
          label: labels,
          onTap: (bounds) => launchDrawerApp(ref, a, iconBounds: bounds),
        ),
      if (rest > 0 && overflow)
        _CountCell(
          theme: theme,
          count: rest,
          size: _icon,
          width: cellW,
          label: labels,
          onTap: openAll,
        ),
    ];

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(
          theme: theme,
          skin: skin,
          text: contents.title,
          accent: accent,
          onTap: openAll,
        ),
        const SizedBox(height: 12),
        if (contents.apps.isEmpty)
          SizedBox(
            width: grid * cellW + (grid - 1) * _gap,
            height: _icon,
            child: Center(
              child: Text(
                tr('desklets.folder.empty'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: theme.typography.display,
                  fontSize: 13,
                  color: p.onDark.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else
          SizedBox(
            width: grid * cellW + (grid - 1) * _gap,
            child: Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: cells,
            ),
          ),
      ],
    );

    return switch (skin.surface) {
      // A panel tile: flat, with the accent edge every waybar module wears.
      DeskletSurface.panel => DecoratedBox(
          decoration: BoxDecoration(
            color: skin.fill(p.bar, 0.9),
            borderRadius: BorderRadius.circular(skin.num_('radius', 4)),
            border: Border.all(color: accent, width: 1.5),
          ),
          child: Padding(padding: const EdgeInsets.all(12), child: body),
        ),
      // A Breeze card, Plasma's Folder View.
      DeskletSurface.card => DecoratedBox(
          decoration: BoxDecoration(
            color: skin.fill(p.bar, 0.72),
            borderRadius: BorderRadius.circular(skin.num_('radius', 10)),
            border: Border.all(color: p.onDark.withValues(alpha: 0.12)),
          ),
          child: Padding(padding: const EdgeInsets.all(14), child: body),
        ),
      // GNOME and the iOS-like desktops: a translucent plate, rounder, the
      // way their own folders sit on the wallpaper. Text alone would leave
      // icons floating with nothing to say they belong together.
      DeskletSurface.bare || DeskletSurface.terminal => DecoratedBox(
          decoration: BoxDecoration(
            color: p.bgBottom.withValues(alpha: skin.num_('opacity', 0.45)),
            borderRadius: BorderRadius.circular(skin.num_('radius', 26)),
            border: Border.all(color: p.onDark.withValues(alpha: 0.14)),
          ),
          child: Padding(padding: const EdgeInsets.all(16), child: body),
        ),
    };
  }
}

/// The whole list: the real folder screen for a user folder, a sheet for the
/// two lists the launcher keeps itself.
Future<void> _openAll(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
  FolderContents contents,
) async {
  final f = contents.folder;
  if (f != null) {
    if (contents.inDrawer) {
      await showFolderOverlay(
        context,
        ref,
        theme,
        FolderDrawerItem(f, contents.apps),
      );
    } else {
      await showHomeFolderOverlay(context, ref, theme, f.id);
    }
    return;
  }
  if (contents.apps.isEmpty) return;
  await ThemedSheet.show<void>(
    context,
    title: contents.title,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Wrap(
        spacing: 12,
        runSpacing: 14,
        children: [
          for (final a in contents.apps.take(40))
            _IconCell(
              theme: theme,
              entry: a,
              size: 48,
              width: 72,
              label: true,
              labelColour: ChromeScope.of(sheet).colors.text,
              onTap: (bounds) {
                Navigator.of(sheet).pop();
                launchDrawerApp(ref, a, iconBounds: bounds);
              },
            ),
        ],
      ),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title({
    required this.theme,
    required this.skin,
    required this.text,
    required this.accent,
    required this.onTap,
  });

  final EffectiveTheme theme;
  final DeskletSkin skin;
  final String text;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final panel = skin.surface == DeskletSurface.panel;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 2,
              style: TextStyle(
                fontFamily: panel || skin.font == DeskletFont.mono
                    ? theme.typography.mono
                    : theme.typography.display,
                fontSize: skin.num_('titleSize', 15),
                fontWeight: FontWeight.w600,
                color: panel || skin.accent ? accent : p.onDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.theme,
    required this.entry,
    required this.size,
    required this.width,
    required this.label,
    required this.onTap,
    this.labelColour,
  });

  final EffectiveTheme theme;
  final AppEntry entry;
  final double size;
  final double width;
  final bool label;
  final ValueChanged<Rect?> onTap;
  final Color? labelColour;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: entry.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // The icon's own rectangle, so the launch animation grows from it.
          final box = context.findRenderObject() as RenderBox?;
          final bounds = box == null || !box.hasSize
              ? null
              : box.localToGlobal(Offset.zero) & box.size;
          onTap(bounds);
        },
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(entry: entry, size: size),
              if (label) ...[
                const SizedBox(height: 4),
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: theme.typography.display,
                    fontSize: 11,
                    color: labelColour ?? theme.palette.onDark,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountCell extends StatelessWidget {
  const _CountCell({
    required this.theme,
    required this.count,
    required this.size,
    required this.width,
    required this.label,
    required this.onTap,
  });

  final EffectiveTheme theme;
  final int count;
  final double size;
  final double width;
  final bool label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.onDark.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(size * 0.28),
                ),
                child: Text(
                  '+$count',
                  style: TextStyle(
                    fontFamily: theme.typography.display,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.onDark,
                  ),
                ),
              ),
              // Keeps the row's baseline when the other cells are labelled.
              if (label) const SizedBox(height: 19),
            ],
          ),
        ),
      ),
    );
  }
}

/// The terminal's large folder: `ls` of it, one launchable name per line.
class _TerminalListing extends StatelessWidget {
  const _TerminalListing({
    required this.theme,
    required this.skin,
    required this.contents,
    required this.shown,
    required this.rest,
    required this.onOpen,
    required this.onLaunch,
  });

  final EffectiveTheme theme;
  final DeskletSkin skin;
  final FolderContents contents;
  final List<AppEntry> shown;
  final int rest;
  final VoidCallback onOpen;
  final ValueChanged<AppEntry> onLaunch;

  /// A name as `ls` would print it: lower case, no spaces.
  static String _slug(String s) => s.toLowerCase().replaceAll(' ', '-');

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final mono = theme.typography.mono;
    final size = skin.num_('rowSize', 13);
    final style = TextStyle(fontFamily: mono, fontSize: size, height: 1.6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(
                  text: '~ ❯ ',
                  style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  // Commands stay English, like `df -h`: it names a path.
                  text: 'ls ~/${_slug(contents.title)}',
                  style: TextStyle(color: p.onDark.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ),
        for (final a in shown)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onLaunch(a),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  '${_slug(a.label)}*',
                  style: style.copyWith(color: p.onDark),
                ),
              ),
            ),
          ),
        if (rest > 0)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Text(
              '+$rest',
              style: style.copyWith(color: p.onDark.withValues(alpha: 0.5)),
            ),
          ),
      ],
    );
  }
}
