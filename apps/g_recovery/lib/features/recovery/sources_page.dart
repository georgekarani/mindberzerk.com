import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../bridge/recovery_api.g.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/g_card.dart';
import '../device/widgets/device_detail.dart';
import '../learn/limits_page.dart';
import 'category_page.dart';
import 'state/recovery_providers.dart';

/// Every place on the phone where deleted files can still be, drawn as a
/// radar with one blip per place, then a row for each saying what quality
/// it gives back.
class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const SourcesPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final RecoverySummary? summary = ref.watch(prescanProvider).value;
    final List<RecoverySource> sources =
        List<RecoverySource>.of(summary?.sources ?? const <RecoverySource>[])
          ..sort((RecoverySource a, RecoverySource b) {
            if (a.available != b.available) return a.available ? -1 : 1;
            return b.itemCount.compareTo(a.itemCount);
          });
    final int items = sources.fold<int>(
      0,
      (int n, RecoverySource s) => n + s.itemCount,
    );

    return GGroundScope(
      grouped: true,
      child: LargeTitlePage(
        title: context.s('Where it looks'),
        grouped: true,
        backLabel: context.s('Can come back'),
        onBack: () => Navigator.of(context).maybePop(),
        actions: <Widget>[
          NavAction.icon(
            icon: GIcons.info,
            semanticLabel: context.s('Reading this page'),
            onTap: () => showDeviceNote(
              context,
              context.s('Reading this page'),
              <String>[
                context.s(
                  'Full quality: the original file is still here, and '
                  'restoring gives back exactly what you had.',
                ),
                context.s(
                  'Preview only: the original is gone. What is left is the '
                  'small copy Android kept to draw your gallery.',
                ),
                context.s(
                  'Off limits: this phone does not let any app look there. '
                  'It is listed so you know it was checked.',
                ),
              ],
            ),
          ),
        ],
        slivers: <Widget>[
          if (summary == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else ...<Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  GDesign.space8,
                  GDesign.gutter,
                  0,
                ),
                child: Reveal(
                  child: Column(
                    children: <Widget>[
                      _Radar(sources: sources),
                      const SizedBox(height: GDesign.space12),
                      CountUpText(
                        value: items,
                        format: (num v) => context.s1(
                          '{} items found',
                          GFormat.count(v.round()),
                        ),
                        style: g.figures(g.headline()),
                      ),
                      Text(
                        context.s1(
                          'in {} places',
                          sources
                              .where((RecoverySource s) => s.available)
                              .length,
                        ),
                        style: g.footnote(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: GDesign.space32),
                child: GroupedSection(
                  children: <Widget>[
                    for (final RecoverySource s in sources)
                      ListRow(
                        icon: _icon(s),
                        title: s.label,
                        subtitle: _quality(context, s),
                        detail: s.available ? GFormat.count(s.itemCount) : null,
                        onTap: s.available && s.itemCount > 0
                            ? () => Navigator.of(context).push(
                                CategoryPage.route(
                                  title: s.label,
                                  sourceIds: <String>[s.sourceId],
                                  backLabel: context.s('Where it looks'),
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  GDesign.space32,
                  0,
                  GDesign.space48,
                ),
                child: GroupedSection(
                  children: <Widget>[
                    ListRow(
                      icon: GIcons.help,
                      title: context.s('What cannot come back'),
                      onTap: () =>
                          Navigator.of(context).push(LimitsPage.route()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(RecoverySource s) {
    if (!s.available) return GIcons.lock;
    return s.fidelity == 'preview' ? GIcons.images : GIcons.checkCircle;
  }

  static String _quality(BuildContext context, RecoverySource s) {
    if (!s.available) return context.s('Off limits on this phone');
    final String quality = s.fidelity == 'preview'
        ? context.s('Preview only')
        : context.s('Full quality');
    final int? days = s.retentionDays;
    return days == null
        ? quality
        : '$quality, ${context.s1('kept {} days', days)}';
  }
}

/// A radar: rings, a sweeping beam, and one blip per place. Blips sit closer
/// to the centre the more they hold, grow with their item count, and flare
/// as the beam passes. Places the phone keeps closed are hollow.
class _Radar extends StatefulWidget {
  const _Radar({required this.sources});

  final List<RecoverySource> sources;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    int most = 1;
    for (final RecoverySource s in widget.sources) {
      most = math.max(most, s.itemCount);
    }
    return SizedBox.square(
      dimension: 220,
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (BuildContext context, Widget? _) => CustomPaint(
          painter: _RadarPainter(
            sources: widget.sources,
            most: most,
            angle: _sweep.value * math.pi * 2,
            ring: g.text.withValues(alpha: 0.12),
            beam: g.accent,
            blip: g.accent,
            closed: g.muted,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.sources,
    required this.most,
    required this.angle,
    required this.ring,
    required this.beam,
    required this.blip,
    required this.closed,
  });

  final List<RecoverySource> sources;
  final int most;
  final double angle;
  final Color ring;
  final Color beam;
  final Color blip;
  final Color closed;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;

    final Paint line = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(c, r * i / 3, line);
    }

    // The beam: a fading wedge trailing the sweep line.
    final Rect box = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      box,
      angle - 0.9,
      0.9,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: angle - 0.9,
          endAngle: angle,
          colors: <Color>[
            beam.withValues(alpha: 0),
            beam.withValues(alpha: 0.28),
          ],
          transform: GradientRotation(0),
        ).createShader(box),
    );

    final int n = sources.length;
    for (int i = 0; i < n; i++) {
      final RecoverySource s = sources[i];
      final double a = -math.pi / 2 + math.pi * 2 * i / math.max(n, 1) + 0.4;
      final double share = s.itemCount / most;
      // Fuller places sit nearer the centre.
      final double dist = r * (0.82 - 0.5 * share);
      final Offset at = c + Offset(math.cos(a), math.sin(a)) * dist;
      final double dot = 4 + 7 * math.sqrt(share);

      // Flare for a moment after the beam passes.
      double since = (angle - (a % (math.pi * 2))) % (math.pi * 2);
      if (since < 0) since += math.pi * 2;
      final double flare = since < 1.2 ? 1 - since / 1.2 : 0;

      if (!s.available) {
        canvas.drawCircle(
          at,
          dot,
          Paint()
            ..color = closed
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        continue;
      }
      if (flare > 0) {
        canvas.drawCircle(
          at,
          dot + 8 * flare,
          Paint()..color = blip.withValues(alpha: 0.25 * flare),
        );
      }
      canvas.drawCircle(
        at,
        dot,
        Paint()..color = blip.withValues(alpha: 0.6 + 0.4 * flare),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.angle != angle || old.sources != sources || old.beam != beam;
}
