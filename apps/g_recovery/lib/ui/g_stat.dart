import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// A figure over its label, as in a row of stats.
class GStat extends StatelessWidget {
  const GStat({
    required this.label,
    required this.value,
    super.key,
    this.unit,
    this.tone,
    this.align = CrossAxisAlignment.start,
  });

  final String label;

  /// Nothing is drawn while this is null, so a missing reading leaves no gap.
  final String? value;
  final String? unit;
  final Color? tone;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    if (value == null) return const SizedBox.shrink();
    final TextStyle figure = g.figures(g.headline(color: tone ?? g.text));
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text.rich(
          TextSpan(
            text: value,
            style: figure,
            children: <InlineSpan>[
              if (unit != null)
                TextSpan(text: unit, style: g.figures(g.footnote())),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: g.footnote()),
      ],
    );
  }
}

/// A section heading above a card: sentence case, small and muted, inset to
/// line up with the text inside the card below.
class GOverline extends StatelessWidget {
  const GOverline(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: GDesign.space16,
        top: GDesign.space12,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _sentence(label),
              style: g.footnote(weight: FontWeight.w600),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// Headings were written in capitals for the old style; this lowers all
  /// but the first letter of a heading that arrives entirely in capitals.
  static String _sentence(String text) {
    if (text.isEmpty || text != text.toUpperCase()) return text;
    return text[0] + text.substring(1).toLowerCase();
  }
}
