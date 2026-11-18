import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';

/// A screen in the immersive layout.
///
/// Layers, back to front: [background] edge to edge, [body], the [primary]
/// action, the [sheet], then the [header] floating on top. There is no app
/// bar and no safe area around the background: content runs under the status
/// bar and under the floating nav, and each layer insets itself.
class ImmersiveScaffold extends StatelessWidget {
  const ImmersiveScaffold({
    super.key,
    this.background,
    this.body,
    this.primary,
    this.sheet,
    this.header,
    this.ground,
  });

  final Widget? background;
  final Widget? body;

  /// The screen's one primary action. Sits above the sheet's peek when there
  /// is a sheet, otherwise above the nav.
  final Widget? primary;
  final Widget? sheet;
  final Widget? header;

  /// Overrides the theme ground, for black viewers and test screens.
  final Color? ground;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double bottom = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: ground ?? g.ground,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double primaryBottom = sheet != null
              ? box.maxHeight * GDesign.sheetPeek + GDesign.space16
              : bottom + GDesign.space16;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ?background,
              ?body,
              if (primary != null)
                Positioned(
                  left: GDesign.gutter,
                  right: GDesign.gutter,
                  bottom: primaryBottom,
                  child: primary!,
                ),
              ?sheet,
              if (header != null)
                Positioned(top: 0, left: 0, right: 0, child: header!),
            ],
          );
        },
      ),
    );
  }
}
