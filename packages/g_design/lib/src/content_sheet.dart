import 'package:flutter/material.dart';

import 'float_header.dart';
import 'theme.dart';
import 'tokens.dart';

/// The one raised surface on a screen: a draggable sheet over full-bleed
/// content.
///
/// Snaps between peek, half and full. Full stops [GDesign.space8] under the
/// [FloatHeader] so the back button and title stay reachable. [builder] gets
/// the scroll controller that drives the drag: hand it to the sheet's list,
/// and start the list with a [SheetHandle].
///
/// Bottom padding for the nav is the list's job: read
/// `MediaQuery.paddingOf(context).bottom`, which the shell scaffold fills in.
class ContentSheet extends StatelessWidget {
  const ContentSheet({
    required this.builder,
    super.key,
    this.initial = GDesign.sheetPeek,
    this.min = GDesign.sheetPeek,
    this.controller,
  });

  final Widget Function(BuildContext context, ScrollController scroll) builder;
  final double initial;
  final double min;
  final DraggableScrollableController? controller;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double headerBottom = FloatHeader.extent(context) + GDesign.space8;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double height = box.maxHeight;
        final double full = ((height - headerBottom) / height).clamp(
          min,
          GDesign.sheetFull,
        );
        final bool hasHalf =
            GDesign.sheetHalf > min && GDesign.sheetHalf < full;

        return DraggableScrollableSheet(
          controller: controller,
          initialChildSize: initial.clamp(min, full),
          minChildSize: min,
          maxChildSize: full,
          snap: true,
          snapSizes: hasHalf ? const <double>[GDesign.sheetHalf] : null,
          snapAnimationDuration: GDesign.motion(context, GDesign.normal),
          builder: (BuildContext context, ScrollController scroll) => Material(
            color: g.sheet,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(GDesign.sheetRadius),
              ),
            ),
            child: builder(context, scroll),
          ),
        );
      },
    );
  }
}

/// The grab bar at the top of a sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: GDesign.space8),
        decoration: BoxDecoration(
          color: g.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
