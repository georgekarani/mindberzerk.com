import 'package:flutter/material.dart';

import '../../design/components/components.dart';
import '../../engine/effective_theme.dart';
import '../../engine/theme_spec.dart';
import '../../shells/aqua_shell.dart';
import '../../shells/gnome_shell.dart';
import '../../shells/plasma_shell.dart';
import '../../shells/tiling_shell.dart';
import '../drawer/shell_drawer.dart';
import 'setup_hello.dart' show setupWallpaperOf;
import 'setup_sheet.dart';

/// What the live preview is a picture of.
enum SetupPreviewMode { desktop, drawer }

/// The REAL desktop, live, drawn small.
///
/// Not a mock. This is the same shell widget the home screen mounts, with the
/// same [EffectiveTheme], so every choice on the sheet below it lands on the
/// real thing: move the dock and the actual dock moves, change the drawer
/// columns and the actual drawer reflows, with the user's own apps in it.
///
/// It is laid out at the true screen size and then scaled as one picture, so
/// nothing reflows for a smaller box and the preview is exactly the desktop
/// the user will get, only smaller. Touch and semantics are off: it is a
/// picture of the desktop, not a second copy of it to operate.
///
/// The terminal shell is left out on purpose. It takes keyboard focus when it
/// mounts, which during setup would open the keyboard over the wizard, and its
/// path through setup has no rows that would change it anyway.
class SetupLivePreview extends StatelessWidget {
  const SetupLivePreview({
    super.key,
    required this.theme,
    this.mode = SetupPreviewMode.desktop,
  });

  final EffectiveTheme theme;
  final SetupPreviewMode mode;

  Widget _surface() {
    if (mode == SetupPreviewMode.drawer) return ShellDrawer(theme: theme);
    return switch (theme.shell) {
      ShellKind.gnome => GnomeShell(theme: theme),
      ShellKind.plasma => PlasmaShell(theme: theme),
      ShellKind.tiling => TilingShell(theme: theme),
      ShellKind.aqua => AquaShell(theme: theme),
      ShellKind.tui => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    // The chrome the home screen installs above every shell. Built here
    // because setup is not under the home screen, and the shells read it.
    final chrome = ChromeData.fromPalette(
      theme.palette,
      typography: theme.typography,
      textScale: theme.textScale,
      family: theme.chromeFamily,
      opacity: theme.surfaceOpacity,
      panelBlur: theme.panelBlur,
      panelTint: theme.panelTint,
      panelRadius: theme.panelRadius,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: screen.width,
          height: screen.height,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: ChromeScope(
                  data: chrome,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // The shells leave the desktop to the system wallpaper,
                      // which is not behind a setup screen, so it is painted.
                      SetupWallpaper(
                        palette: theme.palette,
                        image: setupWallpaperOf(theme),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: KeyedSubtree(
                          key: ValueKey(mode),
                          child: _surface(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The layout every "make it yours" screen shares: the live desktop on top,
/// a sheet of choices below it, over the distro's wallpaper.
///
/// [sheetFraction] is how much of the screen height the sheet takes. The
/// preview gets whatever is left above it, at the phone's own aspect ratio.
class SetupStageScaffold extends StatelessWidget {
  const SetupStageScaffold({
    super.key,
    required this.theme,
    required this.ink,
    required this.child,
    required this.liveLabel,
    this.mode = SetupPreviewMode.desktop,
    this.sheetFraction = 0.56,
    this.showPreview = true,
  });

  final EffectiveTheme theme;
  final SetupInk ink;
  final Widget child;
  final String liveLabel;
  final SetupPreviewMode mode;
  final double sheetFraction;

  /// False for the terminal, which has no desktop to preview.
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final sheetTop = size.height * (1 - sheetFraction);

    return Stack(
      fit: StackFit.expand,
      children: [
        SetupWallpaper(
          palette: theme.spec.palette,
          image: setupWallpaperOf(theme),
        ),
        // A veil, so the small live desktop reads as the subject and the
        // full-size wallpaper behind it as the room it sits in.
        ColoredBox(color: ink.scrim.withValues(alpha: 0.45)),
        if (showPreview)
          Positioned(
            left: 0,
            right: 0,
            top: top + 14,
            height: sheetTop - top - 30,
            child: Center(
              child: AspectRatio(
                aspectRatio: size.width / size.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(color: Color(0x66000000), blurRadius: 24),
                        ],
                      ),
                      child: SetupLivePreview(theme: theme, mode: mode),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _LiveTag(label: liveLabel, ink: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: sheetTop,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ink.scrim.withValues(alpha: 0.96),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// "Live", with a green dot: this picture is the real desktop, updating.
class _LiveTag extends StatelessWidget {
  const _LiveTag({required this.label, required this.ink});

  final String label;
  final SetupInk ink;

  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: ink.scrim.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF26A269),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 10.5, color: ink.text)),
          ],
        ),
      );
}
