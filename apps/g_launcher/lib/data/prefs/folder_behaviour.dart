/// How a folder behaves beyond holding what it was given: whether it files new
/// apps on its own, and how it orders what it holds.
///
/// Pure functions over prefs and the app list, like `DrawerLayout` and
/// `HomeLayout`, so "the launcher moved my app" stays provable without a phone.
/// Both folder lists are handled: the drawer's (`drawerFolders`) and the
/// desktop's (`folders`), each against its own "already filed" set.
library;

import '../../platform/launcher_api.g.dart';
import 'drawer_layout.dart';
import 'folder_suggestions.dart';
import 'home_layout.dart';
import 'launcher_prefs.dart';

/// The kinds an automatic folder can file. The same signals the suggestions
/// use, so a folder that was suggested keeps meaning what it meant.
abstract final class FolderAuto {
  static const games = 'games';
  static const social = 'social';

  /// Does [app] belong in a folder of [kind]?
  ///
  /// Read off what the app declares (its manifest category, Android's game
  /// flag) plus the explicit social list. Nothing is guessed from a name.
  static bool matches(String kind, AppEntry app) => switch (kind) {
        games => app.isGame || app.category == FolderSuggestions.categoryGame,
        social => !(app.isGame ||
                app.category == FolderSuggestions.categoryGame) &&
            (FolderSuggestions.socialPackages.contains(app.packageName) ||
                app.category == FolderSuggestions.categorySocial),
        _ => false,
      };

  /// The kind a folder made BEFORE this field existed already had.
  ///
  /// Setup and the suggestions created Games and Social as plain folders, so
  /// every existing phone has one that does not know it is automatic. A folder
  /// still carrying the suggested name whose members all match is adopted;
  /// one the user renamed or mixed is left exactly as it is.
  static String? adopt(AppFolder f, Map<String, AppEntry> byKey) {
    if (f.auto != null) return f.auto;
    final kind = switch (f.name) {
      'Games' => games,
      'Social' => social,
      _ => null,
    };
    if (kind == null) return null;
    final members = [
      for (final k in f.members)
        if (byKey[k] != null) byKey[k]!,
    ];
    if (members.isEmpty) return null;
    return members.every((a) => matches(kind, a)) ? kind : null;
  }
}

/// File newly installed apps into the automatic folders. Returns [p] itself
/// (identical) when nothing changed, so a caller can skip the write.
///
/// ─── WHY [AppFolder.autoSeen] ───────────────────────────────────────────────
///
/// "Add every matching app that is not in a folder" would also re-add a game
/// the user deliberately dragged out, every time this ran. So each folder
/// remembers which matching apps it has already considered, and only a key it
/// has never seen is a new install. A folder adopted from before this existed
/// starts with only its members seen, so its first pass also gathers the
/// matching apps already loose on the phone, which is what "the Games folder
/// is automatic" has to mean on day one.
LauncherPrefs reconcileAutoFolders(LauncherPrefs p, List<AppEntry> apps) {
  final byKey = {for (final a in apps) a.componentKey: a};
  var changed = false;

  List<AppFolder> pass(List<AppFolder> folders, Set<String> filed) {
    final out = <AppFolder>[];
    for (final f in folders) {
      final kind = FolderAuto.adopt(f, byKey);
      if (kind == null) {
        out.add(f);
        continue;
      }
      final seen = {...f.autoSeen, ...f.members};
      final members = [...f.members];
      for (final a in apps) {
        final k = a.componentKey;
        if (seen.contains(k) || !FolderAuto.matches(kind, a)) continue;
        seen.add(k);
        // Already filed in another folder: the user put it there, and that
        // wins. Recorded as seen either way, so it is never reconsidered.
        if (filed.contains(k)) continue;
        members.add(k);
        filed.add(k);
      }
      final next = f.copyWith(
        auto: kind,
        members: members,
        autoSeen: (seen.toList()..sort()),
      );
      if (next != f) changed = true;
      out.add(next);
    }
    return out;
  }

  final drawer = pass(p.drawerFolders, {...DrawerLayout.foldedKeys(p)});
  final home = pass(p.folders, {...HomeLayout.foldedKeys(p)});
  if (!changed) return p;

  // A home folder that gained an app takes it off the grid, as a manual add
  // does (see HomeLayout.addToFolder).
  final homeFiled = {for (final f in home) ...f.members};
  return p.copyWith(
    drawerFolders: drawer,
    folders: home,
    homeItems: [
      for (final i in p.homeItems)
        if (i.componentKey == null || !homeFiled.contains(i.componentKey)) i,
    ],
  );
}

/// The folder ordering modes, in the order the picker lists them.
abstract final class FolderSort {
  /// The user's own order. Stored as null.
  static const String? custom = null;
  static const az = 'az';
  static const mostUsed = 'mostUsed';
}

/// [members] in the order [sort] asks for. [ranked] is the usage ranking
/// (`frequentAppsProvider`), most used first; apps never opened keep
/// alphabetical order after the ranked ones, as the drawer's own Most used
/// does.
List<AppEntry> sortFolderMembers(
  List<AppEntry> members,
  String? sort,
  List<String> ranked,
) {
  if (sort == null) return members;
  final az = [...members]
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  if (sort != FolderSort.mostUsed) return az;
  final rank = {for (var i = 0; i < ranked.length; i++) ranked[i]: i};
  final used = [
    for (final a in az)
      if (rank.containsKey(a.componentKey)) a,
  ]..sort((a, b) => rank[a.componentKey]!.compareTo(rank[b.componentKey]!));
  return [
    ...used,
    for (final a in az)
      if (!rank.containsKey(a.componentKey)) a,
  ];
}

/// Set how folder [id] orders its apps, in whichever list holds it.
LauncherPrefs setFolderSort(LauncherPrefs p, String id, String? sort) =>
    p.copyWith(
      drawerFolders: [
        for (final f in p.drawerFolders)
          f.id == id ? f.copyWith(sort: [sort]) : f,
      ],
      folders: [
        for (final f in p.folders) f.id == id ? f.copyWith(sort: [sort]) : f,
      ],
    );

/// Make the order on screen the folder's own order, and switch it to custom.
///
/// Called before a drag inside a sorted folder: the user dragged against what
/// they SEE, so that order is frozen first and the move applied to it. Keys
/// missing from [ordered] (an app the screen did not show) keep their place
/// after it rather than being dropped.
LauncherPrefs freezeFolderOrder(
  LauncherPrefs p,
  String id,
  List<String> ordered,
) {
  AppFolder freeze(AppFolder f) {
    if (f.id != id) return f;
    final shown = {...ordered};
    return f.copyWith(
      members: [
        for (final k in ordered)
          if (f.members.contains(k)) k,
        for (final k in f.members)
          if (!shown.contains(k)) k,
      ],
      sort: const [null],
    );
  }

  return p.copyWith(
    drawerFolders: [for (final f in p.drawerFolders) freeze(f)],
    folders: [for (final f in p.folders) freeze(f)],
  );
}
