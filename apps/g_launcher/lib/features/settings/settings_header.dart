import 'package:flutter/material.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../engine/effective_theme.dart';
import 'wallpaper_screen.dart' show previewWallpaperFor, wallpaperImageFor;

/// The top of the Settings home: the desktop you are on, full width.
///
/// The wallpaper is the one actually on screen (a photo the user picked, a
/// rotation's current frame, or the distro's own), so the header is a picture
/// of THIS phone rather than of the distro in general. Under it, the distro's
/// name and the one action that changes all of it.
class SettingsDesktopHeader extends StatelessWidget {
  const SettingsDesktopHeader({
    super.key,
    required this.theme,
    required this.onChange,
  });

  final EffectiveTheme theme;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final palette = theme.spec.palette;
    final wallpaper = wallpaperImageFor(theme, previewWallpaperFor(theme));
    final logo = theme.spec.logoAsset(onDarkSurface: true);
    final mq = MediaQuery.of(context);
    final name = theme.spec.version.isEmpty
        ? theme.spec.name
        : '${theme.spec.name} ${theme.spec.version}';

    // Contrast-picked ink for the Change button, so a pale accent gets dark
    // text without a field in theme.json.
    final accent = palette.accent;
    final onAccent = accent.computeLuminance() > 0.4
        ? const Color(0xFF14080F)
        : const Color(0xFFFFFFFF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.bgTop, palette.bgBottom],
                  ),
                ),
              ),
              if (wallpaper != null)
                Image(
                  // Decoded at the header's width, not the source's: a 4K
                  // wallpaper decoded whole for a 220dp strip is tens of MB of
                  // image cache on a page people open often.
                  image: ResizeImage(
                    wallpaper,
                    width: (mq.size.width * mq.devicePixelRatio).round(),
                    allowUpscaling: false,
                  ),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Color.alphaBlend(
                    const Color(0x66000000),
                    palette.bgBottom,
                  ).withValues(alpha: 0.86),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        if (logo != null) ...[
                          Image(
                            image: logo.image,
                            width: 34,
                            height: 34,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF7F2F5),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.t('settings.home.yourDesktop'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFD9C9D2),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: onChange,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: onAccent,
                            minimumSize: const Size(64, 40),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(context.t('settings.home.change')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
