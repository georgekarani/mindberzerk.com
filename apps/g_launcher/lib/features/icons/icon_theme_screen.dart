/// Settings > Icons: what configures icons on this phone.
///
/// The current icon theme (which opens the store), shape and size, and icon
/// packs installed from Play. Choosing and buying a style is the store's job,
/// in `icon_store_screen.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/cdn/pack_repository.dart';
import '../../data/repositories/app_repository.dart';
import '../../design/components/components.dart';
import '../../design/setting_previews.dart' show SettingPreview;
import '../../engine/effective_theme.dart';
import '../../platform/launcher_api.g.dart';
import '../../platform/pack_api.g.dart';
import '../drawer/app_icon.dart';
import '../settings/settings_rows.dart';
import 'icon_appearance_rows.dart';
import 'icon_pack_actions.dart';
import 'icon_store_screen.dart';

/// One native handle for coverage lookups: a new Pigeon wrapper per card is
/// a new codec instance for no reason.
final _previewApi = PackHostApi();

/// Third-party icon packs installed as APKs: package name -> label.
///
/// AN EMPTY MAP IS A REAL ANSWER and draws the empty state, never an error. Note
/// while debugging that empty is ALSO what a missing `<queries>` declaration
/// produces on Android 11+, silently, on a phone with forty packs installed.
/// Check the manifest before this file.
///
/// A FutureProvider rather than widget state so it survives a rebuild, and so
/// `ref.invalidate` is the whole of "refresh" when someone installs a pack and
/// comes back.
final installedIconThemesProvider = FutureProvider<Map<String, String>>((ref) {
  return ref.read(launcherHostApiProvider).installedIconPacks();
});

/// The installed APK behind a third-party pack, so its own launcher icon can be
/// the preview.
///
/// This is the one honest preview available for a third-party pack and it costs
/// nothing: those apps almost always put a sample of their art on their own
/// icon, and `AppIcon` already knows how to draw one. `componentKey` is
/// `package/class`, so the match is on the segment before the slash.
///
/// Null when the pack is not in the app list, which happens for a pack that has
/// no launcher activity. The card falls back to the schematic.
final iconThemeAppProvider =
    Provider.family<AppEntry?, String>((ref, packageName) {
  final apps = ref.watch(appListProvider).asData?.value ?? const <AppEntry>[];
  for (final a in apps) {
    if (a.componentKey.split('/').first == packageName) return a;
  }
  return null;
});

/// How many of this device's apps a pack actually draws, or null.
///
/// ─── THE ONLY MEASURED NUMBER ON THE SCREEN ─────────────────────────────────
///
/// Everything else a card can say comes from the index and is a claim about the
/// pack: a title, a price, 13,622 drawings. This is a claim about the phone in
/// the user's hand, and it is the difference between "13,622 icons" and "41 of
/// your 46 apps", which is the number they were actually asking about.
///
/// Watches [appListProvider] rather than caching against it, so installing or
/// removing an app re-asks. Native memoises on the app-list size, so that
/// re-ask is free unless the count genuinely moved.
///
/// Also watches [catalogueProvider], because an install is what turns a null
/// answer into a real one: nothing can be counted until the pack is on disk.
///
/// NULL IS A RESULT, not an error. The pack is not installed yet, or it is a
/// theme rather than an icon set, or its json would not parse. The row is
/// simply absent for all three, which is this app's rule for a nullable stat
/// and the honest reading here: a `0 of 46` would describe a pack that covers
/// nothing, which is a different and much worse thing than one that has not
/// been asked yet.
final packCoverageProvider =
    FutureProvider.family<PackCoverage?, String>((ref, packId) async {
  ref.watch(appListProvider);
  ref.watch(catalogueProvider);
  // Swallowed rather than surfaced. A missing caption costs nothing and the
  // card behind it is still correct and still tappable; an error state here
  // would put a retry button on a number nobody asked for.
  //
  // try/catch rather than `catchError`, which on a `Future<PackCoverage?>`
  // takes a `Function` and loses the return type: a handler returning the wrong
  // thing is a runtime cast failure inside the provider rather than a compile
  // error here.
  try {
    return await _previewApi.packCoverage(packId);
  } catch (_) {
    return null;
  }
});

