import 'package:flutter/material.dart';

import '../../design/settings_look.dart';
import '../../engine/theme_spec.dart';

/// Shared building blocks for the immersive setup flow.
///
/// Every setup screen is the same composition: the distro's own wallpaper,
/// full bleed, with one panel or sheet of controls over it. These widgets keep
/// that composition identical across screens so the flow reads as one surface
/// rather than a series of pages.

/// Colours for text and controls laid over a wallpaper.
///
/// Derived from the distro palette rather than from [ChromeData], because the
/// chrome greys are tuned for settings pages and wash out over a photograph.
/// The scrim is the palette's darkest stop, so Ubuntu gets an aubergine panel
/// and KDE a slate one with no per-distro authoring.
@immutable
class SetupInk {
  const SetupInk({
    required this.scrim,
    required this.text,
    required this.textMuted,
    required this.line,
    required this.accent,
    required this.onAccent,
    this.look,
    this.mono,
  });

  /// The setup screens in the chosen distro's own look: its buttons,
  /// marks and panel shape. Built from the pack, before it is applied.
  factory SetupInk.forSpec(ThemeSpec spec) {
    final base = SetupInk.of(spec.palette);
    return SetupInk(
      scrim: base.scrim,
      text: base.text,
      textMuted: base.textMuted,
      line: base.line,
      accent: base.accent,
      onAccent: base.onAccent,
      look: SettingsLook.forSpec(spec),
      mono: spec.typography.mono,
    );
  }

  factory SetupInk.of(ThemePalette palette) {
    final accent = palette.accent;
    return SetupInk(
      scrim: Color.alphaBlend(
        const Color(0x66000000),
        palette.bgBottom,
      ).withValues(alpha: 0.86),
      text: const Color(0xFFF7F2F5),
      textMuted: const Color(0xFFD9C9D2),
      line: const Color(0x2EFFFFFF),
      accent: accent,
      // Contrast-picked ink, so a pale accent (Mint green) gets dark text and a
      // deep one gets white, without a field in theme.json.
      onAccent: accent.computeLuminance() > 0.4
          ? const Color(0xFF14080F)
          : const Color(0xFFFFFFFF),
    );
  }

  final Color scrim;
  final Color text;
  final Color textMuted;
  final Color line;
  final Color accent;
  final Color onAccent;

  /// Null keeps the shared setup look.
  final SettingsLook? look;

  /// The pack's monospace face, for the config-file look.
  final String? mono;

  bool get isConfig => look == SettingsLook.config;

  /// Corner radius of a button in this look.
  double get buttonRadius => switch (look) {
        SettingsLook.boxed => 27,
        SettingsLook.grouped => 14,
        SettingsLook.cinnamon => 6,
        SettingsLook.form || SettingsLook.dialog => 4,
        SettingsLook.config => 0,
        null => 14,
      };

  TextStyle monoStyle(double size, Color color, {FontWeight? weight}) =>
      TextStyle(
        fontFamily: mono ?? 'monospace',
        fontSize: size,
        color: color,
        fontWeight: weight,
      );
}

/// A wallpaper filling its box, with the palette gradient beneath it.
///
/// The gradient is what shows while the image decodes, and for good when it
/// fails, so a slow CDN or a missing asset never leaves a black hole.
class SetupWallpaper extends StatelessWidget {
  const SetupWallpaper({
    super.key,
    required this.palette,
    this.image,
    this.opacity = 1,
  });

