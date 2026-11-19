import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:g_design/g_design.dart';

import 'tokens.dart';

/// Builds ThemeData from a token set.
///
/// The ColorScheme is written out explicitly rather than seeded. A seeded
/// scheme derives tones we do not control, and any Material widget that reaches
/// past GTokens into the scheme would then paint a colour nobody chose.
ThemeData buildGTheme(GTokens t) {
  final ColorScheme scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.accentText,
    secondary: t.chat,
    onSecondary: t.onAccent,
    error: t.danger,
    onError: t.onAccent,
    surface: t.panel,
    onSurface: t.text,
    surfaceContainerLowest: t.ink,
    surfaceContainerLow: t.panel,
    surfaceContainer: t.panelAlt,
    surfaceContainerHigh: t.panelHigh,
    surfaceContainerHighest: t.panelHigh,
    onSurfaceVariant: t.muted,
    outline: t.lineStrong,
    outlineVariant: t.line,
    scrim: t.scrim,
  );

  final TextTheme textTheme = TextTheme(
    displaySmall: GType.display.copyWith(color: t.text),
    titleLarge: GType.title.copyWith(color: t.text),
    titleMedium: GType.heading.copyWith(color: t.text),
    bodyLarge: GType.body.copyWith(color: t.text),
    bodyMedium: GType.bodySmall.copyWith(color: t.muted),
    labelLarge: GType.label.copyWith(color: t.text),
    labelSmall: GType.micro.copyWith(color: t.dim),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[t, gDesignTheme(t)],
    scaffoldBackgroundColor: t.ink,
    canvasColor: t.ink,
    dividerColor: t.line,
    splashFactory: InkRipple.splashFactory,
    textTheme: textTheme,
    iconTheme: IconThemeData(color: t.muted, size: 20),
    // Nothing in this app is allowed to construct a SnackBar. The theme below
    // exists only so that a stray one from a package is visually contained
    // rather than neon pink. tool/no_snackbars.sh blocks our own code.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.panelAlt,
      contentTextStyle: GType.bodySmall.copyWith(color: t.text),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        // iOS-style push: the new page slides over while the old one
        // parallaxes and dims, with the edge swipe to go back.
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// System bars follow the theme. Called on every theme change, not once at
/// boot, or the status bar icons stay unreadable after a light to dark switch.
SystemUiOverlayStyle gSystemOverlay(GTokens t) {
  final Brightness iconBrightness = t.brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: t.brightness,
    // Transparent, so content runs under the gesture area and the floating
    // nav is the only thing at the bottom edge. Contrast enforcement off, or
    // Android paints its own scrim back over the content.
    systemNavigationBarColor: const Color(0x00000000),
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarDividerColor: const Color(0x00000000),
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}

/// G Recovery's accent and base type, handed to the shared g_design widgets.
///
/// The neutrals come from g_design's approved light and dark palettes, so
/// every app on the language draws the same greys; G Recovery only brings
/// its accent.
GDesignTheme gDesignTheme(GTokens t) {
  final bool dark = t.brightness == Brightness.dark;
  return dark
      ? GDesignTheme.dark(
          accent: t.accent,
          accentText: t.accentText,
          sans: GType.body,
          mono: GType.monoNumber,
        )
      : GDesignTheme.light(
          accent: t.accent,
          accentText: t.accentText,
          sans: GType.body,
          mono: GType.monoNumber,
        );
}