/// Which other distro's colour is being previewed, by distro base id.
///
/// ─── PREVIEW IS NOT A SETTING ───────────────────────────────────────────────
///
/// Deliberately NOT in prefs. It lasts as long as the screen is open and dies
/// with it, because it describes a moment of shopping rather than a choice the
/// user made. Persisting it would mean reopening Icons and finding a distro you
/// do not own already tried on, which reads as something having changed.
///
/// Null means the running distro, which is what the try-on shows before any
/// swatch is tapped.
class IconThemeScreen extends ConsumerWidget {
  const IconThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(effectiveThemeProvider);
    return themeAsync.when(
      loading: () => ThemedScaffold(
        title: context.t('settings.icons'),
        body: const SizedBox.shrink(),
      ),
      error: (_, __) => ThemedScaffold(
        title: context.t('settings.icons'),
        body: const SizedBox.shrink(),
      ),
      data: (theme) => _Settings(theme: theme),
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings({required this.theme});

  final EffectiveTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = IconPackActions(context, ref, theme);
    final catalogue = ref.watch(catalogueProvider).value ?? const <PackInfo>[];
    final installed = ref.watch(installedIconThemesProvider).value ??
        const <String, String>{};

    String? titleOf(String? id) {
      if (id == null) return null;
      for (final p in catalogue) {
        if (p.packId == id && p.title.isNotEmpty) return p.title;
      }
      return null;
    }

    // What is drawn on top: a Linux theme when one is worn, else the line pack,
    // else the apps' own icons.
    final line = actions.appliedLine;
    final current = titleOf(theme.prefs.iconPackId) ??
        titleOf(line) ??
        context.t(line == null ? 'icons.original' : 'icons.distroDefault');

    final system = theme.prefs.systemIconPack;
    final systemLabel =
        system == null ? context.t('icons.none') : installed[system] ?? system;

    return ThemedScaffold(
      title: context.t('settings.icons'),
      settingsLook: true,
      body: RowIcons(
        show: false,
        child: ListView(
          padding: EdgeInsets.only(
            top: 8,
            bottom: 28 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            const _YourIcons(),
            SettingsGroup(
              label: context.t('icons.iconTheme'),
              rows: [
                FilterRow(
                  const ['icon theme', 'papirus', 'arcticons', 'line', 'store'],
                  SettingsRow(
                    icon: Icons.palette_outlined,
                    title: context.t('icons.theme'),
                    trailing: ValueLabel(current),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const IconStoreScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // The live picture stays out: the row of real icons above is it.
            for (final w in iconAppearanceRows(context, ref, theme))
              if (w is! SettingPreview) w,
            SettingsGroup(
              label: context.t('icons.fromPlay'),
              rows: [
                FilterRow(
                  const ['icon pack', 'nova', 'adw', 'play'],
                  SettingsRow(
                    icon: Icons.apps_outlined,
                    title: context.t('icons.playPacks'),
                    trailing: ValueLabel(systemLabel),
                    onTap: () => _pickSystemPack(
                      context,
                      actions,
                      installed,
                      system,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A sheet listing None and every Nova or ADW pack installed from Play.
  static Future<void> _pickSystemPack(
    BuildContext context,
    IconPackActions actions,
    Map<String, String> installed,
    String? selected,
  ) =>
      showLookSheet(
        context,
        title: context.t('icons.playPacks'),
        builder: (sheet) {
          final c = ChromeScope.of(sheet).colors;

          Widget option(String? id, String label) => InkWell(
                onTap: () {
                  Navigator.of(sheet).pop();
                  if (id != selected) unawaited(actions.chooseSystemPack(id));
                },
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: c.text),
                        ),
                      ),
                      if (id == selected)
                        Icon(Icons.check, size: 20, color: c.accent),
                    ],
                  ),
                ),
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              option(null, context.t('icons.none')),
              for (final e in installed.entries) option(e.key, e.value),
              if (installed.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    context.t('icons.noPlayPacks'),
                    style: TextStyle(fontSize: 12.5, color: c.textMuted),
                  ),
                ),
            ],
          );
        },
      );
}

/// Five of this phone's apps, drawn exactly as the drawer draws them now.
class _YourIcons extends ConsumerWidget {
  const _YourIcons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = (ref.watch(appListProvider).value ?? const <AppEntry>[])
        .take(5)
        .toList();
    if (apps.isEmpty) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final a in apps)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: AppIcon(entry: a, size: 44, showBadge: false),
            ),
        ],
      ),
    );
  }
}