  final ThemePalette palette;
  final ImageProvider? image;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bgTop, palette.bgBottom],
        ),
      ),
    );
    final img = image;
    if (img == null) return gradient;

    // Decoded at screen width, not at the source's size. A distro wallpaper is
    // often 4K, and decoding it full size for a 1080px screen costs tens of MB
    // of image cache on the first screen anyone sees.
    final mq = MediaQuery.of(context);
    final target = (mq.size.width * mq.devicePixelRatio).round();

    return Stack(
      fit: StackFit.expand,
      children: [
        gradient,
        Opacity(
          opacity: opacity,
          child: Image(
            image: ResizeImage(img, width: target, allowUpscaling: false),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            frameBuilder: (_, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 260),
                    child: child,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The small letter-spaced label above a heading.
class SetupKicker extends StatelessWidget {
  const SetupKicker(this.text, {super.key, required this.ink});

  final String text;
  final SetupInk ink;

  @override
  Widget build(BuildContext context) => ink.isConfig
      ? _lookKicker(this)
      : Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          letterSpacing: 1,
          fontWeight: FontWeight.w500,
          color: ink.textMuted,
        ),
      );
}

/// The one filled button a setup screen has.
///
/// [onPressed] null draws the disabled outline used for paid previews, so a
/// screen never swaps widgets to say "not available": the button stays where
/// the thumb expects it and changes what it says.
class SetupPrimaryButton extends StatelessWidget {
  const SetupPrimaryButton({
    super.key,
    required this.label,
    required this.ink,
    required this.onPressed,
  });

  final String label;
  final SetupInk ink;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (ink.look != null) return _lookPrimary(this);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: enabled ? ink.accent : const Color(0x0FFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: enabled ? BorderSide.none : BorderSide(color: ink.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 54,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: enabled ? 16 : 14,
                  fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                  color: enabled ? ink.onAccent : ink.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet text action under the primary button.
class SetupLink extends StatelessWidget {
  const SetupLink({
    super.key,
    required this.label,
    required this.ink,
    required this.onPressed,
  });

  final String label;
  final SetupInk ink;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: ink.text,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 14),
        ),
        child: Text(label, textAlign: TextAlign.center),
      );
}

/// A square outlined icon button, used for the pager arrows.
class SetupIconButton extends StatelessWidget {
  const SetupIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.ink,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final SetupInk ink;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ink.look != null
      ? _lookIconButton(this)
      : Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: ink.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, size: 20, color: ink.text),
            ),
          ),
        ),
      );
}

/// A pill over the wallpaper: the language chip, the Free and Preview tags.
class SetupPill extends StatelessWidget {
  const SetupPill({
    super.key,
    required this.label,
    required this.ink,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final SetupInk ink;
  final IconData? leading;
  final IconData? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (ink.look != null) return _lookPill(this);
    final body = Container(
      height: onTap == null ? 28 : 36,
      padding: EdgeInsets.symmetric(horizontal: onTap == null ? 12 : 14),
      decoration: BoxDecoration(
        color: ink.scrim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: 12, color: ink.text),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: onTap == null ? 12 : 13,
              fontWeight: FontWeight.w500,
              color: ink.text,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Icon(trailing, size: 14, color: ink.text),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// The bottom panel every full-bleed setup screen ends in.
///
/// Flat scrim rather than a gradient wash: the wallpaper stays fully legible
/// above the panel, and the panel reads as one surface below it.
class SetupBottomPanel extends StatelessWidget {
  const SetupBottomPanel({super.key, required this.ink, required this.child});

  final SetupInk ink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ink.look != null) return _lookPanel(this, context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: ink.scrim,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 20, 18 + bottom),
        child: child,
      ),
    );
  }
}

/// The drag handle at the top of a setup sheet.
class SetupGrip extends StatelessWidget {
  const SetupGrip({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: const Color(0x4DFFFFFF),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Kicker, title and optional subtitle, the head of every setup sheet.
class SetupHeading extends StatelessWidget {
  const SetupHeading({
    super.key,
    required this.ink,
    required this.kicker,
    required this.title,
    this.subtitle,
  });

  final SetupInk ink;
  final String kicker;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ink.isConfig
      ? _lookHeading(this)
      : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SetupKicker(kicker, ink: ink),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 24,
              height: 1.15,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w700,
              color: ink.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 13, height: 1.4, color: ink.textMuted),
            ),
          ],
        ],
      );
}

