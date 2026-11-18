/// One search, every distro. PHASE 5.
///
/// ─── WHAT WAS MISSING ───────────────────────────────────────────────────────
///
/// Every search surface already ranked APPS the same way
/// (`paletteResultsProvider`), but everything that is not an app lived in one
/// or two of them. Sums, unit conversions and `!bang` sites appeared in the
/// One UI page and the drop-down sheet and nowhere else; app shortcuts only in
/// the One UI page; Android settings only as fixed chips there. So the same
/// query found different things on KDE, in rofi and on Pocket, and a person
/// who learned `=12*7` on one distro found it gone on the next.
///
/// This file is the rest of the answer, decided once. Each surface keeps its
/// own app list in its own idiom (KRunner rows, a rofi list, a Spotlight
/// stack) and puts [UnifiedExtraRows] beside it, drawn in that surface's
/// colours through [CommandRowStyle].
///
/// ─── WHAT IT FINDS ──────────────────────────────────────────────────────────
///
///  commands   `=`, `:`, `!` and bare sums, through [CommandRouter]
///  shortcuts  every app's shortcuts whose label matches, in one native call
///  Android    a fixed set of AOSP settings pages, matched on name and synonyms
///  Settings   "Search settings for …", which opens G Launcher's own settings
///             with the query typed, so every row it filters is reachable and
///             there is no second list of settings here to fall out of date
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/recent_searches.dart';
import '../../data/repositories/app_repository.dart';
import '../../data/repositories/shell_apps.dart';
import '../../design/branded_message.dart';
import '../../engine/effective_theme.dart';
import '../../platform/launcher_api.g.dart';
import '../command/command_router.dart';
import '../command/command_rows.dart';
import '../command/search_settings.dart';
import '../drawer/app_icon.dart';
import '../settings/settings_screen.dart';

/// The shortest query that searches shortcuts and settings. One letter
/// matches half of every list, which is noise rather than an answer.
const _minExtraQuery = 2;

/// Most shortcut rows shown at once. Shortcuts are a side dish next to apps.
const _maxShortcuts = 4;

/// Most Android settings rows shown at once.
const _maxTopics = 3;

/// An Android settings page this launcher can open on any phone.
///
/// A FIXED, universal set on purpose. Vendor topics (Samsung's Eye comfort,
/// Xiaomi's Second space) dead-end on the Infinix, Tecno and Pixel phones this
/// launcher also runs on. These are AOSP actions that resolve virtually
/// everywhere. [keywords] are English synonyms; the localised label is
/// matched too, so a German query for "Akku" finds Battery.
class SettingsTopic {
  const SettingsTopic(this.icon, this.labelKey, this.action, this.keywords);

  final IconData icon;
  final String labelKey;
  final String action;
  final List<String> keywords;
}

