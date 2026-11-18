import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';

/// Full-width row with a hairline underneath. Replaces cards inside lists.
///
/// At least [GDesign.rowMinHeight] tall. A chevron appears only when the row
/// opens something.
class EdgeRow extends StatelessWidget {
  const EdgeRow({
    required this.title,
    super.key,
    this.subtitle,
    this.value,
    this.valueTone,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.chevron = true,
    this.divider = true,
  });

  final String title;
  final String? subtitle;

  /// A short measured value, drawn in the number face.
  final String? value;
  final Color? valueTone;
  final Widget? leading;

  /// A control such as a switch. Shown after [value].
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Fills the row with the accent wash while it is part of a selection.
  final bool selected;
  final bool chevron;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    final Widget body = Container(
      constraints: const BoxConstraints(minHeight: GDesign.rowMinHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: GDesign.gutter,
        vertical: GDesign.space8,
      ),
      decoration: BoxDecoration(
        color: selected ? g.accentSoft : null,
        border: divider
            ? Border(bottom: BorderSide(color: g.hairline))
            : null,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: g.sans.copyWith(
                    fontSize: GDesign.body,
                    height: 20 / 15,
                    color: g.text,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: g.sans.copyWith(
                      fontSize: GDesign.caption,
                      height: 18 / 13,
                      color: g.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(width: GDesign.space12),
            Text(
              value!,
              maxLines: 1,
              softWrap: false,
              style: g.mono.copyWith(
                fontSize: 14,
                color: valueTone ?? g.text,
              ),
            ),
          ],
          if (trailing != null) ...<Widget>[
            const SizedBox(width: GDesign.space12),
            trailing!,
          ],
          if (chevron && onTap != null) ...<Widget>[
            const SizedBox(width: GDesign.space8),
            Icon(
              rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              size: 18,
              color: g.muted,
            ),
          ],
        ],
      ),
    );

    if (onTap == null && onLongPress == null) return body;
    return Semantics(
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, onLongPress: onLongPress, child: body),
      ),
    );
  }
}

/// Caps label that opens a group of rows on a sheet.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;

  /// Optional count or tag at the far end of the line.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.gutter,
        GDesign.gutter,
        GDesign.space8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text.toUpperCase(), style: g.label()),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
