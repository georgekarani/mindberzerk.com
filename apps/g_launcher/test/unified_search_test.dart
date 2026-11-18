import 'package:flutter_test/flutter_test.dart';
import 'package:g_launcher/features/search/unified_search.dart';

/// PHASE 5. The Android settings topics every distro's search offers.
///
/// Labels are passed in, so these run without the i18n bundle: each key reads
/// back as its own last segment, which is close enough to English to test the
/// matching rules.
String _label(String key) => key.split('.').last;

List<String> _actions(String q) =>
    [for (final t in topicsFor(q, _label)) t.action];

void main() {
  test('one letter finds nothing; it would match half the list', () {
    expect(topicsFor('b', _label), isEmpty);
  });

  test('a synonym finds its page', () {
    expect(_actions('gps'), ['android.settings.LOCATION_SOURCE_SETTINGS']);
    expect(_actions('ringtone'), ['android.settings.SOUND_SETTINGS']);
  });

  test('the label matches as well as the synonyms', () {
    expect(_actions('bluetooth').first, 'android.settings.BLUETOOTH_SETTINGS');
  });

  test('a word that starts the label beats one found inside it', () {
    // "net" starts "network" (Wi-Fi's synonym) and sits inside "internet".
    final hits = _actions('net');
    expect(hits, isNotEmpty);
    expect(hits.first, 'android.settings.WIFI_SETTINGS');
  });

  test('never more than three', () {
    expect(topicsFor('se', _label).length, lessThanOrEqualTo(3));
  });

  test('a query nothing names finds nothing', () {
    expect(topicsFor('zzzz', _label), isEmpty);
  });
}
