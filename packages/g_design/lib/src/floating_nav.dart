import 'package:flutter/material.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';

@immutable
class FloatingNavItem {
  const FloatingNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Glass pill nav, [GDesign.navInset] above the system gesture area.
///
/// Meant for `Scaffold.bottomNavigationBar` with `extendBody: true`. The
/// scaffold then adds this widget's height to the body's bottom padding, so
/// content can run underneath while anything that respects the padding stops
/// above the pill. The empty space either side of the pill passes touches
/// through to the content below.
///
/// The selected tab shows its label; the others are icons with the label kept
/// for screen readers.
class FloatingNav extends StatelessWidget {
  const FloatingNav({
    required this.items,
    required this.index,
    required this.onSelected,
    super.key,
  });

  final List<FloatingNavItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  /// Height the nav takes from the bottom of the screen, gesture area
  /// included.
  static double reserve(BuildContext context) =>
      GDesign.navHeight +
      GDesign.navInset +
      MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final double gesture = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: gesture + GDesign.navInset),
      child: Center(
        heightFactor: 1,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(GDesign.navHeight / 2),
          child: Padding(
            padding: const EdgeInsets.all(GDesign.space4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: GDesign.space4),
                  _Cell(
                    item: items[i],
                    selected: i == index,
                    onTap: () => onSelected(i),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Color tone = selected ? g.accent : g.muted;
    final Duration duration = GDesign.motion(context, GDesign.normal);
    final BorderRadius radius = BorderRadius.circular(GDesign.touch / 2);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: GDesign.enter,
            height: GDesign.touch,
            // 13 + 22 + 13 keeps an unselected cell exactly 48 dp wide.
            padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 13),
            decoration: BoxDecoration(
              color:
                  selected ? g.accentSoft : g.accentSoft.withValues(alpha: 0),
              borderRadius: radius,
            ),
            child: AnimatedSize(
              duration: duration,
              curve: GDesign.enter,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(item.icon, size: 22, color: tone),
                  if (selected) ...<Widget>[
                    const SizedBox(width: GDesign.space8),
                    Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      style: g.sans.copyWith(
                        fontSize: GDesign.caption,
                        fontWeight: FontWeight.w600,
                        color: tone,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
