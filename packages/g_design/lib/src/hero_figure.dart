import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';

enum HeroSize { large, display, compact }

/// The one big measured number on a screen.
///
/// A caps label above, the figure with an optional unit, and an optional one
/// line caption. The figure shrinks to fit a narrow phone rather than wrap.
///
/// [value] is null while nothing has been measured: the label and caption
/// still show, and no placeholder number is drawn in its place.
class HeroFigure extends StatelessWidget {
  const HeroFigure({
    required this.label,
    super.key,
    this.value,
    this.unit,
    this.caption,
    this.tone,
    this.labelTrailing,
    this.size = HeroSize.display,
  });

  final String label;
  final String? value;
  final String? unit;
  final String? caption;

  /// Colour for the figure. Only set it when the number is a state.
  final Color? tone;

  /// Optional marker after the label, such as a [HeaderTag].
  final Widget? labelTrailing;
  final HeroSize size;

  double get _points => switch (size) {
        HeroSize.large => GDesign.displayLarge,
        HeroSize.display => GDesign.display,
        HeroSize.compact => GDesign.compact,
      };

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double points = _points;

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(child: Text(label.toUpperCase(), style: g.label())),
              if (labelTrailing != null) ...<Widget>[
                const SizedBox(width: GDesign.space8),
                labelTrailing!,
              ],
            ],
          ),
          if (value != null) ...<Widget>[
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: value!),
                    if (unit != null)
                      TextSpan(
                        text: ' ${unit!}',
                        style: TextStyle(
                          fontSize: GDesign.title,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          color: g.muted,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                softWrap: false,
                style: g.sans.copyWith(
                  fontSize: points,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.02 * points,
                  color: tone ?? g.text,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
          if (caption != null) ...<Widget>[
            const SizedBox(height: GDesign.space8),
            Text(
              caption!,
              style: g.sans.copyWith(
                fontSize: GDesign.body,
                height: 22 / 15,
                color: g.text,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
