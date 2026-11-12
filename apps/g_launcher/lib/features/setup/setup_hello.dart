import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/effective_theme.dart';
import '../../i18n/i18n.dart';
import '../../system/wallpaper_source.dart';
import 'setup_language_sheet.dart';
import 'setup_sheet.dart';

/// Board 1, Hello.
///
/// The wallpaper is the distro the user will get, so the first screen is a
/// picture of the product rather than a form about it. One button installs;
/// restoring is a link because almost nobody takes that path.
///
/// The home-role question that used to live here moved to the moment it makes
/// sense, right after Install is tapped on Ready.
class SetupHello extends ConsumerWidget {
  const SetupHello({
    super.key,
    required this.theme,
    required this.onInstall,
    required this.onRestore,
  });

  final EffectiveTheme theme;
  final VoidCallback onInstall;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = SetupInk.forSpec(theme.spec);
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final logo = theme.spec.logoAsset(onDarkSurface: true);

    return Stack(
      fit: StackFit.expand,
      children: [
        SetupWallpaper(
          palette: theme.spec.palette,
          image: setupWallpaperOf(theme),
        ),
        if (logo != null)
          Positioned(
            left: 0,
            right: 0,
            top: size.height * 0.19,
            child: Center(
              child: Image(
                image: logo.image,
                width: (size.width * 0.4).clamp(96.0, 150.0),
                height: (size.width * 0.4).clamp(96.0, 150.0),
                fit: BoxFit.contain,
                semanticLabel: theme.spec.name,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Positioned(
          top: top + 16,
          right: 18,
          child: _LanguageChip(ink: ink),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SetupBottomPanel(
            ink: ink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The product name, kept out of i18n because it is a name.
                SetupKicker('G Launcher', ink: ink),
                const SizedBox(height: 12),
                Text(
                  ref.t('setup.hello.title'),
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.08,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700,
                    color: ink.text,
                  ),
                ),
                const SizedBox(height: 22),
                SetupPrimaryButton(
                  label: ref.t('setup.hello.install'),
                  ink: ink,
                  onPressed: onInstall,
                ),
                const SizedBox(height: 6),
                Center(
                  child: SetupLink(
                    label: ref.t('setup.hello.restore'),
                    ink: ink,
                    onPressed: onRestore,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The current language, opening the language sheet.
class _LanguageChip extends ConsumerWidget {
  const _LanguageChip({required this.ink});

  final SetupInk ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = ref.watch(i18nProvider);
    final code = i18n.selectedCode ?? i18n.translations.code;
    final name = localeNameFor(code);
    return SetupPill(
      label: name,
      ink: ink,
      trailing: Icons.expand_more_rounded,
      semanticLabel: ref.t('setup.hello.language', {'name': name}),
      onTap: () => showSetupLanguageSheet(context, ink: ink),
    );
  }
}

/// The native name for a language code, falling back to the code itself.
String localeNameFor(String code) {
  for (final l in localesForDisplay()) {
    if (l.code == code) return l.nativeName;
  }
  return code;
}

/// The first wallpaper a distro authors, or null when it is not a theme asset.
///
/// The same guard the old installer used: `isThemeAssetRef` keeps a user path
/// or a URL out of `spec.asset`, which only knows APK and pack files.
ImageProvider? setupWallpaperOf(EffectiveTheme theme) {
  final walls = theme.spec.wallpapers;
  if (walls.isEmpty || !isThemeAssetRef(walls.first)) return null;
  return theme.spec.asset(walls.first).image;
}
