// Guards Phase 6: the per-distro launch animation and the accent taken from
// the wallpaper, both of which ride in theme.json and the per-theme prefs.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_launcher/data/prefs/launcher_prefs.dart';
import 'package:g_launcher/engine/effective_theme.dart';
import 'package:g_launcher/engine/layout_resolver.dart';
import 'package:g_launcher/engine/theme_spec.dart';
import 'package:g_launcher/system/wallpaper_accent.dart';

const _bar = '#202020';

/// A minimal theme through the real parser, so the fixture cannot drift from
/// how a bundled theme.json decodes.
ThemeSpec _spec({
  Object? launch,
  bool? fromWallpaper,
  List<Map<String, String>>? accents,
}) =>
    ThemeSpec.fromJson(<String, dynamic>{
      'id': 'x',
      'name': 'X',
      'shell': 'gnome',
      'palette': <String, dynamic>{
        'bgTop': '#000000',
        'bgBottom': '#000000',
        'bar': _bar,
        'dock': '#000000',
        'accent': '#E95420',
        'onDark': '#FFFFFF',
      },
      'layout': <String, dynamic>{
        if (launch != null) 'launchAnimation': launch,
      },
      if (fromWallpaper != null) 'accentFromWallpaper': fromWallpaper,
      if (accents != null) 'accents': accents,
    });

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('launchAnimation', () {
    test('a known value parses and resolves', () {
      final r = LayoutResolver.resolve(_spec(launch: 'fade'), const LauncherPrefs());
      expect(r.launchAnimation, 'fade');
    });

    test('absent or unknown falls back to zoom', () {
      expect(
        LayoutResolver.resolve(_spec(), const LauncherPrefs()).launchAnimation,
        LayoutResolver.defaultLaunchAnimation,
      );
      expect(
        LayoutResolver.resolve(_spec(launch: 'warp'), const LauncherPrefs())
            .launchAnimation,
        'zoom',
      );
    });

    test("the user's choice beats the distro's", () {
      final r = LayoutResolver.resolve(
        _spec(launch: 'none'),
        const LauncherPrefs(launchAnimation: 'reveal'),
      );
      expect(r.launchAnimation, 'reveal');
    });
  });

  group('wallpaperAccentFor', () {
    test('no colours gives no accent', () {
      expect(wallpaperAccentFor(const [], const Color(0xFF202020)), isNull);
    });

    test('a grey wallpaper gives no accent', () {
      expect(
        wallpaperAccentFor(const [Color(0xFF808080), Color(0xFF777777)],
            const Color(0xFF202020)),
        isNull,
      );
    });

    test('picks the chromatic colour over a dominant grey', () {
      final c = wallpaperAccentFor(
        const [Color(0xFF7A7A7A), Color(0xFF1E88E5)],
        const Color(0xFF202020),
      )!;
      expect(c.b, greaterThan(c.r));
    });

    test('the result reads on the bar', () {
      const bar = Color(0xFF202020);
      final c = wallpaperAccentFor(const [Color(0xFF1A0F5C)], bar)!;
      expect(_contrast(c, bar), greaterThanOrEqualTo(3.0));
    });
  });

  group('wallpaper accent in the theme', () {
    const colours = [Color(0xFF1E88E5)];

    test('an authored `wallpaper` id is dropped at parse', () {
      final spec = _spec(accents: [
        {'id': 'wallpaper', 'name': 'Fake', 'value': '#00FF00'},
        {'id': 'blue', 'name': 'Blue', 'value': '#0073E5'},
      ]);
      expect(spec.accents.map((a) => a.id), ['blue']);
    });

    test('the swatch is offered first whenever the wallpaper has colour', () {
      final t = EffectiveTheme.resolve(_spec(), const LauncherPrefs(),
          wallpaperColors: colours);
      expect(t.offeredAccents.first.id, wallpaperAccentId);
      // Offered, but not chosen: this distro does not follow the wallpaper.
      expect(t.accentChoice, isNull);
    });

    test('accentFromWallpaper makes it the default', () {
      final t = EffectiveTheme.resolve(_spec(fromWallpaper: true),
          const LauncherPrefs(), wallpaperColors: colours);
      expect(t.accentChoice, wallpaperAccentId);
      expect(t.accent, isNotNull);
      expect(t.palette.accent, t.accent);
    });

    test("the user's pick beats the distro default", () {
      final t = EffectiveTheme.resolve(
        _spec(fromWallpaper: true, accents: [
          {'id': 'red', 'name': 'Red', 'value': '#DA3450'},
        ]),
        const LauncherPrefs(accentId: 'red'),
        wallpaperColors: colours,
      );
      expect(t.accentChoice, 'red');
      expect(t.accent, const Color(0xFFDA3450));
    });

    test('no wallpaper colours keeps the palette accent', () {
      final t = EffectiveTheme.resolve(_spec(fromWallpaper: true),
          const LauncherPrefs());
      expect(t.accent, isNull);
      expect(t.palette.accent, const Color(0xFFE95420));
    });
  });
}
