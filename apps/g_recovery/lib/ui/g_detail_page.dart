import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

import 'g_card.dart';

/// A pushed detail page: large title collapsing into the nav bar, grey
/// grouped ground, and the page's cards as white sections.
///
/// [hue] and [icon] are kept so existing call sites compile; the design
/// language has one accent and no title glyphs, so neither is drawn.
class GDetailPage extends StatelessWidget {
  const GDetailPage({
    required this.hue,
    required this.icon,
    required this.title,
    required this.children,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final Color hue;
  final IconData icon;
  final String title;

  /// One line under the large title.
  final String? subtitle;

  /// Controls placed in the nav bar.
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GDetailSliverPage(
      hue: hue,
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      tailSpace: GDesign.space32,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          sliver: SliverList.list(children: children),
        ),
      ],
    );
  }
}

/// The sliver form of [GDetailPage], for long or lazily built lists, with an
/// optional [footer] pinned above the gesture area.
class GDetailSliverPage extends StatelessWidget {
  const GDetailSliverPage({
    required this.hue,
    required this.icon,
    required this.title,
    required this.slivers,
    super.key,
    this.subtitle,
    this.trailing,
    this.footer,
    this.tailSpace = 120,
  });

  final Color hue;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> slivers;

  /// Pinned to the bottom, over a solid strip so content never shows
  /// through the controls.
  final Widget? footer;

  /// Space after the last sliver so it can scroll clear of the tab bar or
  /// the footer.
  final double tailSpace;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return GGroundScope(
      grouped: true,
      child: LargeTitlePage(
        title: title,
        grouped: true,
        onBack: () => Navigator.of(context).maybePop(),
        actions: <Widget>[?trailing],
        bottom: footer == null
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: g.grouped,
                  border: Border(
                    top: BorderSide(color: g.hairline, width: 0.5),
                  ),
                ),
                child: SafeArea(top: false, child: footer!),
              ),
        slivers: <Widget>[
          if (subtitle != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  0,
                  GDesign.gutter,
                  GDesign.space16,
                ),
                child: Text(subtitle!, style: g.figures(g.footnote())),
              ),
            ),
          ...slivers,
          SliverToBoxAdapter(child: SizedBox(height: tailSpace)),
        ],
      ),
    );
  }
}

/// Label and value rows inside one card. Rows with no value are left out,
/// and the card disappears when none has one.
class GSpecCard extends StatelessWidget {
  const GSpecCard({required this.rows, super.key});

  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    if (!SpecRows.any(rows)) return const SizedBox.shrink();
    return GCard(
      padding: const EdgeInsetsDirectional.only(start: GDesign.space16),
      child: SpecRows(rows: rows),
    );
  }
}

/// Yes or no facts, one per row, with a check for yes.
class GFlagCard extends StatelessWidget {
  const GFlagCard({required this.flags, super.key});

  final List<(String, bool)> flags;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    if (flags.isEmpty) return const SizedBox.shrink();
    return GCard(
      padding: const EdgeInsetsDirectional.only(start: GDesign.space16),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < flags.length; i++)
            _RowFrame(
              last: i == flags.length - 1,
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(flags[i].$1, style: g.body())),
                  const SizedBox(width: GDesign.space12),
                  if (flags[i].$2)
                    Icon(GIcons.check, size: 18, color: g.accentText)
                  else
                    Text('No', style: g.body(color: g.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One part of a [GStackBar].
@immutable
class GStackPart {
  const GStackPart({required this.bytes, required this.colour});

  final int bytes;
  final Color colour;
}

/// A slim bar split into parts by size.
class GStackBar extends StatelessWidget {
  const GStackBar({required this.parts, super.key, this.height = 8});

  final List<GStackPart> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final List<GStackPart> present = <GStackPart>[
      for (final GStackPart part in parts)
        if (part.bytes > 0) part,
    ];
    if (present.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < present.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: present[i].bytes,
                child: ColoredBox(color: present[i].colour),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The legend under a [GStackBar].
class GStackKeys extends StatelessWidget {
  const GStackKeys({required this.entries, super.key});

  final List<(String, Color)> entries;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: GDesign.space16,
      runSpacing: GDesign.space4,
      children: <Widget>[
        for (final (String label, Color hue) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label, style: g.footnote()),
            ],
          ),
      ],
    );
  }
}

/// One row of [GCoreBars].
@immutable
class GCoreBar {
  const GCoreBar({
    required this.label,
    required this.colour,
    this.value,
    this.fraction,
  });

