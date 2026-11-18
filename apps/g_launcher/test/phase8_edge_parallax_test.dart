// Guards Phase 8: the edge handle's settings and gestures, and the wallpaper
// following the desktop pages.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_launcher/data/prefs/launcher_prefs.dart';
import 'package:g_launcher/engine/effective_theme.dart';
import 'package:g_launcher/engine/theme_spec.dart';
import 'package:g_launcher/features/gestures/gesture_actions.dart';
import 'package:g_launcher/system/wallpaper_pan.dart';

const _translated = [
  'ar', 'de', 'en', 'es', 'fa', 'fr', 'hi', 'id', 'it', 'ja', //
  'ko', 'nl', 'pl', 'pt', 'ru', 'tr', 'uk', 'vi', 'zh_CN', 'zh_TW',
];

ThemeSpec _spec({bool? follows}) => ThemeSpec.fromJson(<String, dynamic>{
      'id': 'x',
      'name': 'X',
      'shell': 'gnome',
      'palette': <String, dynamic>{},
      if (follows != null) 'wallpaperFollowsPages': follows,
    });

EffectiveTheme _theme(LauncherPrefs prefs, {bool? follows}) =>
    EffectiveTheme.resolve(_spec(follows: follows), prefs);

void main() {
  group('parallaxOffset', () {
    test('runs from the first page at 0 to the last at 1', () {
      expect(parallaxOffset(0, 4), 0);
      expect(parallaxOffset(3, 4), 1);
      expect(parallaxOffset(1.5, 4), closeTo(0.5, 1e-9));
    });

    test('a single page sits in the middle', () {
      expect(parallaxOffset(0, 1), 0.5);
      expect(parallaxOffset(0, 0), 0.5);
    });

    test('overscroll stays on the wallpaper', () {
      expect(parallaxOffset(-0.3, 3), 0);
      expect(parallaxOffset(2.4, 3), 1);
    });
  });

  group('wallpaperFollowsPages', () {
    test('is off unless the distro authors it', () {
      expect(_theme(const LauncherPrefs()).wallpaperFollowsPages, isFalse);
      expect(
        _theme(const LauncherPrefs(), follows: true).wallpaperFollowsPages,
        isTrue,
      );
    });

    test("the user's choice wins either way", () {
      expect(
        _theme(const LauncherPrefs(wallpaperFollowsPages: false), follows: true)
            .wallpaperFollowsPages,
        isFalse,
      );
      expect(
        _theme(const LauncherPrefs(wallpaperFollowsPages: true))
            .wallpaperFollowsPages,
        isTrue,
      );
    });
  });

  group('edge handle settings', () {
    test('default to off, middle, drawn', () {
      final t = _theme(const LauncherPrefs());
      expect(t.edgeHandleSide, 'off');
      expect(t.edgeHandlePosition, 'middle');
      expect(t.edgeHandleVisible, isTrue);
    });

    test('unknown stored values fall back rather than misplace the handle', () {
      final t = _theme(const LauncherPrefs(
        edgeHandleSide: 'top',
        edgeHandlePosition: 'left',
      ));
      expect(t.edgeHandleSide, 'off');
      expect(t.edgeHandlePosition, 'middle');
    });

    test('survive a prefs round trip', () {
      const p = LauncherPrefs(
        edgeHandleSide: 'right',
        edgeHandlePosition: 'bottom',
        edgeHandleVisible: false,
        wallpaperFollowsPages: true,
      );
      final back = LauncherPrefs.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(back, p);
    });
  });

  group('edge gestures', () {
    test('are the three handle moves, appended after the desktop ones', () {
      final handle = [for (final g in Gesture.values) if (g.onHandle) g];
      expect(handle, [
        Gesture.edgeSwipeIn,
        Gesture.edgeSwipeUp,
        Gesture.edgeSwipeDown,
      ]);
      expect(Gesture.values.indexOf(Gesture.edgeSwipeIn),
          Gesture.values.indexOf(Gesture.twoFingerSwipeDown) + 1);
    });

    test('default to search, quick settings and the shade', () {
      GestureAction act(Gesture g) =>
          resolveGestureBinding(const {}, const {}, g).action;
      expect(act(Gesture.edgeSwipeIn), GestureAction.search);
      expect(act(Gesture.edgeSwipeUp), GestureAction.quickSettings);
      expect(act(Gesture.edgeSwipeDown), GestureAction.notifications);
    });
  });

  test('every translated locale carries the Phase 8 strings', () {
    const keys = [
      'settings.edgeHandle',
      'settings.edgeHandle.side',
      'settings.edgeHandle.left',
      'settings.edgeHandle.right',
      'settings.edgeHandle.position',
      'settings.edgeHandle.top',
      'settings.edgeHandle.middle',
      'settings.edgeHandle.bottom',
      'settings.edgeHandle.show',
      'gestures.edgeSwipeIn',
      'gestures.edgeSwipeUp',
      'gestures.edgeSwipeDown',
      'settings.wallpaperFollowsPages',
    ];
    for (final code in _translated) {
      final map = jsonDecode(File('assets/i18n/$code.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final k in keys) {
        expect((map[k] as String?)?.isNotEmpty, isTrue, reason: '$code $k');
      }
    }
  });
}
