/// The accent taken from the wallpaper. PHASE 6.
///
/// ─── ONE MORE SWATCH, NOT A NEW SYSTEM ──────────────────────────────────────
///
/// A distro already offers its accents through `prefs.accentId`, folded into
/// `EffectiveTheme.palette` so the hundred places that read the accent cannot
/// miss a choice. The wallpaper is one more entry in that list, under the
/// reserved id [wallpaperAccentId]. Nothing that reads `palette.accent` has to
/// know where the colour came from.
///
/// ─── WHY THE COLOUR IS ADJUSTED ─────────────────────────────────────────────
///
/// A wallpaper's main colour is chosen for the wallpaper, not for a button on
/// this distro's bar. A pale sky on Breeze's pale panel, or a near-black forest
/// on Kali's black bar, would make every accented control vanish. So the
/// wallpaper's most colourful tone is kept and its LIGHTNESS is moved, only as
/// far as it takes, until it stands off the distro's bar at a 3:1 contrast,
/// the WCAG floor for interface components. The hue the person recognises from
/// their wallpaper survives; only how light it is changes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/app_repository.dart';

/// The `accentId` meaning "take it from the wallpaper".
const wallpaperAccentId = 'wallpaper';

/// The system wallpaper's main colours, most prominent first. Empty below
/// Android 8.1, for a wallpaper the system cannot describe, or on any failure.
///
/// Read again whenever the launcher comes back to the front, which is when a
/// wallpaper set in another app shows up, and invalidated by the launcher's
/// own wallpaper screen after it applies one.
final wallpaperColorsProvider = FutureProvider<List<Color>>((ref) async {
  final observer = _ResumeObserver(() => ref.invalidateSelf());
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

  try {
    final argb = await ref.read(launcherHostApiProvider).wallpaperColors();
    return [for (final c in argb) Color(c)];
  } catch (_) {
    return const [];
  }
});

/// Runs [refresh] after a short pause; callers pass
/// `() => ref.invalidate(wallpaperColorsProvider)` from whichever kind of ref
/// they hold.
///
/// The pause is for Android, which describes a newly set wallpaper a moment
/// after the set returns; asking at once can read the old picture's colours.
void refreshWallpaperColorsSoon(void Function() refresh) {
  Future<void>.delayed(const Duration(milliseconds: 800), refresh);
}

class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// The accent [colors] give against a bar of [bar], or null when none of
/// them has enough colour to be an accent (a black-and-white photo), in which
/// case the distro's own accent stands.
Color? wallpaperAccentFor(List<Color> colors, Color bar) {
  final picked = _mostColourful(colors);
  if (picked == null) return null;
  return _readableOn(picked, bar);
}

/// The most saturated of [colors], weighted toward the prominent ones, or
/// null when all of them are close to grey.
Color? _mostColourful(List<Color> colors) {
  Color? best;
  var bestScore = 0.0;
  for (var i = 0; i < colors.length; i++) {
    final hsl = HSLColor.fromColor(colors[i]);
    // Saturation only counts where there is lightness for it to show in:
    // a "saturated" near-black reads as black.
    final chroma = hsl.saturation * (1 - (2 * hsl.lightness - 1).abs());
    // The wallpaper's primary colour gets a small edge over its secondaries.
    final score = chroma * (1 - i * 0.1);
    if (score > bestScore) {
      bestScore = score;
      best = colors[i];
    }
  }
  return bestScore < _minChroma ? null : best;
}

/// Below this the colour reads as grey, and a grey accent is no accent.
const _minChroma = 0.12;

/// The contrast an accented control needs against its surface.
const _minContrast = 3.0;

/// [c] with its lightness moved the least distance that clears
/// [_minContrast] against [bar]. Lighter on a dark bar, darker on a light
/// one. Returned as is when it already clears.
Color _readableOn(Color c, Color bar) {
  if (_contrast(c, bar) >= _minContrast) return c;
  final hsl = HSLColor.fromColor(c);
  final barIsDark = bar.computeLuminance() < 0.5;
  for (var step = 1; step <= 20; step++) {
    final l = barIsDark
        ? math.min(1.0, hsl.lightness + step * 0.04)
        : math.max(0.0, hsl.lightness - step * 0.04);
    final next = hsl.withLightness(l).toColor();
    if (_contrast(next, bar) >= _minContrast) return next;
  }
  return hsl.withLightness(barIsDark ? 0.85 : 0.2).toColor();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The glyph inside the Wallpaper swatch, in black or white, whichever reads
/// on the swatch's own colour.
class WallpaperAccentMark extends StatelessWidget {
  const WallpaperAccentMark({super.key, required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) {
    final light = colour.computeLuminance() > 0.45;
    return Center(
      child: Icon(
        Icons.wallpaper,
        size: 16,
        color: light ? const Color(0xDD000000) : const Color(0xEEFFFFFF),
      ),
    );
  }
}
