import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_launcher/engine/splash_spec.dart';

void main() {
  group('SplashSpec.fromJson', () {
    test('an old block parses exactly as before', () {
      final s = SplashSpec.fromJson({'style': 'bar', 'durationMs': 1200})!;
      expect(s.style, SplashStyle.bar);
      expect(s.durationMs, 1200);
      expect(s.background, isNull);
      expect(s.indicator, isNull);
      expect(s.wordmark, isNull);
      expect(s.console, isNull);
      expect(s.logoSize, SplashSpec.defaultLogoSize);
    });

    test('graphical fields parse', () {
      final s = SplashSpec.fromJson({
        'style': 'dots',
        'background': {
          'radial': ['#3B0F2C', '#FF2C001E', 'nonsense'],
          'center': [0.5, 0.4],
        },
        'decor': 'grid',
        'ring': {'kind': 'conic', 'colors': ['#FF0F7B', '#F89B29']},
        'logoGlow': '#7387CF3E',
        'indicator': {'kind': 'dots', 'count': 3},
        'caption': {'text': 'KALI LINUX', 'spacing': 10, 'mono': true},
        'wordmark': {'text': 'ubuntu', 'suffix': '24.04', 'weight': 320},
      })!;
      expect(s.background!.fill, SplashFill.radial);
      expect(s.background!.colors, hasLength(2));
      expect(s.background!.center.x, closeTo(0, 1e-9));
      expect(s.background!.center.y, closeTo(-0.2, 1e-9));
      expect(s.decor!.kind, SplashDecorKind.grid);
      expect(s.ring!.kind, SplashRingKind.conic);
      expect(s.logoGlow, const Color(0x7387CF3E));
      expect(s.indicator!.count, 3);
      // Dots default to a dot-sized thickness, not a bar's.
      expect(s.indicator!.thickness, 7);
      expect(s.caption!.mono, isTrue);
      expect(s.wordmark!.suffix, '24.04');
      expect(s.wordmark!.weight, 300);
    });

    test('hostile numbers are clamped', () {
      final s = SplashSpec.fromJson({
        'durationMs': 9000,
        'logoSize': 4000,
        'indicator': {'kind': 'dots', 'count': 99},
        'ring': {'size': 1},
      })!;
      expect(s.durationMs, SplashSpec.maxDurationMs);
      expect(s.logoSize, 160);
      expect(s.indicator!.count, 8);
      expect(s.ring!.size, 96);
    });

    test('unknown kinds and empty blocks are dropped, not guessed', () {
      final s = SplashSpec.fromJson({
        'background': {'pattern': 'plaid'},
        'decor': 'confetti',
        'indicator': {'kind': 'laser'},
        'wordmark': '',
        'console': {'lines': []},
      })!;
      expect(s.background, isNull);
      expect(s.decor, isNull);
      expect(s.indicator, isNull);
      expect(s.wordmark, isNull);
      expect(s.console, isNull);
    });

    test('console lines take strings and heads', () {
      final s = SplashSpec.fromJson({
        'style': 'text',
        'console': {
          'lines': [
            {'head': 'Arch Linux', 'text': ' 6.11 (tty1)'},
            'Password:',
          ],
        },
      })!;
      expect(s.style, SplashStyle.text);
      expect(s.console!.lines.first.head, 'Arch Linux');
      expect(s.console!.lines.last.text, 'Password:');
      expect(s.console!.cursor, isTrue);
    });

    test('equal blocks are equal', () {
      Map<String, dynamic> j() => {
            'style': 'bar',
            'indicator': {'kind': 'bar', 'width': 150, 'thickness': 4},
            'wordmark': {'text': 'manjaro', 'spacing': 2},
          };
      expect(SplashSpec.fromJson(j()), SplashSpec.fromJson(j()));
    });
  });
}
