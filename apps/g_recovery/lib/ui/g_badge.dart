import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// What a badge is saying. Colour means state only: the accent marks Pro
/// and live states, everything else is neutral.
enum GBadgeTone { full, partial, none, live, pro }

/// A small sentence-case label on a soft fill, such as "Measured" or "Pro".
class GBadge extends StatelessWidget {
  const GBadge({required this.label, super.key, this.tone = GBadgeTone.none});

  const GBadge.full(String label, {Key? key})
    : this(label: label, key: key, tone: GBadgeTone.full);

  const GBadge.partial(String label, {Key? key})
    : this(label: label, key: key, tone: GBadgeTone.partial);

  const GBadge.live(String label, {Key? key})
    : this(label: label, key: key, tone: GBadgeTone.live);

  final String label;
  final GBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool accented = tone == GBadgeTone.pro || tone == GBadgeTone.live;
    final Color ink = accented ? g.accentText : g.muted;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: GDesign.space8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accented
            ? g.accent.withValues(alpha: g.isDark ? 0.18 : 0.10)
            : (g.isDark ? g.hairline : g.fill),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _sentence(label),
        maxLines: 1,
        style: g.footnote(color: ink, weight: FontWeight.w600),
      ),
    );
  }

  /// Labels were written in capitals for the old style.
  static String _sentence(String text) {
    if (text.isEmpty || text != text.toUpperCase()) return text;
    return text[0] + text.substring(1).toLowerCase();
  }
}
