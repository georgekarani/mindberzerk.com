import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../../engine/desklet_skin.dart';
import '../../../engine/effective_theme.dart';
import '../../../engine/theme_spec.dart' show parseColor;

/// The faces a clock desklet can wear. PHASE 7.
///
/// Each one is a real Linux desktop's own clock, not an invention: Plasma ships
/// Analog, Fuzzy and Binary clock widgets, and `tty-clock` is what a terminal
/// user runs. [digital] is the clock as it was before faces existed, drawn by
/// the four surfaces in clock_desklet.dart and untouched by this file.
///
/// ─── STORED AS A STRING, PARSED ON READ ─────────────────────────────────────
///
/// The value lives in `Desklet.config['face']` or a theme's
/// `desklets.skins.clock.face`, both of which can come from a CDN pack or a
/// newer build. An unknown value falls back to [digital], so a face this build
/// has never heard of draws the plain clock rather than nothing.
enum ClockFace {
  digital('digital'),
  analog('analog'),
  fuzzy('fuzzy'),
  binary('binary'),
  digits('digits');

  const ClockFace(this.id);

  final String id;

  static ClockFace parse(String? raw) {
    for (final f in values) {
      if (f.id == raw) return f;
    }
    return digital;
  }

  /// The i18n key of this face's name in the widget settings.
  String get labelKey => 'desklets.face.$id';

  /// What the terminal surface prints as the command that drew this face.
  /// Real programs, so the line reads as something you could have typed.
  String get command => switch (this) {
        ClockFace.digital => 'date',
        ClockFace.analog => 'xclock',
        ClockFace.fuzzy => 'fuzzyclock',
        ClockFace.binary => 'binclock',
        ClockFace.digits => 'tty-clock -c',
      };
}

/// The phrase a fuzzy clock shows for [t], to the nearest five minutes.
///
/// ─── TWO PLACEHOLDERS, BECAUSE LANGUAGES DISAGREE ABOUT THE HOUR ────────────
///
/// English says "half past ten" and German says "halb elf": the same moment,
/// named after different hours. So every template is offered both the current
/// hour `{h}` and the next one `{n}`, and each locale's string picks whichever
/// its language uses. The code never decides which hour a phrase is about.
String fuzzyTime(DateTime t) {
  final step = (t.minute + 2) ~/ 5; // 0..12, nearest five minutes
  final hour = step == 12 ? t.hour + 1 : t.hour;
  final slot = step % 12;
  String word(int h24) => tr('clock.fuzzy.h${(h24 % 12 == 0) ? 12 : h24 % 12}');
  final phrase = tr('clock.fuzzy.t$slot', {
    'h': word(hour),
    'n': word(hour + 1),
  });
  return phrase.isEmpty
      ? phrase
      : phrase[0].toUpperCase() + phrase.substring(1);
}

/// One face, wrapped in its surface's container. Every face but [digital]
/// draws through here, so a new face needs a painter and nothing else.
class ClockFaceView extends StatelessWidget {
  const ClockFaceView({
    super.key,
    required this.theme,
    required this.skin,
    required this.face,
    required this.now,
    required this.twelve,
    required this.showDate,
    required this.date,
  });

  final EffectiveTheme theme;
  final DeskletSkin skin;
  final ClockFace face;
  final DateTime now;
  final bool twelve;
  final bool showDate;
  final String date;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final accent = parseColor(skin.text('accentHex', '')) ?? p.accent;
    final ink = skin.accent ? accent : p.onDark;
    final family = skin.font == DeskletFont.mono
        ? theme.typography.mono
        : theme.typography.display;
    final terminal = skin.surface == DeskletSurface.terminal;
    final bare = skin.surface == DeskletSurface.bare;

