/// Keeps automatic folders filed: a new game lands in Games as it installs.
///
/// Mounted around the desktop, which is alive whenever the launcher is, and
/// listens to the app list rather than polling: a package install is what
/// changes that list, so the folder updates as soon as the app appears. The
/// rule itself is `reconcileAutoFolders`, pure and testable; this only decides
/// when to run it and writes only when it changed something.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/prefs/folder_behaviour.dart';
import '../../data/prefs/home_layout.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../data/repositories/shell_apps.dart';
import '../../engine/effective_theme.dart';
import '../../platform/launcher_api.g.dart';

class AutoFolders extends ConsumerStatefulWidget {
  const AutoFolders({super.key, required this.theme, required this.child});

  final EffectiveTheme theme;
  final Widget child;

  @override
  ConsumerState<AutoFolders> createState() => _AutoFoldersState();
}

class _AutoFoldersState extends ConsumerState<AutoFolders> {
  @override
  void initState() {
    super.initState();
    // Once at start, for an install that happened while the launcher was not
    // running, and for adopting folders made before this existed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(ref.read(shellAppsProvider(widget.theme)));
    });
  }

  void _sync(List<AppEntry> apps, {Set<String> installed = const {}}) {
    // An empty list is the app list still loading, not a phone with no apps.
    if (apps.isEmpty) return;
    final theme = widget.theme;
    LauncherPrefs apply(LauncherPrefs p) =>
        _placeNewOnHome(reconcileAutoFolders(p, apps), installed);
    final current = theme.prefs;
    // Identical when nothing changed: a write here would reload prefs and
    // rebuild the desktop for no reason.
    if (identical(apply(current), current)) return;
    ref.read(prefsProvider(theme.spec.id).notifier).edit(apply);
  }

  /// iPhone's default: a newly installed app gets a home-screen icon.
  ///
  /// Only on a distro whose data lays apps on the home screen at all
  /// (`home.fill`, Pocket), so a Linux desktop with an empty grid stays empty.
  /// After the folders, so a new game filed into Games does not also appear
  /// loose. First free slot from page one on, a new page when all are full.
  LauncherPrefs _placeNewOnHome(LauncherPrefs p, Set<String> installed) {
    final theme = widget.theme;
    if (installed.isEmpty || theme.spec.home.fill <= 0) return p;
    final capacity = theme.rows * theme.cols;
    if (capacity <= 0) return p;
    final filed = HomeLayout.foldedKeys(p);
    var out = p;
    for (final key in installed) {
      if (filed.contains(key) ||
          HomeLayout.isOnHome(out, key) ||
          out.favourites.contains(key)) {
        continue;
      }
      for (var page = 0; page < 20; page++) {
        final next =
            HomeLayout.seedToHome(out, key, page: page, capacity: capacity);
        if (!identical(next, out)) {
          out = next;
          break;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // listen, not watch: the desktop below never rebuilds for this.
    ref.listen<List<AppEntry>>(shellAppsProvider(widget.theme), (prev, next) {
      if (prev == null || prev.length != next.length || prev != next) {
        // New = in the list now and not before. Null `prev` is the first
        // load, where nothing is new: those apps were already installed.
        final before = {for (final a in prev ?? next) a.componentKey};
        final installed = {
          for (final a in next)
            if (!before.contains(a.componentKey)) a.componentKey,
        };
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync(next, installed: installed);
        });
      }
    });
    return widget.child;
  }
}
