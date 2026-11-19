import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// One action under a peek.
@immutable
class PeekAction {
  const PeekAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

/// Holds a file up for a closer look: the screen blurs, the preview grows
/// out of the tile on a spring (playing, if it is a video), and the actions
/// sit under it. Tap anywhere else to put it back.
Future<void> showMediaPeek(
  BuildContext context, {
  required Widget preview,
  required double aspectRatio,
  required List<PeekAction> actions,
}) {
  Haptics.lift();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: GDesign.motion(context, Springs.standardCurve.settle),
      reverseTransitionDuration: GDesign.motion(context, GDesign.fast),
      pageBuilder: (BuildContext context, Animation<double> a, _) => _Peek(
        animation: a,
        preview: preview,
        aspectRatio: aspectRatio,
        actions: actions,
      ),
    ),
  );
}

class _Peek extends StatelessWidget {
  const _Peek({
    required this.animation,
    required this.preview,
    required this.aspectRatio,
    required this.actions,
  });

  final Animation<double> animation;
  final Widget preview;
  final double aspectRatio;
  final List<PeekAction> actions;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Size screen = MediaQuery.sizeOf(context);
    final Animation<double> spring = CurvedAnimation(
      parent: animation,
      curve: Springs.standardCurve,
      reverseCurve: Curves.easeIn,
    );
    // The preview is as large as fits in the top 60 percent of the screen.
    final double maxW = screen.width - 2 * GDesign.gutter;
    final double maxH = screen.height * 0.6;
    final double w = (maxH * aspectRatio).clamp(0, maxW);
    final double h = w / aspectRatio;

    return AnimatedBuilder(
      animation: spring,
      builder: (BuildContext context, Widget? child) {
        final double t = spring.value;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 24 * animation.value,
                  sigmaY: 24 * animation.value,
                ),
                child: ColoredBox(
                  color: g.scrim.withValues(alpha: g.scrim.a * animation.value),
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: animation.value,
                child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
              ),
            ),
          ],
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(GDesign.cardRadius),
            child: SizedBox(width: w, height: h, child: preview),
          ),
          const SizedBox(height: GDesign.space12),
          SizedBox(
            width: 240,
            child: GlassSurface(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < actions.length; i++)
                    _ActionRow(
                      action: actions[i],
                      last: i == actions.length - 1,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.last});

  final PeekAction action;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Color ink = action.destructive ? g.danger : g.text;
    return Pressable(
      onTap: () {
        Navigator.of(context).pop();
        action.onTap();
      },
      scale: 0.98,
      child: Container(
        height: GDesign.touch,
        padding: const EdgeInsets.symmetric(horizontal: GDesign.space16),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: g.hairline, width: 0.5)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(action.label, style: g.body(color: ink)),
            ),
            Icon(action.icon, size: 20, color: ink),
          ],
        ),
      ),
    );
  }
}