/// One row of a single-choice list: title, optional subtitle, a tick when on.
///
/// Hairline above every row, and a radio role for screen readers, so a list of
/// these reads as one choice rather than as a stack of buttons.
class SetupChoiceRow extends StatelessWidget {
  const SetupChoiceRow({
    super.key,
    required this.ink,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final SetupInk ink;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ink.look != null
      ? _lookChoice(this)
      : Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: ink.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 15, color: ink.text),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style:
                              TextStyle(fontSize: 12.5, color: ink.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 20, color: ink.accent),
              ],
            ),
          ),
        ),
      );
}

/// A settings row that opens a sheet: label on the left, current value and a
/// chevron on the right.
class SetupValueRow extends StatelessWidget {
  const SetupValueRow({
    super.key,
    required this.ink,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final SetupInk ink;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ink.isConfig
      ? _lookValue(this)
      : Semantics(
        button: true,
        label: '$title, $value',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: ink.line)),
            ),
            child: Row(
              children: [
                Text(title, style: TextStyle(fontSize: 15, color: ink.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: ink.textMuted),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: ink.textMuted),
              ],
            ),
          ),
        ),
      );
}

/// A row with a switch, for opt-out lists such as suggested folders.
class SetupSwitchRow extends StatelessWidget {
  const SetupSwitchRow({
    super.key,
    required this.ink,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
  });

  final SetupInk ink;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ink.look != null
      ? _lookSwitch(this)
      : MergeSemantics(
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: ink.line)),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: TextStyle(fontSize: 15, color: ink.text)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12.5, color: ink.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  thumbColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? ink.onAccent
                        : ink.textMuted,
                  ),
                  trackColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? ink.accent
                        : const Color(0x2EFFFFFF),
                  ),
                  trackOutlineColor:
                      const WidgetStatePropertyAll(Colors.transparent),
                ),
              ],
            ),
          ),
        ),
      );
}