const androidSettingsTopics = <SettingsTopic>[
  SettingsTopic(Icons.wifi, 'search.wifi', 'android.settings.WIFI_SETTINGS',
      ['wifi', 'wi-fi', 'wlan', 'internet', 'network']),
  SettingsTopic(Icons.bluetooth, 'search.bluetooth',
      'android.settings.BLUETOOTH_SETTINGS', ['bluetooth', 'pair', 'headphones']),
  SettingsTopic(Icons.cell_tower, 'search.connections',
      'android.settings.WIRELESS_SETTINGS',
      ['connections', 'mobile data', 'airplane', 'hotspot', 'network']),
  SettingsTopic(Icons.brightness_6_outlined, 'search.display',
      'android.settings.DISPLAY_SETTINGS',
      ['display', 'brightness', 'screen', 'dark mode', 'font size']),
  SettingsTopic(Icons.volume_up_outlined, 'search.sound',
      'android.settings.SOUND_SETTINGS',
      ['sound', 'volume', 'ringtone', 'vibration', 'do not disturb']),
  SettingsTopic(Icons.battery_charging_full_outlined, 'search.battery',
      'android.intent.action.POWER_USAGE_SUMMARY',
      ['battery', 'power', 'charging']),
  SettingsTopic(Icons.sd_storage_outlined, 'desklet_spec.storage',
      'android.settings.INTERNAL_STORAGE_SETTINGS',
      ['storage', 'space', 'memory', 'free up']),
  SettingsTopic(Icons.apps_outlined, 'search.apps',
      'android.settings.APPLICATION_SETTINGS',
      ['apps', 'applications', 'uninstall', 'default apps']),
  SettingsTopic(Icons.location_on_outlined, 'search.location',
      'android.settings.LOCATION_SOURCE_SETTINGS', ['location', 'gps']),
  SettingsTopic(Icons.shield_outlined, 'search.security',
      'android.settings.SECURITY_SETTINGS',
      ['security', 'lock screen', 'password', 'fingerprint', 'pin']),
  SettingsTopic(Icons.schedule, 'search.dateTime',
      'android.settings.DATE_SETTINGS', ['date', 'time', 'time zone', 'clock']),
  SettingsTopic(Icons.language, 'search.language',
      'android.settings.LOCALE_SETTINGS', ['language', 'locale', 'keyboard']),
];

/// The topics [query] names, best first: a label or synonym that STARTS with
/// the query beats one that only contains it.
List<SettingsTopic> topicsFor(String query, String Function(String) label) {
  final q = query.trim().toLowerCase();
  if (q.length < _minExtraQuery) return const [];
  final starts = <SettingsTopic>[];
  final contains = <SettingsTopic>[];
  for (final t in androidSettingsTopics) {
    final words = [label(t.labelKey).toLowerCase(), ...t.keywords];
    if (words.any((w) => w.startsWith(q))) {
      starts.add(t);
    } else if (words.any((w) => w.contains(q))) {
      contains.add(t);
    }
  }
  return [...starts, ...contains].take(_maxTopics).toList();
}

/// Shortcuts from every app matching [query], for the visible apps only.
///
/// Auto-disposing and uncached, the same rule as the per-app row: a shortcut
/// is the publishing app's live state. A short pause before asking lets a
/// burst of keystrokes cost one native call instead of one each.
final shortcutSearchProvider = FutureProvider.autoDispose
    .family<List<SearchedShortcut>, String>((ref, query) async {
  final q = query.trim();
  if (q.length < _minExtraQuery) return const [];

  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 160));
  if (disposed) return const [];

  try {
    return await ref
        .read(launcherHostApiProvider)
        .searchShortcuts(q, _maxShortcuts * 3);
  } catch (_) {
    return const [];
  }
});

/// Everything that is not an app, for one query, drawn in a surface's style.
///
/// Renders nothing at all when there is nothing to show, so a surface can put
/// it beside its app list unconditionally.
class UnifiedExtraRows extends ConsumerWidget {
  const UnifiedExtraRows({
    super.key,
    required this.theme,
    required this.query,
    required this.style,
    required this.onClose,
    this.fillQuery,
    this.commands = true,
  });

  final EffectiveTheme theme;
  final String query;
  final CommandRowStyle style;

  /// Called when a result has opened something and the search should go.
  final VoidCallback onClose;

  /// Replaces the typed query, for a bang hint. Null where a surface cannot.
  final void Function(String)? fillQuery;

  /// False on a surface that already draws command rows itself, so a sum is
  /// not answered twice.
  final bool commands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim();
    if (q.isEmpty) return const SizedBox.shrink();

    final hits = commands
        ? CommandRouter.route(q, extraBangs: ref.watch(extraBangsProvider)).hits
        : const <CommandHit>[];

    // Shortcuts only from apps this distro shows, so hiding an app hides its
    // shortcuts too.
    final visible = {
      for (final a in ref.watch(shellAppsProvider(theme))) a.componentKey: a,
    };
    final shortcuts = [
      for (final s in ref.watch(shortcutSearchProvider(q)).asData?.value ??
          const <SearchedShortcut>[])
        if (visible[s.componentKey] case final app?) (shortcut: s, app: app),
    ].take(_maxShortcuts).toList();

