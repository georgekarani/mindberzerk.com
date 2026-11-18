import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart' show Alignment;

import 'theme_spec.dart' show ShellKind, parseColor;

/// The quick boot splash, expressed as data — [BootSpec]'s smaller sibling.
///
/// Two different things happen between "you picked a theme" and "here is your
/// desktop", and they are not the same feature:
///
///   * [BootSpec] is the VERBOSE boot: the scrolling `[  OK  ]` systemd spew,
///     six seconds of theatre, opt-in per theme because most people want their
///     phone, not a performance.
///   * [SplashSpec] is what everyone else gets: a logo, under a second, the
///     thing a real distro shows while it starts a session. Plymouth on Ubuntu,
///     the KDE progress bar, Arch's bare text.
///
/// Same rules as the rest of the theme layer: data not code, forward-compatible
/// parse, and a sane per-shell default so a theme that ships no `splash` block
/// still comes up looking like its family.
///
/// ─── THE GRAPHICAL FIELDS ARE ADDITIVE ──────────────────────────────────────
///
/// `style` stays the one field every app version reads. Everything else
/// (`background`, `decor`, `ring`, `logoGlow`, `indicator`, `caption`,
/// `wordmark`, `console`) is optional, and an app that predates a field simply
/// does not draw it. A theme therefore keeps a sensible `style` beside its
/// graphical fields, so an older install still shows the right family of
/// splash rather than a generic one. Example:
///
/// ```json
/// "splash": {
///   "style": "dots",
///   "durationMs": 1100,
///   "background": { "radial": ["#FF3B0F2C", "#FF2C001E", "#FF12000C"], "center": [0.5, 0.4] },
///   "indicator": { "kind": "dots", "count": 5, "color": "#FFFFFFFF" },
///   "wordmark": { "text": "ubuntu", "suffix": "24.04", "size": 22, "weight": 300 }
/// }
/// ```
///
/// Colours are `#RRGGBB` or `#AARRGGBB`, the same as everywhere else in a
/// theme (see [parseColor]).
///
/// Deliberately NOT played on every home press. A launcher that flashes a logo
/// each time you hit HOME is a launcher people uninstall in a week — see
/// home_screen, which plays this on cold start and on a theme SWITCH only.
enum SplashStyle {
  /// Ubuntu/Plymouth: the logo, with a row of pulsing dots beneath it.
  dots,

  /// KDE: the logo over a thin determinate progress bar.
  bar,

  /// A quiet circular spinner under the logo. The generic desktop answer.
  spinner,

  /// Arch and friends: no logo, just the distro name in mono. A tiling WM does
  /// not have a splash screen, and pretending otherwise is less authentic than
  /// showing nothing pretty.
  text,

  /// The logo over a thin bar, like `bar`, and then, the FIRST time the
  /// distro is applied, its words written out by hand before the desktop
  /// arrives (see `HelloLettering`). Every later boot is logo and bar only.
  /// Pocket.
  hello,

  /// No splash at all. The terminal shell boots INTO a terminal; a graphical
  /// splash in front of it would be a lie about what this theme is.
  none;

  static SplashStyle parse(String? raw) => switch (raw) {
        'dots' => SplashStyle.dots,
        'bar' => SplashStyle.bar,
        'spinner' => SplashStyle.spinner,
        'text' => SplashStyle.text,
        'hello' => SplashStyle.hello,
        'none' => SplashStyle.none,
        // Unknown style from a newer CDN theme degrades to the safe middle
        // rather than throwing. Same contract as BootLineKind.parse.
        _ => SplashStyle.spinner,
      };
}

/// What paints behind everything else.
enum SplashFill { solid, radial, linear }

/// The splash's ground: one colour, or a radial or linear gradient.
///
/// Null on [SplashSpec] means "the distro's dark base", the old behaviour.
class SplashBackground {
  const SplashBackground({
    required this.fill,
    required this.colors,
    this.center = Alignment.center,
    this.angle = 180,
  });

  final SplashFill fill;

  /// At least one colour. Gradients spread them evenly from first to last.
  final List<Color> colors;

  /// Radial only: where the glow sits, as an [Alignment].
  final Alignment center;

  /// Linear only: CSS degrees, so 180 runs top to bottom.
  final double angle;