/// A row of equal segments, one selected. Used for column counts and badges.
class SetupSegmented<T> extends StatelessWidget {
  const SetupSegmented({
    super.key,
    required this.ink,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final SetupInk ink;

  /// Value to label, in display order.
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ink.look != null
      ? _lookSegmented<T>(this)
      : Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0x40000000),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            for (final e in options.entries)
              Expanded(
                child: Semantics(
                  inMutuallyExclusiveGroup: true,
                  checked: e.key == selected,
                  button: true,
                  label: e.value,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            e.key == selected ? ink.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: e.key == selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: e.key == selected ? ink.onAccent : ink.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}


// ─── THE SAME SETUP, IN THE CHOSEN DISTRO'S LOOK ────────────────────────────
//
// Each primitive above routes here when its ink carries a [SettingsLook]. The
// layout of every step stays as it is; what changes is what a distro's own
// installer and settings would draw: GNOME's pill buttons, KDE's square ones
// and radio marks, Xfce's checkboxes, iOS's green switches, and on a WM or the
// terminal a config file's `[x]`, `true` and `< Next >`.

Widget _lookKicker(SetupKicker w) => Text(
      '# ${w.text.toLowerCase()}',
      style: w.ink.monoStyle(11.5, w.ink.textMuted),
    );

Widget _lookHeading(SetupHeading w) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _lookKicker(SetupKicker(w.kicker, ink: w.ink)),
        const SizedBox(height: 6),
        Text(
          w.title,
          style: w.ink.monoStyle(20, w.ink.text, weight: FontWeight.w700),
        ),
        if (w.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(w.subtitle!, style: w.ink.monoStyle(12, w.ink.textMuted)),
        ],
      ],
    );

Widget _lookPrimary(SetupPrimaryButton w) {
  final ink = w.ink;
  final enabled = w.onPressed != null;
  final form = ink.look == SettingsLook.form;
  final fill = !enabled
      ? const Color(0x0FFFFFFF)
      : form
          ? ink.accent.withValues(alpha: 0.32)
          : ink.accent;
  final ink2 = !enabled
      ? ink.textMuted
      : form
          ? ink.text
          : ink.onAccent;
  final label = ink.isConfig ? '< ${w.label} >' : w.label;
  return Semantics(
    button: true,
    enabled: enabled,
    label: w.label,
    excludeSemantics: true,
    child: Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ink.buttonRadius),
        side: !enabled || form
            ? BorderSide(color: form && enabled ? ink.accent : ink.line)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: w.onPressed,
        child: SizedBox(
          height: ink.isConfig ? 46 : 52,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: ink.isConfig
                  ? ink.monoStyle(15, ink2, weight: FontWeight.w700)
                  : TextStyle(
                      fontSize: enabled ? 16 : 14,
                      fontWeight:
                          enabled ? FontWeight.w600 : FontWeight.w500,
                      color: ink2,
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _lookIconButton(SetupIconButton w) => Tooltip(
      message: w.tooltip,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(w.ink.buttonRadius),
          side: BorderSide(color: w.ink.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: w.onPressed,
          child: SizedBox(
            width: 52,
            height: w.ink.isConfig ? 46 : 52,
            child: Icon(w.icon, size: 20, color: w.ink.text),
          ),
        ),
      ),
    );

Widget _lookPill(SetupPill w) {
  final ink = w.ink;
  final r = switch (ink.look) {
    SettingsLook.config => 0.0,
    SettingsLook.form || SettingsLook.dialog => 4.0,
    SettingsLook.cinnamon => 6.0,
    _ => 18.0,
  };
  final body = Container(
    height: w.onTap == null ? 28 : 36,
    padding: EdgeInsets.symmetric(horizontal: w.onTap == null ? 12 : 14),
    decoration: BoxDecoration(
      color: ink.scrim.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: ink.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (w.leading != null) ...[
          Icon(w.leading, size: 12, color: ink.text),
          const SizedBox(width: 6),
        ],
        Text(
          w.label,
          style: ink.isConfig
              ? ink.monoStyle(12, ink.text)
              : TextStyle(
                  fontSize: w.onTap == null ? 12 : 13,
                  fontWeight: FontWeight.w500,
                  color: ink.text,
                ),
        ),
        if (w.trailing != null) ...[
          const SizedBox(width: 6),
          Icon(w.trailing, size: 14, color: ink.text),
        ],
      ],
    ),
  );
  if (w.onTap == null) return body;
  return Semantics(
    button: true,
    label: w.semanticLabel ?? w.label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: w.onTap,
      child: body,
    ),
  );
}

Widget _lookPanel(SetupBottomPanel w, BuildContext context) {
  final ink = w.ink;
  final bottom = MediaQuery.paddingOf(context).bottom;
  final radius = switch (ink.look) {
    SettingsLook.grouped => 28.0,
    SettingsLook.boxed => 24.0,
    SettingsLook.cinnamon => 10.0,
    _ => 0.0,
  };
  final edge = switch (ink.look) {
    SettingsLook.config => BorderSide(color: ink.text, width: 2),
    SettingsLook.form || SettingsLook.dialog => BorderSide(color: ink.line),
    _ => BorderSide.none,
  };
  return DecoratedBox(
    decoration: BoxDecoration(
      color: ink.scrim,
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      border: Border(top: edge),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 18 + bottom),
      child: w.child,
    ),
  );
}

Widget _rowFrame({
  required SetupInk ink,
  required VoidCallback onTap,
  required String title,
  String? subtitle,
  Widget? leading,
  required Widget trailing,
  double minHeight = 56,
}) {
  final config = ink.isConfig;
  return InkWell(
    onTap: onTap,
    child: Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ink.line)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: config
                      ? ink.monoStyle(14, ink.text)
                      : TextStyle(fontSize: 15, color: ink.text),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: config
                        ? ink.monoStyle(11.5, ink.textMuted)
                        : TextStyle(fontSize: 12.5, color: ink.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    ),
  );
}

