// Guards Phase 7: clock faces and the large folder desklet.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_launcher/engine/desklet_spec.dart';
import 'package:g_launcher/features/desklets/kinds/clock_faces.dart';
import 'package:g_launcher/features/desklets/kinds/folder_desklet.dart';
import 'package:g_launcher/i18n/i18n.dart';

/// The locales that carry every key; the rest fall back to English.
const _translated = [
  'ar', 'de', 'en', 'es', 'fa', 'fr', 'hi', 'id', 'it', 'ja', //
  'ko', 'nl', 'pl', 'pt', 'ru', 'tr', 'uk', 'vi', 'zh_CN', 'zh_TW',
];

/// Make [code] the strings `tr` reads, the way bootstrap does.
Future<void> _use(String code) async {
  final strings = await Translations.load(code);
  final container = ProviderContainer(
    overrides: [
      i18nProvider.overrideWith(
        () => I18nController(I18nState(selectedCode: code, translations: strings)),
      ),
    ],
  );
  container.read(i18nProvider);
  addTearDown(container.dispose);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClockFace', () {
    test('every face round-trips through its id', () {
      for (final f in ClockFace.values) {
        expect(ClockFace.parse(f.id), f);
      }
    });

    test('an unknown or missing face draws the digital clock', () {
      expect(ClockFace.parse('sundial'), ClockFace.digital);
      expect(ClockFace.parse(null), ClockFace.digital);
    });
  });

  group('fuzzyTime', () {
    test('English rounds to the nearest five minutes', () async {
      await _use('en');
      expect(fuzzyTime(DateTime(2026, 11, 18, 10, 8)), 'Ten past ten');
      expect(fuzzyTime(DateTime(2026, 11, 18, 10, 30)), 'Half past ten');
      expect(fuzzyTime(DateTime(2026, 11, 18, 10, 45)), 'Quarter to eleven');
      expect(fuzzyTime(DateTime(2026, 11, 18, 22, 1)), "Ten o'clock");
    });

    test('rounding up past the hour names the next hour', () async {
      await _use('en');
      expect(fuzzyTime(DateTime(2026, 11, 18, 10, 58)), "Eleven o'clock");
      expect(fuzzyTime(DateTime(2026, 11, 18, 11, 58)), "Twelve o'clock");
      expect(fuzzyTime(DateTime(2026, 11, 18, 23, 58)), "Twelve o'clock");
      expect(fuzzyTime(DateTime(2026, 11, 18, 12, 40)), 'Twenty to one');
    });

    test('a locale can name the next hour at half past', () async {
      await _use('de');
      expect(fuzzyTime(DateTime(2026, 11, 18, 10, 30)), 'Halb elf');
      await _use('nl');
      expect(fuzzyTime(DateTime(2026, 11, 18, 10, 30)), 'Half elf');
    });
  });

  test('every translated locale carries the Phase 7 strings', () {
    final keys = [
      'desklet_spec.folder',
      'desklets.face',
      for (final f in ClockFace.values) f.labelKey,
      'desklets.folder.recent',
      'desklets.folder.frequent',
      'desklets.folder.show',
      'desklets.folder.size',
      'desklets.folder.empty',
      'desklets.folder.missing',
      for (var i = 1; i <= 12; i++) 'clock.fuzzy.h$i',
      for (var i = 0; i < 12; i++) 'clock.fuzzy.t$i',
    ];
    for (final code in _translated) {
      final map = jsonDecode(File('assets/i18n/$code.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final k in keys) {
        expect((map[k] as String?)?.isNotEmpty, isTrue, reason: '$code $k');
      }
      // Each template names an hour, or the phrase would say no time at all.
      for (var i = 0; i < 12; i++) {
        final t = map['clock.fuzzy.t$i'] as String;
        expect(t.contains('{h}') || t.contains('{n}'), isTrue,
            reason: '$code clock.fuzzy.t$i');
      }
    }
  });

  group('large folder', () {
    test('is a registered kind that defaults to the newest apps in 2x2', () {
      expect(DeskletKinds.byId('folder'), DeskletKinds.folder);
      expect(DeskletKinds.folder.paneOnly, isFalse);
      expect(DeskletKinds.folder.read<String>(const {}, 'source', ''), 'recent');
      expect(DeskletKinds.folder.read<num>(const {}, 'grid', 0), 2);
    });

    test('an unknown source falls back to recently added', () {
      expect(FolderSource.parse('folder'), FolderSource.folder);
      expect(FolderSource.parse('frequent'), FolderSource.frequent);
      expect(FolderSource.parse('starred'), FolderSource.recent);
      expect(FolderSource.parse(null), FolderSource.recent);
    });
  });
}