  final String label;

  /// Kept for call sites; bars draw in the accent.
  final Color colour;
  final double? fraction;
  final String? value;
}

/// One bar per core: label, how busy or how fast, and the figure.
class GCoreBars extends StatelessWidget {
  const GCoreBars({required this.cores, super.key});

  final List<GCoreBar> cores;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    if (cores.isEmpty) return const SizedBox.shrink();
    final TextStyle small = g.figures(g.footnote());

    return Column(
      children: <Widget>[
        for (int i = 0; i < cores.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: GDesign.space8),
          Row(
            children: <Widget>[
              SizedBox(
                width: 32,
                child: Text(cores[i].label, maxLines: 1, style: small),
              ),
              const SizedBox(width: GDesign.space8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 8,
                    color: g.isDark ? g.hairline : g.fill,
                    alignment: AlignmentDirectional.centerStart,
                    child: cores[i].fraction == null
                        ? null
                        : FractionallySizedBox(
                            widthFactor: cores[i].fraction!.clamp(0.0, 1.0),
                            child: AnimatedContainer(
                              duration: GDesign.motion(context, GDesign.fast),
                              decoration: BoxDecoration(
                                color: g.accent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: GDesign.space8),
              SizedBox(
                width: 72,
                child: Text(
                  cores[i].value ?? '',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Something this phone would not tell the app, and why, as a quiet row.
class GMissNote extends StatelessWidget {
  const GMissNote({
    required this.text,
    super.key,
    this.onTap,
    this.icon = Icons.lock_outline_rounded,
  });

  final String text;
  final VoidCallback? onTap;

  /// Kept for call sites; the row uses the lock glyph.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return GCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: GDesign.space16,
        vertical: GDesign.space12,
      ),
      child: Row(
        children: <Widget>[
          Icon(GIcons.lock, size: 18, color: g.muted),
          const SizedBox(width: GDesign.space12),
          Expanded(child: Text(text, style: g.footnote())),
          if (onTap != null) Icon(GIcons.forward, size: 18, color: g.faint),
        ],
      ),
    );
  }
}

/// A chart in a card, with an optional caption or header and axis labels.
class GChartCard extends StatelessWidget {
  const GChartCard({
    required this.child,
    super.key,
    this.caption,
    this.header,
    this.axis = const <String>[],
  });

  final String? caption;
  final Widget? header;
  final Widget child;
  final List<String> axis;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return GCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (header != null) ...<Widget>[
            header!,
            const SizedBox(height: GDesign.space8),
          ] else if (caption != null) ...<Widget>[
            Text(
              caption!,
              style: g.footnote(color: g.text, weight: FontWeight.w600),
            ),
            const SizedBox(height: GDesign.space12),
          ],
          child,
          if (axis.isNotEmpty) ...<Widget>[
            const SizedBox(height: GDesign.space8),
            Row(
              mainAxisAlignment: axis.length == 1
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: <Widget>[
                for (final String label in axis)
                  Text(label, style: g.figures(g.footnote())),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Label on the left, value on the right, a hairline between rows.
class SpecRows extends StatelessWidget {
  const SpecRows({required this.rows, super.key});

  final List<(String, String?)> rows;

  static bool any(List<(String, String?)> rows) {
    for (final (String _, String? value) in rows) {
      if (value != null && value.isNotEmpty) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<(String, String)> present = <(String, String)>[
      for (final (String label, String? value) in rows)
        if (value != null && value.isNotEmpty) (label, value),
    ];
    if (present.isEmpty) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        for (int i = 0; i < present.length; i++)
          _RowFrame(
            last: i == present.length - 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 5, child: Text(present[i].$1, style: g.body())),
                const SizedBox(width: GDesign.space12),
                Expanded(
                  flex: 4,
                  child: Text(
                    present[i].$2,
                    textAlign: TextAlign.end,
                    style: g.figures(g.body(color: g.muted)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A 52 dp row with a hairline under it, inset from the leading edge, as in
/// a grouped list.
class _RowFrame extends StatelessWidget {
  const _RowFrame({required this.child, required this.last});

  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: GDesign.rowMinHeight),
      padding: const EdgeInsetsDirectional.fromSTEB(
        0,
        GDesign.space12,
        GDesign.space16,
        GDesign.space12,
      ),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: g.hairline, width: 0.5)),
      ),
      child: child,
    );
  }
}
