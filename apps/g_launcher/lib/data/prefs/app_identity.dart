import 'launcher_prefs.dart';

/// An app's identity on this launcher: the name it wears and whether its
/// notification count is drawn. PHASE G2.
///
/// Both are the person's, not the distro's, so both live in the global bucket
/// and follow them across every distro (see `GlobalPrefs.appLabels`).
///
/// Pure functions over [LauncherPrefs], like `HiddenApps` and `HomeLayout`,
/// so a caller writes them through `PrefsNotifier.edit` and the routing to the
/// global bucket happens on its own.
abstract final class AppIdentity {
  /// Icon choices, as `IconCache.setOverrides` reads them. Mirrored in Kotlin.
  static const iconApp = 'app';
  static const iconPackPrefix = 'pack:';
  static const iconImagePrefix = 'image:';

  /// Set [componentKey]'s icon to [choice], or back to the distro's when
  /// [choice] is null.
  static LauncherPrefs setIcon(
    LauncherPrefs p,
    String componentKey,
    String? choice,
  ) {
    final next = {...p.iconOverrides};
    if (choice == null) {
      next.remove(componentKey);
    } else {
      next[componentKey] = choice;
    }
    return p.copyWith(iconOverrides: next);
  }

  /// Give [componentKey] the name [name], or its own name back when [name] is
  /// null, blank, or exactly [original].
  ///
  /// Storing a rename that equals the app's own label would freeze today's
  /// label: when the app later renames itself in an update, the launcher would
  /// keep showing the old word with no way to see why.
  static LauncherPrefs rename(
    LauncherPrefs p,
    String componentKey,
    String? name, {
    required String original,
  }) {
    final next = {...p.appLabels};
    final n = name?.trim() ?? '';
    if (n.isEmpty || n == original) {
      next.remove(componentKey);
    } else {
      next[componentKey] = n;
    }
    return p.copyWith(appLabels: next);
  }

  /// Hide or show [componentKey]'s notification count.
  static LauncherPrefs muteBadge(
    LauncherPrefs p,
    String componentKey, {
    required bool muted,
  }) {
    final next = {...p.badgeMuted};
    if (muted) {
      next.add(componentKey);
    } else {
      next.remove(componentKey);
    }
    return p.copyWith(badgeMuted: next);
  }
}
