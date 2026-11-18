// Guards Phase 9: icon tint, the page indicator, Recently added, contacts in
// search and notification history settings, and their strings.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_launcher/data/prefs/global_prefs.dart';
import 'package:g_launcher/data/prefs/launcher_prefs.dart';
import 'package:g_launcher/data/update/update_repository.dart';
import 'package:g_launcher/engine/effective_theme.dart';
import 'package:g_launcher/engine/theme_spec.dart';
import 'package:g_launcher/features/drawer/drawer_items.dart';
import 'package:g_launcher/platform/launcher_api.g.dart';

const _translated = [
  'ar', 'de', 'en', 'es', 'fa', 'fr', 'hi', 'id', 'it', 'ja', //
  'ko', 'nl', 'pl', 'pt', 'ru', 'tr', 'uk', 'vi', 'zh_CN', 'zh_TW',
];

const _accent = Color(0xFFE95420);

ThemeSpec _spec() => ThemeSpec.fromJson(<String, dynamic>{
      'id': 'x',
      'name': 'X',
      'shell': 'gnome',
      'palette': <String, dynamic>{
        'bgTop': '#000000',
        'bgBottom': '#000000',
        'bar': '#1E1E1E',
        'dock': '#000000',
        'accent': '#E95420',
        'onDark': '#FFFFFF',
      },
    });

AppEntry _app(
  String packageName, {
  bool system = false,
  int installed = 1000,
}) =>
    AppEntry(
      componentKey: '$packageName/.Main#0',
      packageName: packageName,
      className: '.Main',
      userSerial: 0,
      label: packageName,
      updateToken: 0,
      isWorkProfile: false,
      isSuspended: false,
      isSystem: system,
      category: -1,
      isGame: false,
      firstInstallTime: installed,
    );

void main() {
  group('icon tint', () {
    test('is off by default and keeps the icon key unchanged', () {
      final off = EffectiveTheme.resolve(_spec(), const LauncherPrefs());
      expect(off.icons.iconTint, isNull);
    });

    test('accent resolves to the accent in force', () {
      final t = EffectiveTheme.resolve(
        _spec(),
        const LauncherPrefs(iconTint: 'accent'),
      );
      expect(t.icons.iconTint, _accent.toARGB32());
    });

    test('wallpaper with no usable colour falls back to the accent', () {
      final t = EffectiveTheme.resolve(
        _spec(),
        const LauncherPrefs(iconTint: 'wallpaper'),
      );
      expect(t.icons.iconTint, _accent.toARGB32());
    });

    test('changes the icon cache id, so tinted icons are re-drawn', () {
      final off = EffectiveTheme.resolve(_spec(), const LauncherPrefs());
      final on = EffectiveTheme.resolve(
        _spec(),
        const LauncherPrefs(iconTint: 'accent'),
      );
      expect(on.iconCacheId, isNot(off.iconCacheId));
    });

    test('round-trips and clears', () {
      const p = LauncherPrefs(iconTint: 'wallpaper');
      final back = LauncherPrefs.fromJson(p.toJson());
      expect(back.iconTint, 'wallpaper');
      expect(back.clearing(iconTint: true).iconTint, isNull);
    });
  });

  group('contacts and notification history switches', () {
    test('are off by default', () {
      const p = LauncherPrefs();
      expect(p.contactsSearch, isNull);
      expect(p.notificationHistory, isNull);
    });

    test('are promoted, so they read the same on every distro', () {
      const before = LauncherPrefs();
      expect(
        GlobalPrefs.from(before.copyWith(contactsSearch: true)).contactsSearch,
        isTrue,
      );
      expect(
        GlobalPrefs.from(before.copyWith(notificationHistory: true))
            .notificationHistory,
        isTrue,
      );
      expect(
        promotedChanged(before, before.copyWith(notificationHistory: true)),
        isTrue,
      );
    });

    test('round-trip through the global bucket', () {
      final g = GlobalPrefs.from(
        const LauncherPrefs(contactsSearch: true, notificationHistory: true),
      );
      final back = GlobalPrefs.fromJson(
        jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>,
      );
      expect(back.contactsSearch, isTrue);
      expect(back.notificationHistory, isTrue);
    });
  });

  group('Recently added', () {
    test('keeps user installs and leaves out system apps', () {
      expect(countsAsRecentlyAdded(_app('com.example.notes')), isTrue);
      expect(countsAsRecentlyAdded(_app('com.android.dialer', system: true)),
          isFalse);
      expect(countsAsRecentlyAdded(_app('com.example.x', installed: 0)),
          isFalse);
    });

    test('leaves out G Launcher itself', () {
      expect(countsAsRecentlyAdded(_app(kApplicationId)), isFalse);
    });
  });

  group('page indicator', () {
    test('defaults to shown', () {
      expect(
        EffectiveTheme.resolve(_spec(), const LauncherPrefs()).workspaceDots,
        isTrue,
      );
      expect(
        EffectiveTheme.resolve(
          _spec(),
          const LauncherPrefs(workspaceDots: false),
        ).workspaceDots,
        isFalse,
      );
    });
  });

  test('every Phase 9 string is in every translated locale', () {
    const keys = [
      'icons.tint',
      'settings.pageIndicator',
      'search.contacts',
      'settings.contactsSearch',
      'settings.notificationHistory',
      'notifHistory.open',
      'notifHistory.clear',
      'notifHistory.empty',
      'desklets.backgroundColour',
    ];
    for (final locale in _translated) {
      final map = jsonDecode(
        File('assets/i18n/$locale.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final k in keys) {
        expect(map[k], isA<String>(), reason: '$locale is missing $k');
        expect((map[k] as String).trim(), isNotEmpty, reason: '$locale $k');
        expect((map[k] as String).contains('—'), isFalse,
            reason: '$locale $k has an em dash');
      }
    }
  });
}