  /// `{"color": c}`, `{"radial": [c...], "center": [x, y]}` with x and y in
  /// 0..1, or `{"linear": [c...], "angle": deg}`. Anything else is null.
  static SplashBackground? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final solid = parseColor(raw['color'] as String?);
    if (solid != null) {
      return SplashBackground(fill: SplashFill.solid, colors: [solid]);
    }
    final radial = _colors(raw['radial']);
    if (radial.isNotEmpty) {
      final c = raw['center'];
      final center = c is List && c.length == 2 && c[0] is num && c[1] is num
          ? Alignment(
              (_unit(c[0] as num) * 2) - 1,
              (_unit(c[1] as num) * 2) - 1,
            )
          : Alignment.center;
      return SplashBackground(
        fill: SplashFill.radial,
        colors: radial,
        center: center,
      );
    }
    final linear = _colors(raw['linear']);
    if (linear.isNotEmpty) {
      return SplashBackground(
        fill: SplashFill.linear,
        colors: linear,
        angle: (raw['angle'] as num?)?.toDouble() ?? 180,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SplashBackground &&
      other.fill == fill &&
      listEquals(other.colors, colors) &&
      other.center == center &&
      other.angle == angle;

  @override
  int get hashCode => Object.hash(fill, Object.hashAll(colors), center, angle);
}

/// A faint pattern laid over the background.
enum SplashDecorKind {
  /// A fine square grid. Kali.
  grid,

  /// A scatter of small stars. EndeavourOS.
  stars;

  static SplashDecorKind? parse(String? raw) => switch (raw) {
        'grid' => SplashDecorKind.grid,
        'stars' => SplashDecorKind.stars,
        _ => null,
      };
}

class SplashDecor {
  const SplashDecor({required this.kind, this.color});

  final SplashDecorKind kind;

  /// Null uses a faint wash of onDark.
  final Color? color;

  /// `"grid"`, or `{"kind": "grid", "color": c}`.
  static SplashDecor? fromJson(Object? raw) {
    if (raw is String) {
      final kind = SplashDecorKind.parse(raw);
      return kind == null ? null : SplashDecor(kind: kind);
    }
    if (raw is! Map) return null;
    final kind = SplashDecorKind.parse(raw['kind'] as String?);
    if (kind == null) return null;
    return SplashDecor(kind: kind, color: parseColor(raw['color'] as String?));
  }

  @override
  bool operator ==(Object other) =>
      other is SplashDecor && other.kind == kind && other.color == color;

  @override
  int get hashCode => Object.hash(kind, color);
}

/// A turning ring around the logo.
enum SplashRingKind {
  /// A single bright arc over a faint track. Zorin.
  arc,

  /// A full ring swept through several colours. Garuda.
  conic;

  static SplashRingKind parse(String? raw) =>
      raw == 'conic' ? SplashRingKind.conic : SplashRingKind.arc;
}

class SplashRing {
  const SplashRing({
    required this.kind,
    required this.colors,
    this.size = 160,
    this.thickness = 2,
  });

  final SplashRingKind kind;

  /// The arc's colour, or the sweep's stops. Empty uses the accent.
  final List<Color> colors;

  /// Outer diameter in logical pixels, clamped to a sane range.
  final double size;
  final double thickness;

  static SplashRing? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return SplashRing(
      kind: SplashRingKind.parse(raw['kind'] as String?),
      colors: _colors(raw['colors']),
      size: _clamp(raw['size'], 160, 96, 240),
      thickness: _clamp(raw['thickness'], 2, 1, 8),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SplashRing &&
      other.kind == kind &&
      listEquals(other.colors, colors) &&
      other.size == size &&
      other.thickness == thickness;

  @override
  int get hashCode =>
      Object.hash(kind, Object.hashAll(colors), size, thickness);
}

/// What sits under the logo while the splash runs.
enum SplashIndicatorKind {
  dots,

  /// A determinate bar. With a large `thickness` it reads as Pop!_OS's pill.
  bar,
  spinner,
  none;

  static SplashIndicatorKind? parse(String? raw) => switch (raw) {
        'dots' => SplashIndicatorKind.dots,
        'bar' => SplashIndicatorKind.bar,
        'spinner' => SplashIndicatorKind.spinner,
        'none' => SplashIndicatorKind.none,
        _ => null,
      };
}

class SplashIndicator {
  const SplashIndicator({
    required this.kind,
    this.count = 5,
    this.color,
    this.track,
    this.width = 180,
    this.thickness = 3,
    this.size = 22,
  });

  final SplashIndicatorKind kind;

  /// Dots only.
  final int count;

  /// Null keeps the style's own choice: onDark for dots, the accent otherwise.
  final Color? color;

  /// Bar and spinner track. Null is a faint wash of onDark.
  final Color? track;

  /// Bar length.
  final double width;

  /// Bar height, spinner stroke, or dot diameter.
  final double thickness;

  /// Spinner diameter.
  final double size;

  static SplashIndicator? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = SplashIndicatorKind.parse(raw['kind'] as String?);
    if (kind == null) return null;
    return SplashIndicator(
      kind: kind,
      count: _clamp(raw['count'], 5, 1, 8).round(),
      color: parseColor(raw['color'] as String?),
      track: parseColor(raw['track'] as String?),
      width: _clamp(raw['width'], 180, 60, 260),
      // One field, three meanings, so each kind gets its own default.
      thickness: _clamp(
        raw['thickness'],
        switch (kind) {
          SplashIndicatorKind.dots => 7.0,
          SplashIndicatorKind.spinner => 2.0,
          _ => 3.0,
        },
        1,
        10,
      ),
      size: _clamp(raw['size'], 22, 14, 56),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SplashIndicator &&
      other.kind == kind &&
      other.count == count &&
      other.color == color &&
      other.track == track &&
      other.width == width &&
      other.thickness == thickness &&
      other.size == size;

  @override
  int get hashCode =>
      Object.hash(kind, count, color, track, width, thickness, size);
}

/// A line of type: the caption under the logo or the wordmark at the foot.
///
/// The words are the distro's own name, so they are not translated. They still
/// wrap rather than clip, because a theme author can write anything here.
class SplashText {
  const SplashText({
    required this.text,
    this.suffix,
    this.size = 18,
    this.weight = 300,
    this.spacing = 0,
    this.color,
    this.mono = false,
  });

  final String text;

  /// Small raised text after [text], such as a version number.
  final String? suffix;
  final double size;

  /// CSS-style 100..900.
  final int weight;

  /// Letter spacing in logical pixels.
  final double spacing;

  /// Null is onDark.
  final Color? color;

  /// Set in the theme's mono font rather than its display font.
  final bool mono;

  static SplashText? fromJson(Object? raw) {
    if (raw is String) return raw.isEmpty ? null : SplashText(text: raw);
    if (raw is! Map) return null;
    final text = raw['text'] as String?;
    if (text == null || text.isEmpty) return null;
    final suffix = raw['suffix'] as String?;
    return SplashText(
      text: text,
      suffix: (suffix == null || suffix.isEmpty) ? null : suffix,
      size: _clamp(raw['size'], 18, 10, 40),
      weight: (_clamp(raw['weight'], 300, 100, 900) / 100).round() * 100,
      spacing: _clamp(raw['spacing'], 0, -2, 14),
      color: parseColor(raw['color'] as String?),
      mono: raw['mono'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SplashText &&
      other.text == text &&
      other.suffix == suffix &&
      other.size == size &&
      other.weight == weight &&
      other.spacing == spacing &&
      other.color == color &&
      other.mono == mono;

  @override
  int get hashCode =>
      Object.hash(text, suffix, size, weight, spacing, color, mono);
}

/// One line of a text-console splash.
class SplashConsoleLine {
  const SplashConsoleLine({required this.text, this.head});

  /// Printed in the accent, bold, before [text].
  final String? head;

  /// `{now}` is replaced with the current time, `Sun Nov 15 14:06`.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SplashConsoleLine && other.text == text && other.head == head;

  @override
  int get hashCode => Object.hash(text, head);
}

/// A tty login typed out line by line, ending on a blinking cursor. Arch.
///
/// Kept beside `"style": "text"`, so an app that predates it shows the old
/// bare-name splash instead of a generic spinner.
class SplashConsole {
  const SplashConsole({required this.lines, this.cursor = true});

  final List<SplashConsoleLine> lines;
  final bool cursor;

  /// `{"lines": ["plain", {"head": "Arch Linux", "text": " (tty1)"}], "cursor": true}`
  static SplashConsole? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lines = <SplashConsoleLine>[];
    final list = raw['lines'];
    if (list is List) {
      for (final e in list.take(12)) {
        if (e is String) {
          lines.add(SplashConsoleLine(text: e));
        } else if (e is Map) {
          lines.add(SplashConsoleLine(
            text: (e['text'] as String?) ?? '',
            head: e['head'] as String?,
          ));
        }
      }
    }
    if (lines.isEmpty) return null;
    return SplashConsole(lines: lines, cursor: raw['cursor'] != false);
  }

  @override
  bool operator ==(Object other) =>
      other is SplashConsole &&
      listEquals(other.lines, lines) &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(Object.hashAll(lines), cursor);
}

class SplashSpec {
  const SplashSpec({
    this.style = SplashStyle.spinner,
    this.logo,
    int durationMs = defaultDurationMs,
    this.background,
    this.decor,
    this.ring,
    this.logoGlow,
    this.logoSize = defaultLogoSize,
    this.gap = defaultGap,
    this.indicator,
    this.caption,
    this.wordmark,
    this.console,
  }) : durationMs = durationMs < minDurationMs
            ? minDurationMs
            : (durationMs > maxDurationMs ? maxDurationMs : durationMs);

  /// Long enough to read as intentional, short enough not to be a tax on every
  /// theme switch. The plan's 800ms–1.5s, enforced rather than documented:
  /// a CDN theme cannot decide your desktop takes eight seconds to appear.
  static const int minDurationMs = 400;
  static const int defaultDurationMs = 900;
  static const int maxDurationMs = 1500;

  static const double defaultLogoSize = 96;
  static const double defaultGap = 34;

  final SplashStyle style;

  /// Splash artwork. Null falls back to the theme's own [ThemeLogo] (dark
  /// variant, since a splash paints on the distro's dark base), and then to the
  /// style's logo-less rendering. A theme therefore gets a correct splash
  /// without authoring anything.
  final String? logo;

  /// Clamped by the constructor to [minDurationMs]..[maxDurationMs].
  final int durationMs;

  /// Null paints the distro's dark base.
  final SplashBackground? background;
  final SplashDecor? decor;

  /// A turning ring around the logo.
  final SplashRing? ring;

  /// A soft glow that breathes behind the logo.
  final Color? logoGlow;
  final double logoSize;

  /// Space between the logo (or its caption) and the indicator.
  final double gap;

  /// Null derives the indicator from [style], as before.
  final SplashIndicator? indicator;

  /// Tracked text directly under the logo.
  final SplashText? caption;

  /// The distro's name at the foot of the screen.
  final SplashText? wordmark;

  /// Replaces the logo layout with a typed tty login.
  final SplashConsole? console;

  /// Forward-compatible parse. A theme with no `splash` block, or a malformed
  /// one, yields null and the caller falls back to [defaultForShell].
  static SplashSpec? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return SplashSpec(
      style: SplashStyle.parse(j['style'] as String?),
      logo: j['logo'] as String?,
      durationMs: (j['durationMs'] as num?)?.toInt() ?? defaultDurationMs,
      background: SplashBackground.fromJson(j['background']),
      decor: SplashDecor.fromJson(j['decor']),
      ring: SplashRing.fromJson(j['ring']),
      logoGlow: parseColor(j['logoGlow'] as String?),
      logoSize: _clamp(j['logoSize'], defaultLogoSize, 48, 160),
      gap: _clamp(j['gap'], defaultGap, 8, 200),
      indicator: SplashIndicator.fromJson(j['indicator']),
      caption: SplashText.fromJson(j['caption']),
      wordmark: SplashText.fromJson(j['wordmark']),
      console: SplashConsole.fromJson(j['console']),
    );
  }

  /// Built-in splashes keyed by SHELL, not by distro id — the same rule
  /// [BootSpec.defaultForShell] follows, and for the same reason: keying on
  /// `theme.id == 'fedora'` is exactly the trap ThemeSpec exists to avoid.
  static SplashSpec defaultForShell(ShellKind shell) => switch (shell) {
        // Plymouth: logo, pulsing dots underneath.
        ShellKind.gnome => const SplashSpec(style: SplashStyle.dots),
        // KDE's splash is a logo over a progress bar.
        ShellKind.plasma => const SplashSpec(style: SplashStyle.bar),
        // A tiling WM has no splash. Bare text is the honest version.
        ShellKind.tiling =>
          const SplashSpec(style: SplashStyle.text, durationMs: 600),
        // The terminal boots into a terminal.
        ShellKind.tui => const SplashSpec(style: SplashStyle.none),
        // A Mac boots to a mark over a thin determinate progress bar — the same
        // shape as KDE's, which is why `bar` already covers it. The MARK itself
        // is the theme's own logo, and the bundled Aqua theme deliberately
        // ships none (see its theme.json), so this renders logo-less.
        ShellKind.aqua => const SplashSpec(style: SplashStyle.bar),
      };

  @override
  bool operator ==(Object other) =>
      other is SplashSpec &&
      other.style == style &&
      other.logo == logo &&
      other.durationMs == durationMs &&
      other.background == background &&
      other.decor == decor &&
      other.ring == ring &&
      other.logoGlow == logoGlow &&
      other.logoSize == logoSize &&
      other.gap == gap &&
      other.indicator == indicator &&
      other.caption == caption &&
      other.wordmark == wordmark &&
      other.console == console;

  @override
  int get hashCode => Object.hash(
        style,
        logo,
        durationMs,
        background,
        decor,
        ring,
        logoGlow,
        logoSize,
        gap,
        indicator,
        caption,
        wordmark,
        console,
      );
}

/// Every colour in a JSON list that parses; the rest are dropped.
List<Color> _colors(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw.take(6))
      if (parseColor(e is String ? e : null) case final c?) c,
  ];
}

/// A number from JSON, defaulted and clamped. A CDN theme cannot ask for a
/// 4000px logo any more than it can ask for an eight-second splash.
double _clamp(Object? raw, double fallback, double min, double max) {
  final v = raw is num ? raw.toDouble() : fallback;
  return v < min ? min : (v > max ? max : v);
}

double _unit(num v) => v < 0 ? 0 : (v > 1 ? 1 : v.toDouble());
