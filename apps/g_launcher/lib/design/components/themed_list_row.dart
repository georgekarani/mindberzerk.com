import 'package:flutter/material.dart';

import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../settings_look.dart';
import 'chrome_theme.dart';

/// The workhorse of the chrome layer: one row in a settings list. Icon, title,
/// optional subtitle, optional trailing control, optional tap.
///
/// It reads [ChromeScope] and nothing else, so the same row is a GNOME setting
/// under Ubuntu and a Breeze setting under KDE with no per-call change — the
/// colours and type come from the derived chrome. Step 3 rebuilds
/// `settings_screen.dart` out of these.
class ThemedListRow extends StatelessWidget {
  const ThemedListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.enabled = true,
  });

  final String title;

  /// A second line. Null renders a single-line row — never a placeholder
  /// string, per the house rule that absent data is an absent line, not "--".
  final String? subtitle;

  final IconData? icon;

  /// Any control: a [ThemedToggle], a chevron, a value label. Kept generic so
  /// the row doesn't grow a variant per trailing type.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Destructive rows (delete a theme, reset). Tints the icon + title with the
  /// semantic danger colour so the weight of the action reads at a glance.
  final bool danger;

  final bool enabled;

  /// The row on a screen opened from Settings: title, a short value at the
  /// right, the control. Long subtitles are descriptions and are dropped.
  Widget _immersive(BuildContext context, SettingsLook look, ChromeData d) {
    final c = d.colors;
    final sub = subtitle;
    final value =
        trailing == null && sub != null && sub.length <= 28 ? sub : null;
    final titleColor = !enabled
        ? c.textFaint
        : danger
            ? c.danger
            : c.text;
    final Widget head = look == SettingsLook.config
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: configKey(title),
                  style: TextStyle(color: danger ? c.danger : c.accent),
                ),
                if (value != null) ...[
                  TextSpan(
                    text: ' = ',
                    style: TextStyle(color: c.textFaint),
                  ),
                  TextSpan(text: value),
                ],
              ],
            ),
            style: d.text.value,
          )
        : Text(
            title,
            style: TextStyle(
              color: titleColor,
              fontSize: switch (look) {
                SettingsLook.grouped => 16.0,
                SettingsLook.dialog || SettingsLook.form => 13.5,
                SettingsLook.cinnamon => 14.0,
                _ => 14.5,
              },
            ),
          );
    final side = switch (look) {
      SettingsLook.form || SettingsLook.dialog || SettingsLook.config => 0.0,
      SettingsLook.grouped => 16.0,
      _ => 14.0,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: look.rowHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Row(
              children: [
                Expanded(child: head),
                if (value != null && look != SettingsLook.config) ...[
                  const SizedBox(width: 12),
                  Text(
                    value,
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: look == SettingsLook.grouped ? 16 : 14,
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 18, color: c.textMuted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final look = SettingsLookScope.of(context);
    if (look != null && !d.inMenu) return _immersive(context, look, d);
    final c = d.colors;

    // ─── A MENU ROW MAY BE TEXT ONLY ────────────────────────────────────
    //
    // GNOME menus and macOS menus carry no icons; Breeze and Xfce menus do.
    // [ChromeMenu.rowIcons] is the family's answer and it is applied HERE
    // rather than by passing a null icon at each call site, because rows in a
    // menu are built in six places and three of them are callers handing in
    // their own list.
    //
    // Gated on [ChromeData.inMenu], which only [AnchoredMenu] sets. A settings
    // list is not a menu: an Adwaita settings page genuinely does carry icons,
    // and stripping them would be the right convention applied to the wrong
    // surface.
    final showIcon = icon != null && (!d.inMenu || d.menu.rowIcons);

    final titleColor = !enabled
        ? c.textFaint
        : danger
            ? c.danger
            : c.text;
    final iconColor = !enabled
        ? c.textFaint
        : danger
            ? c.danger
            : c.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        splashColor: c.accent.withValues(alpha: 0.10),
        highlightColor: c.surfaceAlt.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GSpace.lg,
            vertical: GSpace.md,
          ),
          child: Row(
            children: [
              if (showIcon) ...[
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: GSpace.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: d.text.body.copyWith(color: titleColor)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: d.text.caption),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: GSpace.md),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A section heading above a group of [ThemedListRow]s. Small caps-y label in
/// the chrome's faint ink — the same rhythm your existing `_Head` gives, but
/// themed.
class ThemedSectionHeader extends StatelessWidget {
  const ThemedSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final look = SettingsLookScope.of(context);
    if (look != null) {
      final c = d.colors;
      final title =
          text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
      return Padding(
        padding: switch (look) {
          SettingsLook.grouped => const EdgeInsets.fromLTRB(32, 22, 32, 6),
          SettingsLook.config => const EdgeInsets.fromLTRB(10, 14, 10, 4),
          _ => const EdgeInsets.fromLTRB(16, 22, 16, 8),
        },
        child: switch (look) {
          SettingsLook.config => Text(
              '[${configKey(text)}]',
              style: d.text.value.copyWith(color: c.warn),
            ),
          SettingsLook.grouped => Text(
              title.toUpperCase(),
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12.5,
                letterSpacing: 0.4,
              ),
            ),
          _ => Text(
              title,
              style: TextStyle(
                color: c.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GSpace.lg,
        GSpace.xl,
        GSpace.lg,
        GSpace.sm,
      ),
      // SENTENCE CASE, not upper.
      //
      // `label` still carries the small size and the letter spacing, and both
      // suit an uppercase caption, which is why this shouted for so long. But
      // neither GNOME nor KDE uppercases a section heading: that is an iOS and
      // One UI convention, and it was one of the two things making this chrome
      // read as a phone app wearing Ubuntu's orange. The other was the icon
      // circle on every row.
      //
      // Muted rather than faint, because a heading that is quieter than the
      // rows beneath it stops grouping them.
      child: Text(
        text,
        style: d.text.label.copyWith(
          color: d.colors.textMuted,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// A grouped card wrapping rows, Adwaita-style (rounded, inset, hairline
/// between rows). KDE/Breeze can later opt for a flatter framing via
/// chromeFamily; the rows inside don't change.
class ThemedListCard extends StatelessWidget {
  const ThemedListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    final look = SettingsLookScope.of(context);
    if (look != null && look.bare) {
      // Kirigami forms, Xfce frames and a config file have no card.
      return Padding(
        padding: EdgeInsets.fromLTRB(
          look == SettingsLook.dialog ? 28 : 16,
          0,
          16,
          8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    if (look != null) {
      final grouped = look == SettingsLook.grouped;
      final radius = look == SettingsLook.cinnamon ? 6.0 : 12.0;
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        if (i > 0) {
          rows.add(
            Divider(
              height: 1,
              thickness: grouped ? 0.5 : 1,
              indent: grouped ? 16 : 0,
              color: c.line,
            ),
          );
        }
        rows.add(children[i]);
      }
      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: grouped ? 16 : 12,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(radius),
          border:
              look == SettingsLook.cinnamon ? Border.all(color: c.line) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      );
    }
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        divided.add(Divider(
            height: 0.5,
            thickness: 0.5,
            color: c.line,
            indent: GSpace.lg,
            endIndent: GSpace.lg));
      }
      divided.add(children[i]);
    }
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: GSpace.lg, vertical: GSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: GRadius.mdAll,
        border: Border.all(color: c.line, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: divided),
    );
  }
}
