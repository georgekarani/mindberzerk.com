import 'package:flutter/material.dart';

/// The palette and type an app hands to the shared widgets.
///
/// Registered once in `ThemeData.extensions`. Nothing in this package picks a
/// colour of its own, so each app keeps its identity while the layout rules
/// stay identical across all of them.
@immutable
class GDesignTheme extends ThemeExtension<GDesignTheme> {
  const GDesignTheme({
    required this.brightness,
    required this.ground,
    required this.glass,
    required this.glassBorder,
    required this.sheet,
    required this.raised,
    required this.hairline,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.danger,
    required this.onDanger,
    required this.success,
    required this.warning,
    required this.scrim,
    required this.sans,
    required this.mono,
  });

  final Brightness brightness;

  /// The colour behind all content.
  final Color ground;

  /// Floating chrome, already translucent.
  final Color glass;
  final Color glassBorder;

  /// The one raised surface.
  final Color sheet;

  /// Secondary buttons sitting on the sheet.
  final Color raised;
  final Color hairline;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color danger;
  final Color onDanger;
  final Color success;
  final Color warning;
  final Color scrim;

  /// Base text style for words. Size, weight and colour are set per widget.
  final TextStyle sans;

  /// Base text style for numbers, with tabular figures.
  final TextStyle mono;

  /// The registered theme. Throws when an app forgot to register it, which is
  /// a wiring mistake to surface on the first frame rather than paper over.
  static GDesignTheme of(BuildContext context) {
    final GDesignTheme? theme = Theme.of(context).extension<GDesignTheme>();
    if (theme == null) {
      throw StateError('GDesignTheme is missing from ThemeData.extensions.');
    }
    return theme;
  }

  /// 11 dp caps label with 0.09 em tracking.
  TextStyle label({Color? color}) => sans.copyWith(
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.99,
        color: color ?? muted,
      );

  @override
  GDesignTheme copyWith({
    Brightness? brightness,
    Color? ground,
    Color? glass,
    Color? glassBorder,
    Color? sheet,
    Color? raised,
    Color? hairline,
    Color? text,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? danger,
    Color? onDanger,
    Color? success,
    Color? warning,
    Color? scrim,
    TextStyle? sans,
    TextStyle? mono,
  }) =>
      GDesignTheme(
        brightness: brightness ?? this.brightness,
        ground: ground ?? this.ground,
        glass: glass ?? this.glass,
        glassBorder: glassBorder ?? this.glassBorder,
        sheet: sheet ?? this.sheet,
        raised: raised ?? this.raised,
        hairline: hairline ?? this.hairline,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        accentSoft: accentSoft ?? this.accentSoft,
        danger: danger ?? this.danger,
        onDanger: onDanger ?? this.onDanger,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        scrim: scrim ?? this.scrim,
        sans: sans ?? this.sans,
        mono: mono ?? this.mono,
      );

  @override
  GDesignTheme lerp(covariant GDesignTheme? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return GDesignTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      ground: mix(ground, other.ground),
      glass: mix(glass, other.glass),
      glassBorder: mix(glassBorder, other.glassBorder),
      sheet: mix(sheet, other.sheet),
      raised: mix(raised, other.raised),
      hairline: mix(hairline, other.hairline),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      scrim: mix(scrim, other.scrim),
      sans: TextStyle.lerp(sans, other.sans, t) ?? other.sans,
      mono: TextStyle.lerp(mono, other.mono, t) ?? other.mono,
    );
  }
}
