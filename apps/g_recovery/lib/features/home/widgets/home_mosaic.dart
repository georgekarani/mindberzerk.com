import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../bridge/recovery_api.g.dart';
import '../../../bridge/recovery_bridge.dart';
import '../../../ui/g_thumbnail.dart';
import '../../recovery/state/recovery_providers.dart';

/// Home's background: what can come back, edge to edge.
///
/// Real thumbnails of real recoverable photos and video, newest first, in a
/// gapless grid that fills the screen once and never scrolls. Nothing is
/// repeated to fill space and nothing is invented: a phone with six deleted
/// photos shows six, and a phone with none shows the plain ground.
///
/// A scrim keeps the figure and the sheet readable over any photo. It follows
/// the theme ground, so light mode fades to light.
class HomeMosaic extends ConsumerWidget {
  const HomeMosaic({super.key});

  static const int _columns = 3;

  /// A third of a 360 dp screen at 3x is 360 px; 320 is sharp enough under
  /// the scrim and keeps a full screen of decodes cheap on a budget phone.
  static const int _maxPixels = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GTokens t = context.g;
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    final List<RecoverableItem> items =
        (ref
                    .watch(
                      recoveryItemsProvider(
                        const RecoveryQuery(sourceIds: kAllSourceIds),
                      ),
                    )
                    .value ??
                const <RecoverableItem>[])
            .where(
              (RecoverableItem item) =>
                  item.kind == 'image' || item.kind == 'video',
            )
            .toList();

    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double cell = box.maxWidth / _columns;
            final int rows = (box.maxHeight / cell).ceil();
            final int count = math.min(items.length, rows * _columns);

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (count > 0)
                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _columns,
                          mainAxisSpacing: 1,
                          crossAxisSpacing: 1,
                        ),
                    itemCount: count,
                    itemBuilder: (BuildContext context, int i) => GThumbnail(
                      itemId: items[i].itemId,
                      bridge: bridge,
                      kind: items[i].kind,
                      maxPixels: _maxPixels,
                      radius: 0,
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const <double>[0, 0.45, 1],
                      colors: <Color>[
                        t.ink.withValues(alpha: 0.62),
                        t.ink.withValues(alpha: 0.62),
                        t.ink.withValues(alpha: 0.96),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
