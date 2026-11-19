import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import '../../../ui/g_card.dart';

/// The frame every Device detail page shares: a large title, one hero
/// visual on its own card, then grouped facts.
///
/// Anything that needs a sentence of explanation goes behind [onInfo] as a
/// sheet, so the page itself stays visual plus labels.
class DeviceDetail extends StatelessWidget {
  const DeviceDetail({
    required this.title,
    required this.sections,
    super.key,
    this.hero,
    this.onInfo,
    this.backLabel,
  });

  final String title;

  /// The one big visual, drawn on a card under the title.
  final Widget? hero;

  /// Grouped sections under the hero, spaced evenly.
  final List<Widget> sections;

  /// Opens the page's explanation sheet.
  final VoidCallback? onInfo;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return GGroundScope(
      grouped: true,
      child: LargeTitlePage(
        title: title,
        grouped: true,
        backLabel: backLabel ?? context.s('Device'),
        onBack: () => Navigator.of(context).maybePop(),
        actions: <Widget>[
          if (onInfo != null)
            NavAction.icon(
              icon: GIcons.info,
              semanticLabel: context.s('About this page'),
              onTap: onInfo,
            ),
        ],
        slivers: <Widget>[
          if (hero != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  GDesign.space8,
                  GDesign.gutter,
                  0,
                ),
                child: Reveal(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: g.card,
                      borderRadius: BorderRadius.circular(GDesign.cardRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(GDesign.space16),
                      child: hero,
                    ),
                  ),
                ),
              ),
            ),
          for (final Widget section in sections)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: GDesign.space32),
                child: section,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space48)),
        ],
      ),
    );
  }
}

/// Label and value rows in a grouped section. Rows without a value are left
/// out, and the section disappears when none has one.
class FactSection extends StatelessWidget {
  const FactSection({required this.rows, super.key, this.header, this.footer});

  final String? header;
  final String? footer;
  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> present = <(String, String)>[
      for (final (String label, String? value) in rows)
        if (value != null && value.isNotEmpty) (label, value),
    ];
    if (present.isEmpty) return const SizedBox.shrink();
    return GroupedSection(
      header: header,
      footer: footer,
      children: <Widget>[
        for (final (String label, String value) in present)
          ListRow(title: label, detail: value),
      ],
    );
  }
}

/// Yes or no features as rows, with a tick or a dash.
class FlagSection extends StatelessWidget {
  const FlagSection({required this.flags, super.key, this.header});

  final String? header;
  final List<(String, bool)> flags;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return GroupedSection(
      header: header,
      children: <Widget>[
        for (final (String label, bool on) in flags)
          ListRow(
            title: label,
            trailing: Icon(
              on ? GIcons.check : GIcons.close,
              size: 18,
              color: on ? g.accentText : g.faint,
            ),
          ),
      ],
    );
  }
}

/// A reading the phone does not share: one row, with the reason a tap away.
class MissingSection extends StatelessWidget {
  const MissingSection({
    required this.title,
    required this.reason,
    super.key,
    this.header,
  });

  final String title;
  final String reason;
  final String? header;

  @override
  Widget build(BuildContext context) => GroupedSection(
    header: header,
    children: <Widget>[
      ListRow(
        icon: GIcons.eyeOff,
        title: title,
        subtitle: context.s('Not shared by this phone'),
        onTap: () => showDeviceNote(context, title, <String>[reason]),
      ),
    ],
  );
}

/// Up to four large figures in a row, each with a small label under it.
class HeroFigures extends StatelessWidget {
  const HeroFigures({required this.figures, super.key});

  /// Value and label pairs. Pairs with no value are left out.
  final List<(String?, String)> figures;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<(String, String)> present = <(String, String)>[
      for (final (String? value, String label) in figures)
        if (value != null) (value, label),
    ];
    if (present.isEmpty) return const SizedBox.shrink();
    return Row(
      children: <Widget>[
        for (final (String value, String label) in present)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Long values shrink to fit rather than wrap.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value, style: g.figures(g.headline())),
                ),
                const SizedBox(height: 2),
                Text(label, style: g.footnote()),
              ],
            ),
          ),
      ],
    );
  }
}

/// A short explanation sheet: a heading and a few plain paragraphs.
Future<void> showDeviceNote(
  BuildContext context,
  String title,
  List<String> lines,
) => presentSheet<void>(
  context: context,
  builder: (BuildContext sheet) {
    final GDesignTheme g = GDesignTheme.of(sheet);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        GDesign.space24,
      ),
      children: <Widget>[
        Text(title, style: g.headline()),
        for (final String line in lines) ...<Widget>[
          const SizedBox(height: GDesign.space12),
          Text(line, style: g.body(color: g.muted)),
        ],
      ],
    );
  },
);

/// A centred spinner with one label, while a reading arrives.
class DeviceLoading extends StatelessWidget {
  const DeviceLoading({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GDesign.space32),
      child: Column(
        children: <Widget>[
          const CircularProgressIndicator.adaptive(),
          const SizedBox(height: GDesign.space12),
          Text(label, style: g.footnote()),
        ],
      ),
    );
  }
}
