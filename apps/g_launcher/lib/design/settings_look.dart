/// The page grammar a settings DETAIL page wears, one per real settings app.
///
/// [ChromeFamily] says which toolkit the colours and corners come from. This
/// says how a page of controls is laid out, which is a different question:
/// Mint and Ubuntu share Adwaita colours but Cinnamon's System Settings frames
/// its sections and uses a tab switcher, and the terminal shares the WM's
/// config-file voice even though its chrome is generic.
///
/// The landing is NOT governed by this. It is installed only by the section
/// pages, so [SettingsLookScope.of] is null on the landing and every widget
/// there renders exactly as before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/effective_theme.dart';
import '../engine/theme_spec.dart' show ChromeFamily, ShellKind, ThemeSpec;
import 'components/components.dart';

/// One value per real settings application the catalogue imitates.
enum SettingsLook {
  /// GNOME Settings: boxed lists, bold sentence-case headings, switches.
  boxed,

  /// Cinnamon System Settings: framed sections with a hairline border and
  /// joined toggle buttons.
  cinnamon,

  /// KDE System Settings: a Kirigami form. Labels right-aligned in a left
  /// column, controls in the right one, checkboxes instead of switches.
  form,

  /// The Xfce Settings Manager dialog: bold legends, indented rows,
  /// checkboxes with their label to the right.
  dialog,

  /// iOS Settings: inset grouped lists, small uppercase headers, green
  /// switches.
  grouped,

  /// No settings app at all: a config file. `[section]` headers and
  /// `key = value` lines, tap a value to change it.
  config;

  /// Parse a theme.json `settingsLook` value. Unknown or absent yields null,
  /// so a value from a newer pack degrades to the derived look.
  static SettingsLook? parse(String? raw) {
    for (final look in values) {
      if (look.name == raw) return look;
    }
    return null;
  }

  /// Whether a two-state setting is drawn as a checkbox rather than a switch.
  bool get checkboxes => this == form || this == dialog;

  /// Whether rows sit directly on the page instead of inside a card.
  bool get bare => this == form || this == dialog || this == config;

  /// Whether a sheet slides up from the bottom (GNOME, iOS) rather than
  /// opening as a small centred window (Cinnamon, KDE, Xfce, terminal).
  bool get sheetSlidesUp => this == boxed || this == grouped;

  /// The vertical gap between two groups on a page.
  double get groupGap => switch (this) {
        boxed => 22,
        cinnamon => 20,
        form => 18,
        dialog => 18,
        grouped => 26,
        config => 10,
      };

  /// The minimum height of one row, matching each toolkit's list rows.
  double get rowHeight => switch (this) {
        boxed => 52,
        cinnamon => 48,
        form => 44,
        dialog => 42,
        grouped => 46,
        config => 36,
      };

  /// Whether the page title sits in the middle of the bar.
  bool get centeredTitle => switch (this) {
        boxed || cinnamon || grouped => true,
        form || dialog || config => false,
      };

  /// Width of the label column in [form].
  static const double formLabelWidth = 116;

  /// The settings app a distro's pages imitate.
  ///
  /// Mint is told apart by its menu. Its live pack runs the plasma shell with
  /// Adwaita chrome and `appDrawer: cinnamon`; `kicker` also resolves to the
  /// cinnamon widget, so the raw pack value is compared, not the resolved
  /// widget. Packs with no chrome family fall back on their shell, so a tiling
  /// WM or the terminal gets the config file and a Plasma pack the KDE form.
  /// The look for anything drawn under [context]: the page's own when inside
  /// a settings page, else the active distro's. Null before the theme has
  /// loaded, which keeps the house style for that first frame.
  static SettingsLook? resolve(BuildContext context) {
    final scoped = SettingsLookScope.of(context);
    if (scoped != null) return scoped;
    final theme = ProviderScope.containerOf(context, listen: false)
        .read(effectiveThemeProvider)
        .asData
        ?.value;
    return theme == null ? null : forTheme(theme);
  }

  static SettingsLook forTheme(EffectiveTheme theme) =>
      forSpec(theme.spec, appDrawer: theme.appDrawer);

  /// The same answer from a pack alone, for screens that show a distro before
  /// it is applied (setup). [appDrawer] overrides the pack's own drawer.
  ///
  /// A distro's own `settingsLook` wins. Without one the look is derived from
  /// the drawer, then the chrome family, then the shell, so every pack
  /// published before the field existed keeps the look it has today.
  static SettingsLook forSpec(ThemeSpec spec, {String? appDrawer}) {
    final named = parse(spec.settingsLook);
    if (named != null) return named;
    if ((appDrawer ?? spec.layout.appDrawer) == 'cinnamon') {
      return SettingsLook.cinnamon;
    }
    return switch (spec.chromeFamily) {
      ChromeFamily.adwaita => SettingsLook.boxed,
      ChromeFamily.breeze => SettingsLook.form,
      ChromeFamily.xfce => SettingsLook.dialog,
      ChromeFamily.wm => SettingsLook.config,
      ChromeFamily.aqua || ChromeFamily.pocket => SettingsLook.grouped,
      ChromeFamily.generic => switch (spec.shell) {
          ShellKind.gnome || ShellKind.aqua => SettingsLook.boxed,
          ShellKind.plasma => SettingsLook.form,
          ShellKind.tiling || ShellKind.tui => SettingsLook.config,
        },
    };
  }
}

