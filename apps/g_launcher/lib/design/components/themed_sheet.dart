import 'package:flutter/material.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../settings_look.dart';
import '../tokens/spacing.dart';
import 'chrome_theme.dart';
import 'glass_panel.dart';

/// A themed modal sheet.
///
/// The important detail is the route boundary: `showModalBottomSheet` pushes a
/// route that is NOT a descendant of the calling screen's [ChromeScope], so a
/// primitive built inside `builder` would read [ChromeData.bootstrap] and the
/// sheet would render in house colours over a themed screen. So [show] reads
/// the data BEFORE pushing and re-wraps the sheet body in a fresh
/// [ChromeScope]. Any new modal must do the same.
///
/// ─── AND IT IS DRAWN THE WAY THE DISTRO DRAWS ONE ───────────────────────────
///
/// GNOME and iOS slide a sheet up from the bottom; Cinnamon, KDE, Xfce and a
/// terminal open a small window in the middle with their own title bar and
/// their own way to close it. [show] reads the distro's [SettingsLook] and
/// picks the frame; callers pass the same arguments either way.
class ThemedSheet {
  const ThemedSheet._();

  /// Show a themed sheet. Returns whatever the sheet pops with.
  ///
  /// [title] renders the distro's header above [builder]'s content. Content
  /// that draws its own header (see `settingsSheetHead`) passes no title and
  /// reads the frame's look from [SheetLookScope].
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    bool isScrollControlled = false,
    // The distro's chrome, for a caller whose [context] sits under no
    // ChromeScope: a drawer menu or Kickoff, which build their own. Without
    // it the sheet fell back to the bootstrap chrome and wore the wrong
    // distro's accent (orange buttons on KDE).
    ChromeData? chrome,
  }) {
    // Capture the live chrome from the screen that's opening the sheet.
    final data = chrome ?? ChromeScope.of(context);

    // ─── CAPTURED NOW, NEVER READ FROM [context] INSIDE THE BUILDER ─────────
    //
    // The builder runs again on every rebuild of the sheet, and the keyboard
    // opening is one. By then the widget that opened the sheet (a drawer
    // tile, a menu row) may be gone, and `Theme.of(context)` on its dead
    // element threw "Looking up a deactivated widget's ancestor is unsafe".
    // First seen on the app Edit sheet, the first sheet here with a text field.
    final hostTheme = Theme.of(context);
    final look = SettingsLook.resolve(context);
    if (look != null && !look.sheetSlidesUp) {
      return _window<T>(context, data, look, title, builder);
    }
    final c = data.colors;

    // TOP CORNERS ONLY, from the shared setting. The sheet cannot pass the
    // radius straight to GlassPanel because its bottom two corners run off the
    // screen and rounding them would cut a notch out of the display edge; so it
    // builds its own shape from the same number rather than keeping a literal
    // that the setting would silently fail to move.
    final radius = switch (look) {
      SettingsLook.grouped => 28.0,
      SettingsLook.boxed => 18.0,
      _ => data.panelRadius,
    };
    final top = BorderRadius.vertical(top: Radius.circular(radius));

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      shape: RoundedRectangleBorder(borderRadius: top),
      builder: (ctx) => Theme(
        data: hostTheme.copyWith(
          bottomSheetTheme: const BottomSheetThemeData(
            surfaceTintColor: Colors.transparent,
          ),
        ),
        child: ChromeScope(
          data: data,
          child: GlassPanel(
            borderRadius: top,
            border: Border(top: BorderSide(color: c.lineStrong)),
            child: _SheetBody(
              title: title,
              look: look,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
  }

  /// The centred window Cinnamon, KDE, Xfce and the terminal open instead.
  static Future<T?> _window<T>(
    BuildContext context,
    ChromeData data,
    SettingsLook look,
    String? title,
    WidgetBuilder builder,
  ) {
    final c = data.colors;
    final shape = switch (look) {
      SettingsLook.config => RoundedRectangleBorder(
          side: BorderSide(color: c.text, width: 2),
        ),
      SettingsLook.form => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: BorderSide(color: c.line),
        ),
      _ => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            look == SettingsLook.cinnamon ? 8 : 6,
          ),
          side: BorderSide(color: c.line),
        ),
    };
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => ChromeScope(
        data: data,
        child: Dialog(
          backgroundColor: c.bg,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: SheetLookScope(
            look: look,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) LookSheetHeader(look: look, title: title),
                Flexible(child: Builder(builder: builder)),
                _WindowFooter(look: look),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.child, this.title, this.look});

  final Widget child;
  final String? title;
  final SettingsLook? look;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final c = d.colors;
    final look = this.look;

    if (look != null) {
      return SafeArea(
        top: false,
        child: SheetLookScope(
          look: look,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) LookSheetHeader(look: look, title: title!),
              Flexible(child: child),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: GSpace.md, bottom: GSpace.sm),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GSpace.lg,
                GSpace.sm,
                GSpace.lg,
                GSpace.md,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title!, style: d.text.title),
              ),
            ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// The look of the sheet or window a widget is inside, for content that draws
/// its own header.
class SheetLookScope extends InheritedWidget {
  const SheetLookScope({super.key, required this.look, required super.child});

  final SettingsLook look;

  static SettingsLook? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetLookScope>()?.look;

  @override
  bool updateShouldNotify(SheetLookScope oldWidget) => oldWidget.look != look;
}

/// A sheet's header as each distro draws it: a grabber and a centred title
/// (GNOME), the same with Done (iOS), a title bar (Cinnamon, KDE with its
/// close button, Xfce), or a centred key in a terminal box.
class LookSheetHeader extends StatelessWidget {
  const LookSheetHeader({super.key, required this.look, required this.title});

  final SettingsLook look;
  final String title;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final c = d.colors;

    Widget grabber() => Center(
          child: Container(
            width: 36,
            height: look == SettingsLook.grouped ? 5 : 4,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            decoration: BoxDecoration(
              color: c.lineStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );

    return switch (look) {
      SettingsLook.boxed => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      SettingsLook.grouped => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  const SizedBox(width: 64),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(
                        context.t('common.done'),
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      SettingsLook.cinnamon => Container(
          height: 40,
          color: c.bar,
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      SettingsLook.form => Container(
          height: 44,
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.close, size: 18, color: c.textMuted),
                tooltip: context.t('common.cancel'),
              ),
            ],
          ),
        ),
      SettingsLook.dialog => Container(
          height: 36,
          color: c.bar,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      SettingsLook.config => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            configKey(title),
            textAlign: TextAlign.center,
            style: d.text.value.copyWith(
              color: c.warn,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    };
  }
}

/// The way out of a centred window: Close for Cinnamon and Xfce, <Cancel> in a
/// terminal. KDE closes from its title bar and has none.
class _WindowFooter extends StatelessWidget {
  const _WindowFooter({required this.look});

  final SettingsLook look;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final c = d.colors;
    void close() => Navigator.of(context).maybePop();

    return switch (look) {
      SettingsLook.cinnamon || SettingsLook.dialog => Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: look == SettingsLook.dialog
              ? BoxDecoration(border: Border(top: BorderSide(color: c.line)))
              : null,
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: close,
            style: TextButton.styleFrom(
              backgroundColor: c.surfaceAlt,
              foregroundColor: c.text,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(context.t('common.close')),
          ),
        ),
      SettingsLook.config => Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Center(
            child: GestureDetector(
              onTap: close,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '<${context.t('common.cancel')}>',
                  style: d.text.value,
                ),
              ),
            ),
          ),
        ),
      SettingsLook.boxed ||
      SettingsLook.grouped ||
      SettingsLook.form =>
        const SizedBox.shrink(),
    };
  }
}
