import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import 'bench_engine.dart';
import 'bench_ladder.dart';
import 'bench_result.dart';
import 'benchmark_page.dart';
import 'phone_xray.dart';

/// The benchmark on Home: a small x-ray of this phone, the last score with
/// its tier, and a way in. Before the first run it invites one.
class BenchmarkCard extends ConsumerWidget {
  const BenchmarkCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<BenchResult> runs = ref.watch(benchHistoryProvider);
    final BenchResult? last = runs.isEmpty ? null : runs.first;
    final String title = context.s('Benchmark');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        0,
      ),
      child: Pressable(
        onTap: () => Navigator.of(context).push(BenchmarkPage.route()),
        scale: 0.97,
        semanticLabel: last == null
            ? title
            : '$title, ${last.total.round()}, ${context.s(ladderOf(ref).tierOf(last.total).label)}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: g.card,
            borderRadius: BorderRadius.circular(GDesign.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(GDesign.space16),
            child: Row(
              children: <Widget>[
                SizedBox(
                  height: 112,
                  child: ExcludeSemantics(
                    child: PhoneXray(
                      stage: last == null ? BenchStage.idle : BenchStage.done,
                      labels: false,
                    ),
                  ),
                ),
                const SizedBox(width: GDesign.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: g.footnote()),
                      const SizedBox(height: GDesign.space4),
                      if (last != null) ...<Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              last.total.round().toString(),
                              style: g.title1(),
                            ),
                            const SizedBox(width: GDesign.space8),
                            TierBadge(
                              tier: ladderOf(ref).tierOf(last.total),
                              size: 28,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.s(BenchMeanings.verdict(last.total)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: g.footnote(),
                        ),
                      ] else ...<Widget>[
                        Text(
                          context.s('How fast is this phone?'),
                          style: g.headline(),
                        ),
                        const SizedBox(height: GDesign.space8),
                        Text(
                          context.s('Run test'),
                          style: g.body(
                            color: g.accentText,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(GIcons.forward, size: 18, color: g.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