    final topics = topicsFor(q, context.t);
    // Only when Settings will show something for it: a row that opens an
    // empty page is a dead end, and "wifi" matches nothing of the launcher's
    // own while matching Android's Wi-Fi page above.
    final showSettings = q.length >= _minExtraQuery &&
        settingsMatchCount(context, ref, theme, q) > 0;

    if (hits.isEmpty && shortcuts.isEmpty && topics.isEmpty && !showSettings) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final hit in hits)
          CommandHitRow(
            hit: hit,
            style: style,
            onTap: () async {
              final close = await activateCommandHit(
                context,
                ref,
                hit,
                query: q,
                fillQuery: fillQuery ?? (_) {},
              );
              if (close) onClose();
            },
            onBang: fillQuery == null ? null : (b) => fillQuery!('!${b.key} '),
          ),
        if (shortcuts.isNotEmpty) ...[
          _Header(text: context.t('search.shortcuts'), style: style),
          for (final r in shortcuts)
            _ExtraRow(
              style: style,
              leading: AppIcon(
                entry: r.app,
                size: 24 * style.scale,
                showBadge: false,
              ),
              title: r.shortcut.label,
              subtitle: r.app.label,
              disabled: r.shortcut.disabled,
              onTap: () => _launchShortcut(context, ref, r.shortcut, q),
            ),
        ],
        if (topics.isNotEmpty || showSettings)
          _Header(text: context.t('settings.settings'), style: style),
        for (final t in topics)
          _ExtraRow(
            style: style,
            leading: Icon(t.icon, size: 22 * style.scale, color: style.accent),
            title: context.t(t.labelKey),
            subtitle: context.t('search.androidSettings'),
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(recentSearchesProvider.notifier).record(q);
              ref.read(launcherHostApiProvider).openAndroidSettings(t.action);
              onClose();
            },
          ),
        if (showSettings)
          _ExtraRow(
            style: style,
            leading: Icon(Icons.tune, size: 22 * style.scale, color: style.accent),
            title: context.t('search.inSettings', {'query': q}),
            subtitle: context.t('search.launcherSettings'),
            onTap: () {
              HapticFeedback.selectionClick();
              // Captured first: closing the search can take this context
              // with it.
              final navigator = Navigator.of(context, rootNavigator: true);
              onClose();
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SettingsScreen(theme: theme, initialQuery: q),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _launchShortcut(
    BuildContext context,
    WidgetRef ref,
    SearchedShortcut s,
    String q,
  ) async {
    if (s.disabled) {
      context.showMessage(context.t('search.shortcutUnavailable'));
      return;
    }
    HapticFeedback.selectionClick();
    final ok = await ref
        .read(launcherHostApiProvider)
        .launchShortcut(s.componentKey, s.id, null, null, null, null);
    if (!context.mounted) return;
    if (!ok) {
      context.showMessage(context.t('search.shortcutUnavailable'));
      return;
    }
    ref.read(recentSearchesProvider.notifier).record(q);
    onClose();
  }
}

/// A small section label above a group of rows.
class _Header extends StatelessWidget {
  const _Header({required this.text, required this.style});

  final String text;
  final CommandRowStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: 11 * style.scale,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: style.muted,
        ),
      ),
    );
  }
}

/// One result row: a glyph or icon, a title and a muted line under it.
class _ExtraRow extends StatelessWidget {
  const _ExtraRow({
    required this.style,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
  });

  final CommandRowStyle style;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final s = style;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              SizedBox(width: 28 * s.scale, child: Center(child: leading)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      style: TextStyle(
                        fontFamily: s.fontFamily,
                        fontSize: 14 * s.scale,
                        color: s.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: s.fontFamily,
                        fontSize: 12 * s.scale,
                        color: s.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
