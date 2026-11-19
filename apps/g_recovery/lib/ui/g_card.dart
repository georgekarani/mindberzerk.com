import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// Tells [GCard]s below whether they sit on a grouped (grey) ground, where a
/// card is white, or on the plain ground, where a card is the fill colour.
class GGroundScope extends InheritedWidget {
  const GGroundScope({required this.grouped, required super.child, super.key});

  final bool grouped;

  static bool groupedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GGroundScope>()?.grouped ??
      false;

  @override
  bool updateShouldNotify(GGroundScope old) => old.grouped != grouped;
}

/// A section card in the design language: 16 radius, no border, set apart
/// from the ground by tone alone, with a spring press when tappable.
///
/// [borderColour] and [tint] are kept so existing call sites compile; one
/// accent and borderless cards mean neither is drawn.
class GCard extends StatelessWidget {
  const GCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(GDesign.space16),
    this.background,
    this.borderColour,
    this.tint,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColour;
  final Color? tint;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool grouped = GGroundScope.groupedOf(context);
    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? (grouped || g.isDark ? g.card : g.grouped),
        borderRadius: BorderRadius.circular(GDesign.cardRadius),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null && onLongPress == null) return body;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.98,
      child: body,
    );
  }
}

/// A hairline across a card, reaching its edges past the card's padding.
class GCardDivider extends StatelessWidget {
  const GCardDivider({super.key, this.inset = GDesign.space16});

  final double inset;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GDesign.space12),
      child: SizedBox(
        height: 0.5,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth + inset * 2;
            return OverflowBox(
              minWidth: width,
              maxWidth: width,
              minHeight: 0.5,
              maxHeight: 0.5,
              child: ColoredBox(color: g.hairline),
            );
          },
        ),
      ),
    );
  }
}
