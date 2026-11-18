import 'package:flutter/material.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';

/// Small floating fact, such as "12 leave Trash in 2 days".
///
/// Glass over content, solid (the raised colour) on a sheet. When tappable it keeps a 48 dp hit
/// area around its 28 dp body.
class FloatChip extends StatelessWidget {
  const FloatChip({
    required this.label,
    super.key,
    this.tone,
    this.onTap,
    this.solid = false,
  });

  final String label;

  /// Text colour. Only set it when the chip states something.
  final Color? tone;
  final VoidCallback? onTap;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final BorderRadius radius = BorderRadius.circular(14);

    final Widget text = SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GDesign.space12),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: g.sans.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tone ?? g.text,
            ),
          ),
        ),
      ),
    );

    final Widget chip = solid
        ? DecoratedBox(
            decoration: BoxDecoration(color: g.raised, borderRadius: radius),
            child: text,
          )
        : GlassSurface(borderRadius: radius, border: false, child: text);

    if (onTap == null) return chip;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: GDesign.touch,
          child: Center(widthFactor: 1, child: chip),
        ),
      ),
    );
  }
}