    // Bare text and strokes have to survive a light wallpaper. The same
    // shadow the digital clock uses, so a face sits beside one without
    // looking lighter.
    final shadows = bare
        ? <Shadow>[
            Shadow(
              color: p.bgBottom.withValues(alpha: 0.55),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ]
        : const <Shadow>[];

    final graphic = switch (face) {
      ClockFace.analog => _Analog(
          now: now,
          ink: ink,
          accent: accent,
          dial: terminal || bare ? null : p.bgBottom.withValues(alpha: 0.55),
          shadow: bare ? p.bgBottom.withValues(alpha: 0.45) : null,
        ),
      ClockFace.binary => _Binary(
          now: now,
          twelve: twelve,
          on: accent,
          off: p.onDark.withValues(alpha: 0.16),
        ),
      ClockFace.digits => _Digits(now: now, twelve: twelve, ink: accent),
      ClockFace.fuzzy || ClockFace.digital => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            fuzzyTime(now),
            textAlign: bare ? TextAlign.start : TextAlign.center,
            style: TextStyle(
              fontFamily: terminal ? theme.typography.mono : family,
              fontSize: skin.num_('fuzzySize', 26),
              fontWeight: FontWeight.w600,
              height: 1.15,
              color: ink,
              shadows: shadows,
            ),
          ),
        ),
    };

    final dateText = Text(
      date,
      style: TextStyle(
        fontFamily: terminal ? theme.typography.mono : family,
        fontSize: skin.num_('dateSize', 12),
        color: p.onDark.withValues(alpha: 0.72),
        shadows: shadows,
      ),
    );

    // The terminal prints the command that drew the face, as its digital
    // clock prints `date`: a scrollback, not a widget.
    if (terminal) {
      final mono = theme.typography.mono;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontFamily: mono,
                fontSize: skin.num_('timeSize', 13),
                height: 1.6,
              ),
              children: [
                TextSpan(
                  text: '~ ❯ ',
                  style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: face.command,
                  style: TextStyle(color: p.onDark.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          graphic,
          if (showDate) ...[const SizedBox(height: 6), dateText],
        ],
      );
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          bare ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        graphic,
        if (showDate) ...[const SizedBox(height: 8), dateText],
      ],
    );

    return switch (skin.surface) {
      DeskletSurface.bare || DeskletSurface.terminal => column,
      DeskletSurface.card => DecoratedBox(
          decoration: BoxDecoration(
            color: skin.fill(p.bar, 0.72),
            borderRadius: BorderRadius.circular(skin.num_('radius', 10)),
            border: Border.all(color: p.onDark.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Center(child: column),
          ),
        ),
      // A waybar module: flat, one accent edge marking it as a module.
      DeskletSurface.panel => DecoratedBox(
          decoration: BoxDecoration(
            color: skin.fill(p.bar, 0.9),
            borderRadius: BorderRadius.circular(skin.num_('radius', 4)),
            border: Border(left: BorderSide(color: p.accent, width: 2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Center(child: column),
          ),
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Analog: Plasma's Analog Clock, and the iOS clock.
// ─────────────────────────────────────────────────────────────────────────────

class _Analog extends StatelessWidget {
  const _Analog({
    required this.now,
    required this.ink,
    required this.accent,
    required this.dial,
    required this.shadow,
  });

  final DateTime now;
  final Color ink;
  final Color accent;

  /// The filled dial, or null for hands and ticks straight on the wallpaper.
  final Color? dial;

  /// A soft halo under the strokes on a bare surface, or null.
  final Color? shadow;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        // Sized by a box rather than CustomPaint.size, so it reports an
        // intrinsic width and a card hugging its content measures it.
        child: SizedBox.fromSize(
          size: const Size.square(132),
          child: CustomPaint(
            painter: _AnalogPainter(
              hour: now.hour % 12 + now.minute / 60,
              minute: now.minute.toDouble(),
              ink: ink,
              accent: accent,
              dial: dial,
              shadow: shadow,
            ),
          ),
        ),
      );
}

class _AnalogPainter extends CustomPainter {
  _AnalogPainter({
    required this.hour,
    required this.minute,
    required this.ink,
    required this.accent,
    required this.dial,
    required this.shadow,
  });

  final double hour;
  final double minute;
  final Color ink;
  final Color accent;
  final Color? dial;
  final Color? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    if (dial != null) {
      canvas.drawCircle(c, r - 1, Paint()..color = dial!);
    }
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ink.withValues(alpha: 0.35),
    );

    // Hour ticks: the quarters long and heavy, the rest short.
    for (var i = 0; i < 12; i++) {
      final a = i * 30 * math.pi / 180;
      final quarter = i % 3 == 0;
      final outer = r - 6;
      final inner = outer - (quarter ? 11 : 6);
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        c + dir * inner,
        c + dir * outer,
        Paint()
          ..strokeWidth = quarter ? 3 : 1.6
          ..strokeCap = StrokeCap.round
          ..color = ink.withValues(alpha: quarter ? 0.9 : 0.55),
      );
    }

    void hand(double turns, double length, double width, Color colour) {
      final a = turns * 2 * math.pi;
      final tip = c + Offset(math.sin(a), -math.cos(a)) * length;
      if (shadow != null) {
        canvas.drawLine(
          c + const Offset(0, 1.5),
          tip + const Offset(0, 1.5),
          Paint()
            ..strokeWidth = width + 2
            ..strokeCap = StrokeCap.round
            ..color = shadow!
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawLine(
        c,
        tip,
        Paint()
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = colour,
      );
    }

    hand(hour / 12, r * 0.5, 5, ink);
    hand(minute / 60, r * 0.74, 3.5, ink);
    canvas.drawCircle(c, 4.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_AnalogPainter old) =>
      old.hour != hour ||
      old.minute != minute ||
      old.ink != ink ||
      old.accent != accent ||
      old.dial != dial ||
      old.shadow != shadow;
}

// ─────────────────────────────────────────────────────────────────────────────
// Binary: Plasma's Binary Clock. One column per digit of HH:MM, read upward.
// ─────────────────────────────────────────────────────────────────────────────

class _Binary extends StatelessWidget {
  const _Binary({
    required this.now,
    required this.twelve,
    required this.on,
    required this.off,
  });

  final DateTime now;
  final bool twelve;
  final Color on;
  final Color off;

  static const _dot = 18.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final h = twelve ? (now.hour % 12 == 0 ? 12 : now.hour % 12) : now.hour;
    final digits = [h ~/ 10, h % 10, now.minute ~/ 10, now.minute % 10];
    const side = 4 * _dot + 3 * _gap;
    return Semantics(
      label: '$h:${now.minute.toString().padLeft(2, '0')}',
      child: SizedBox.fromSize(
        size: const Size(side + _gap, side),
        child: CustomPaint(
          painter: _BinaryPainter(digits: digits, on: on, off: off),
        ),
      ),
    );
  }
}

class _BinaryPainter extends CustomPainter {
  _BinaryPainter({required this.digits, required this.on, required this.off});

  final List<int> digits;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    const dot = _Binary._dot;
    const gap = _Binary._gap;
    for (var col = 0; col < digits.length; col++) {
      // A wider gap between the hours and the minutes, where the colon sits.
      final x = col * (dot + gap) + (col >= 2 ? gap : 0) + dot / 2;
      for (var bit = 0; bit < 4; bit++) {
        // Row 0 is the top, worth 8; row 3 the bottom, worth 1.
        final lit = (digits[col] >> (3 - bit)) & 1 == 1;
        canvas.drawCircle(
          Offset(x, bit * (dot + gap) + dot / 2),
          dot / 2,
          Paint()..color = lit ? on : off,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BinaryPainter old) =>
      old.on != on || old.off != off || !_same(old.digits, digits);

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return a.length == b.length;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Big digits: tty-clock. Blocks on a 3x5 grid, painted rather than typed.
// ─────────────────────────────────────────────────────────────────────────────

/// Painted, not set in a font. The block character is in most mono fonts but
/// not all of them, and a pack can name any family; a missing glyph would draw
/// tofu where the time should be.
class _Digits extends StatelessWidget {
  const _Digits({required this.now, required this.twelve, required this.ink});

  final DateTime now;
  final bool twelve;
  final Color ink;

  static const _cell = 8.0;

  @override
  Widget build(BuildContext context) {
    final h = twelve ? (now.hour % 12 == 0 ? 12 : now.hour % 12) : now.hour;
    final text =
        '${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final columns = _DigitsPainter.columnsFor(text);
    return Semantics(
      label: text,
      child: SizedBox.fromSize(
        size: Size(columns * _cell, 5 * _cell),
        child: CustomPaint(
          painter: _DigitsPainter(text: text, ink: ink),
        ),
      ),
    );
  }
}

class _DigitsPainter extends CustomPainter {
  _DigitsPainter({required this.text, required this.ink});

  final String text;
  final Color ink;

  /// Each glyph is five rows of three bits, left to right. The colon is one
  /// column wide.
  static const _glyphs = <String, List<String>>{
    '0': ['111', '101', '101', '101', '111'],
    '1': ['010', '110', '010', '010', '111'],
    '2': ['111', '001', '111', '100', '111'],
    '3': ['111', '001', '111', '001', '111'],
    '4': ['101', '101', '111', '001', '001'],
    '5': ['111', '100', '111', '001', '111'],
    '6': ['111', '100', '111', '101', '111'],
    '7': ['111', '001', '001', '001', '001'],
    '8': ['111', '101', '111', '101', '111'],
    '9': ['111', '101', '111', '001', '111'],
    ':': ['0', '1', '0', '1', '0'],
  };

  /// Width in cells: each glyph plus one blank column after all but the last.
  static int columnsFor(String text) {
    var w = 0;
    for (var i = 0; i < text.length; i++) {
      w += (_glyphs[text[i]]?.first.length ?? 0) + (i == text.length - 1 ? 0 : 1);
    }
    return w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const cell = _Digits._cell;
    final paint = Paint()..color = ink;
    var x = 0.0;
    for (var i = 0; i < text.length; i++) {
      final g = _glyphs[text[i]];
      if (g == null) continue;
      for (var row = 0; row < g.length; row++) {
        for (var col = 0; col < g[row].length; col++) {
          if (g[row][col] != '1') continue;
          // A hair of space between blocks, as a terminal's cells have.
          canvas.drawRect(
            Rect.fromLTWH(
              x + col * cell,
              row * cell,
              cell - 1,
              cell - 1,
            ),
            paint,
          );
        }
      }
      x += (g.first.length + 1) * cell;
    }
  }

  @override
  bool shouldRepaint(_DigitsPainter old) => old.text != text || old.ink != ink;
}