Widget _lookChoice(SetupChoiceRow w) {
  final ink = w.ink;
  final Widget mark = switch (ink.look) {
    SettingsLook.config => Text(
        w.selected ? '[x]' : '[ ]',
        style: ink.monoStyle(14, w.selected ? ink.accent : ink.textMuted),
      ),
    SettingsLook.form || SettingsLook.dialog => Icon(
        w.selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        size: 20,
        color: w.selected ? ink.accent : ink.textMuted,
      ),
    _ => w.selected
        ? Icon(Icons.check_rounded, size: 20, color: ink.accent)
        : const SizedBox(width: 20),
  };
  return Semantics(
    inMutuallyExclusiveGroup: true,
    checked: w.selected,
    button: true,
    child: _rowFrame(
      ink: ink,
      onTap: w.onTap,
      title: w.title,
      subtitle: w.subtitle,
      trailing: mark,
    ),
  );
}

Widget _lookValue(SetupValueRow w) => Semantics(
      button: true,
      label: '${w.title}, ${w.value}',
      excludeSemantics: true,
      child: _rowFrame(
        ink: w.ink,
        onTap: w.onTap,
        title: configKey(w.title),
        trailing: Text(
          '= ${w.value}',
          style: w.ink.monoStyle(13.5, w.ink.accent),
        ),
      ),
    );

Widget _lookSwitch(SetupSwitchRow w) {
  final ink = w.ink;
  final Widget control = switch (ink.look) {
    SettingsLook.config => Text(
        w.value ? 'true' : 'false',
        style: ink.monoStyle(14, w.value ? ink.accent : ink.textMuted),
      ),
    SettingsLook.form || SettingsLook.dialog => Checkbox(
        value: w.value,
        onChanged: (v) => w.onChanged(v ?? false),
        activeColor: ink.accent,
        checkColor: ink.onAccent,
        side: BorderSide(color: ink.textMuted, width: 1.4),
      ),
    _ => Switch(
        value: w.value,
        onChanged: w.onChanged,
        thumbColor: WidgetStatePropertyAll(
          ink.look == SettingsLook.grouped ? Colors.white : ink.onAccent,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (ink.look == SettingsLook.grouped
                  ? const Color(0xFF34C759)
                  : ink.accent)
              : const Color(0x2EFFFFFF),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
  };
  return MergeSemantics(
    child: _rowFrame(
      ink: ink,
      onTap: () => w.onChanged(!w.value),
      title: ink.isConfig ? configKey(w.title) : w.title,
      subtitle: w.subtitle,
      leading: w.leading,
      trailing: control,
      minHeight: 60,
    ),
  );
}

Widget _lookSegmented<T>(SetupSegmented<T> w) {
  final ink = w.ink;
  final joined = switch (ink.look) {
    SettingsLook.form ||
    SettingsLook.dialog ||
    SettingsLook.cinnamon ||
    SettingsLook.config =>
      true,
    _ => false,
  };
  final r = ink.buttonRadius.clamp(0, 13).toDouble();
  final entries = w.options.entries.toList();
  return Container(
    padding: joined ? EdgeInsets.zero : const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: joined ? null : const Color(0x40000000),
      border: joined ? Border.all(color: ink.line) : null,
      borderRadius: BorderRadius.circular(r),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        for (var i = 0; i < entries.length; i++)
          Expanded(
            child: Semantics(
              inMutuallyExclusiveGroup: true,
              checked: entries[i].key == w.selected,
              button: true,
              label: entries[i].value,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => w.onChanged(entries[i].key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: entries[i].key == w.selected
                        ? (ink.look == SettingsLook.form
                            ? ink.accent.withValues(alpha: 0.32)
                            : ink.accent)
                        : Colors.transparent,
                    borderRadius:
                        joined ? null : BorderRadius.circular(r - 3),
                    border: joined && i > 0
                        ? Border(left: BorderSide(color: ink.line))
                        : null,
                  ),
                  child: Text(
                    entries[i].value,
                    style: ink.isConfig
                        ? ink.monoStyle(
                            13.5,
                            entries[i].key == w.selected
                                ? ink.onAccent
                                : ink.text,
                          )
                        : TextStyle(
                            fontSize: 14,
                            fontWeight: entries[i].key == w.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: entries[i].key == w.selected &&
                                    ink.look != SettingsLook.form
                                ? ink.onAccent
                                : ink.text,
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
