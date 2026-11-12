import 'package:flutter/widgets.dart';

/// An app or folder name, shrunk to fit its lines rather than cut off.
///
/// ─── NO ELLIPSIS ON A NAME ──────────────────────────────────────────────────
///
/// Home and folder cells are narrow, and with `TextOverflow.ellipsis` names
/// like "Productivity & Finance" ended in "…". A name is how a person finds
/// the one thing they came for, so a truncated name is the one thing these
/// surfaces must not show. The label keeps its line budget (the box the grid
/// reserved still holds) and steps its size down until the whole name fits:
/// within [maxLines], and with no single word wider than the box, because
/// Flutter otherwise breaks an overlong word mid-letters ("Instash" / "ot").
/// Past [minFontSize], which only a very long name reaches, it clips at the
/// edge with no ellipsis character.
class FitLabel extends StatelessWidget {
  const FitLabel(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 1,
    this.minFontSize = 9,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final double minFontSize;
  final TextAlign textAlign;

  static const _step = 0.5;

  // ─── MEASURED ONCE PER NAME AND WIDTH ─────────────────────────────────────
  //
  // Finding the size takes several TextPainter layouts per label, and a home
  // page rebuilds every label on a drag, a theme emit or a badge change. The
  // answer depends only on the inputs below, so it is remembered. Bounded,
  // oldest dropped first, so a phone with hundreds of apps cannot grow it.
  static final _sizes = <String, double>{};
  static const _cacheMax = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        var size = style.fontSize ?? 12;
        if (box.maxWidth.isFinite) {
          final key = '$text|${box.maxWidth.toStringAsFixed(1)}|$maxLines|'
              '$size|$minFontSize|${style.fontFamily}|${style.fontWeight}|'
              '${style.height}|${scaler.scale(1)}|$direction';
          final known = _sizes[key];
          if (known != null) {
            size = known;
          } else {
            while (size > minFontSize) {
              if (_fits(size, box.maxWidth, scaler, direction)) break;
              size -= _step;
            }
            if (_sizes.length >= _cacheMax) _sizes.remove(_sizes.keys.first);
            _sizes[key] = size;
          }
        }
        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.clip,
          textAlign: textAlign,
          style: style.copyWith(fontSize: size),
        );
      },
    );
  }

  bool _fits(
    double size,
    double width,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final sized = style.copyWith(fontSize: size);
    final whole = TextPainter(
      text: TextSpan(text: text, style: sized),
      maxLines: maxLines,
      textAlign: textAlign,
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final withinLines = !whole.didExceedMaxLines;
    whole.dispose();
    if (!withinLines) return false;

    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final one = TextPainter(
        text: TextSpan(text: word, style: sized),
        maxLines: 1,
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final wide = one.width > width;
      one.dispose();
      if (wide) return false;
    }
    return true;
  }
}