/// Installs a [SettingsLook] for everything below it.
class SettingsLookScope extends InheritedWidget {
  const SettingsLookScope({
    super.key,
    required this.look,
    required super.child,
  });

  final SettingsLook look;

  /// The look for this subtree, or null outside a section page.
  static SettingsLook? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsLookScope>()?.look;

  @override
  bool updateShouldNotify(SettingsLookScope oldWidget) =>
      oldWidget.look != look;
}

/// A config-file key derived from a row title: "Dock position" -> dock_position.
String configKey(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// One row that names a setting and shows its current value, drawn the way
/// the page's look draws a row that opens something.
///
/// Used for the controls that are too big to live on the page itself: the
/// picture choices and the sliders. The page shows the value; the control
/// opens in a sheet.
class LookValueRow extends StatelessWidget {
  const LookValueRow({
    super.key,
    required this.look,
    required this.title,
    this.value,
    this.onTap,
  });

  final SettingsLook look;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final c = d.colors;

    final Widget content = switch (look) {
      SettingsLook.form => Row(
          children: [
            SizedBox(
              width: SettingsLook.formLabelWidth,
              child: Text(
                '$title:',
                textAlign: TextAlign.right,
                style: TextStyle(color: c.text, fontSize: 13.5),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value != null) ...[
                    Text(value!, style: TextStyle(color: c.text, fontSize: 13)),
                    const SizedBox(width: 6),
                  ],
                  Icon(Icons.expand_more, size: 16, color: c.textMuted),
                ],
              ),
            ),
          ],
        ),
      SettingsLook.config => Row(
          children: [
            Text(
              configKey(title),
              style: d.text.value.copyWith(color: c.accent),
            ),
            Text(' = ', style: d.text.value.copyWith(color: c.textFaint)),
            Flexible(
              child: Text(
                value ?? '',
                style: d.text.value,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ),
          ],
        ),
      SettingsLook.boxed ||
      SettingsLook.cinnamon ||
      SettingsLook.dialog ||
      SettingsLook.grouped =>
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: switch (look) {
              SettingsLook.dialog => 0.0,
              SettingsLook.grouped => 16.0,
              _ => 14.0,
            },
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: switch (look) {
                      SettingsLook.grouped => 16.0,
                      SettingsLook.dialog => 13.5,
                      SettingsLook.cinnamon => 14.0,
                      _ => 14.5,
                    },
                  ),
                ),
              ),
              if (value != null) ...[
                Text(
                  value!,
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: look == SettingsLook.grouped ? 16 : 14,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right, size: 18, color: c.textMuted),
            ],
          ),
        ),
    };

    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: look.rowHeight),
          child: Align(alignment: Alignment.centerLeft, child: content),
        ),
      ),
    );
  }
}

/// The sheet behind a [LookValueRow], in the distro's own sheet frame.
///
/// The sheet is a new route, so it sits outside the page's
/// [SettingsLookScope]; the control inside renders at full size, which is the
/// point of opening it.
Future<void> showLookSheet(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) =>
    ThemedSheet.show<void>(
      context,
      title: title,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: SingleChildScrollView(child: Builder(builder: builder)),
      ),
    );

/// A slider setting on a section page: a row with the value, the slider in a
/// sheet. Every change is written as the thumb moves, so the desktop behind
/// the sheet updates live.
class LookSlider extends StatelessWidget {
  const LookSlider({
    super.key,
    required this.look,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.divisions,
  });

  final SettingsLook look;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;

  /// Null when the distro cannot change it; the row is then shown inert.
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return LookValueRow(
      look: look,
      title: label,
      value: format(value),
      onTap: change == null ? null : () => _open(context, change),
    );
  }

  void _open(BuildContext context, ValueChanged<double> change) {
    var current = value.clamp(min, max).toDouble();
    showLookSheet(
      context,
      title: label,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          final d = ChromeScope.of(context);
          return Row(
            children: [
              Expanded(
                child: ThemedSlider(
                  value: current,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: format(current),
                  onChanged: (v) {
                    setState(() => current = v);
                    change(v);
                  },
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  format(current),
                  textAlign: TextAlign.right,
                  style: d.text.value.copyWith(color: d.colors.textMuted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
