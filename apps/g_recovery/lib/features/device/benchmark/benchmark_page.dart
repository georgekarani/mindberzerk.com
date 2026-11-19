import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import '../state/identity_providers.dart';
import 'bench_engine.dart';
import 'bench_ladder.dart';
import 'bench_result.dart';
import 'gpu_bench.dart';
import 'ladder_page.dart';
import 'phone_spec.dart';
import 'phone_xray.dart';

/// Benchmark home: the phone's insides, the last score and tier, a run
/// button, the ranking and every saved run.
class BenchmarkPage extends ConsumerWidget {
  const BenchmarkPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const BenchmarkPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<BenchResult> runs = ref.watch(benchHistoryProvider);
    final BenchResult? last = runs.isEmpty ? null : runs.first;

    return LargeTitlePage(
      title: context.s('Benchmark'),
      grouped: true,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: <Widget>[
                const SizedBox(height: GDesign.space16),
                SizedBox(
                  height: 340,
                  child: PhoneXray(
                    stage: last == null ? BenchStage.idle : BenchStage.done,
                  ),
                ),
                const SizedBox(height: GDesign.space24),
                if (last != null) ...<Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        last.total.round().toString(),
                        style: g.largeTitle().copyWith(fontSize: 56, height: 1),
                      ),
                      const SizedBox(width: GDesign.space12),
                      TierBadge(tier: ladderOf(ref).tierOf(last.total)),
                    ],
                  ),
                  const SizedBox(height: GDesign.space4),
                  Text(
                    context.s(BenchMeanings.verdict(last.total)),
                    style: g.headline(color: g.muted),
                  ),
                ] else
                  Text(
                    context.s('About a minute. Keep the phone still.'),
                    style: g.headline(color: g.muted),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: GDesign.space24),
                PrimaryButton(
                  label: context.s(last == null ? 'Run test' : 'Run again'),
                  pill: true,
                  onTap: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(BenchRunPage.route()),
                ),
                const SizedBox(height: GDesign.space32),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: <Widget>[
              ListRow(
                icon: GIcons.star,
                title: context.s('Phone ranking'),
                onTap: () =>
                    Navigator.of(context).push(LadderPage.route(mine: last)),
              ),
            ],
          ),
        ),
        if (runs.isNotEmpty)
          SliverToBoxAdapter(
            child: GroupedSection(
              header: context.s('Your runs'),
              children: <Widget>[
                for (int i = 0; i < runs.length; i++)
                  ListRow(
                    icon: GIcons.gauge,
                    title: runs[i].total.round().toString(),
                    subtitle: MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(runs[i].at),
                    detail: i + 1 < runs.length
                        ? _delta(runs[i].total, runs[i + 1].total)
                        : null,
                    onTap: () => Navigator.of(context).push(
                      BenchResultPage.route(
                        runs[i],
                        previous: i + 1 < runs.length ? runs[i + 1] : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space48)),
      ],
    );
  }
}

/// "+4%" or "-12%" against an earlier score; null when within 1%.
String? _delta(double now, double before) {
  if (before <= 0) return null;
  final int pct = ((now - before) / before * 100).round();
  if (pct == 0) return null;
  return pct > 0 ? '+$pct%' : '$pct%';
}

/// A tier letter in a rounded square, coloured by how high it is.
class TierBadge extends StatelessWidget {
  const TierBadge({required this.tier, this.size = 40, super.key});

  final BenchTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Color tint = tierColor(g, tier);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: tint, width: 1.5),
      ),
      child: Text(
        tier.letter,
        style: g.headline(color: tint).copyWith(fontSize: size * 0.45),
      ),
    );
  }
}

/// Theme colour for a tier: top tiers green, the middle in the accent,
/// low tiers warning and danger.
Color tierColor(GDesignTheme g, BenchTier tier) => switch (tier) {
  BenchTier.s => g.success,
  BenchTier.a => g.success.withValues(alpha: 0.8),
  BenchTier.b => g.accent,
  BenchTier.c => g.warning,
  BenchTier.d => g.danger,
};

// ───────────────────────────────────────────────────────────────────────────
// Running
// ───────────────────────────────────────────────────────────────────────────

/// The test in progress. The x-ray lights each part as it is tested, with
/// the running score and one line on what that part does. For the graphics
/// step the test scene itself fills the screen behind the x-ray.
class BenchRunPage extends ConsumerStatefulWidget {
  const BenchRunPage({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
    transitionDuration: GDesign.slow,
    pageBuilder: (_, _, _) => const BenchRunPage(),
    transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
        FadeTransition(opacity: a, child: child),
  );

  @override
  ConsumerState<BenchRunPage> createState() => _BenchRunPageState();
}

class _BenchRunPageState extends ConsumerState<BenchRunPage> {
  /// Share of the progress bar the native tests fill; graphics takes the rest.
  static const double _nativeShare = 0.8;

  BenchProgress _now = BenchProgress.idle;
  StreamSubscription<BenchProgress>? _sub;
  Map<Object?, Object?>? _native;
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final BenchEngine engine = ref.read(benchEngineProvider);
    _sub = engine.progress().listen((BenchProgress p) {
      if (!mounted || p.stage == BenchStage.done) return;
      if (p.stage != _now.stage) Haptics.select();
      // A step reports 0 until its first workload finishes; hold the last
      // score instead of dropping to zero.
      setState(
        () => _now = BenchProgress(
          stage: p.stage,
          progress: p.progress * _nativeShare,
          live: p.live > 0 ? p.live : _now.live,
          cores: p.cores,
        ),
      );
    });
    try {
      final Map<Object?, Object?>? raw = await engine.run();
      if (!mounted) return;
      if (raw == null) {
        Navigator.of(context).pop();
        return;
      }
      await _sub?.cancel();
      Haptics.select();
      setState(() {
        _native = raw;
        _now = BenchProgress(
          stage: BenchStage.gpu,
          progress: _nativeShare,
          live: _now.live,
        );
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onGpuProgress(double progress, double fps) {
    if (!mounted) return;
    setState(
      () => _now = BenchProgress(
        stage: BenchStage.gpu,
        progress: _nativeShare + (1 - _nativeShare) * progress,
        live: _now.live,
      ),
    );
  }

  Future<void> _onGpuDone(GpuOutcome gpu) async {
    final Map<Object?, Object?>? raw = _native;
    if (raw == null || !mounted) return;
    final BenchResult run = BenchResult.fromEngine(
      raw,
      device: deviceTitle(ref.read(deviceIdentityProvider).value),
      gpu: gpu.score,
      gpuFps: gpu.fps,
      refreshRate:
          ref.read(phoneSpecProvider).value?.maxRefreshHz ??
          View.of(context).display.refreshRate,
    );
    final List<BenchResult> before = ref.read(benchHistoryProvider);
    await ref.read(benchHistoryProvider.notifier).add(run);
    Haptics.confirm();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      BenchResultPage.route(
        run,
        previous: before.isEmpty ? null : before.first,
        fresh: true,
      ),
    );
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    if (_now.stage == BenchStage.gpu) {
      Navigator.of(context).pop();
      return;
    }
    await ref.read(benchEngineProvider).cancel();
  }

  /// What the part being tested does for the person holding the phone.
  String _what(BenchStage s) => switch (s) {
    BenchStage.single => 'One core: how fast apps open and pages load',
    BenchStage.multi => 'Every core: many apps and video at once',
    BenchStage.memory => 'Memory: how fast big photos and games load',
    BenchStage.storage => 'Storage: installs, saving photos and backups',
    BenchStage.gpu => 'Graphics: games and smooth animation',
    BenchStage.done => 'Done',
    BenchStage.idle => 'Getting ready',
  };

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool gpu = _now.stage == BenchStage.gpu && _native != null;
    return PopScope(
      canPop: _error != null,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        backgroundColor: g.ground,
        body: Stack(
          children: <Widget>[
            if (gpu)
              Positioned.fill(
                child: GpuBench(
                  onProgress: _onGpuProgress,
                  onDone: _onGpuDone,
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(GDesign.gutter),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: GDesign.space24),
                    Expanded(
                      child: Center(child: PhoneXray(stage: _now.stage)),
                    ),
                    const SizedBox(height: GDesign.space24),
                    if (_error != null)
                      Text(
                        context.s('The test stopped early'),
                        style: g.headline(color: g.danger),
                      )
                    else ...<Widget>[
                      if (gpu)
                        Text(
                          context.s('Drawing a test scene'),
                          style: g.title1(),
                          textAlign: TextAlign.center,
                        )
                      else
                        CountUpText(
                          value: _now.live.round(),
                          format: (num v) => v.round().toString(),
                          style: g
                              .largeTitle()
                              .copyWith(fontSize: 56, height: 1),
                        ),
                      const SizedBox(height: GDesign.space8),
                      DirectionalSwitcher(
                        index: _now.stage.index,
                        child: Text(
                          context.s(_what(_now.stage)),
                          key: ValueKey<BenchStage>(_now.stage),
                          style: g.headline(color: g.muted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: GDesign.space24),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: _now.progress),
                        duration: GDesign.normal,
                        builder: (_, double v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 4,
                          color: g.accent,
                          backgroundColor: g.fill,
                        ),
                      ),
                    ),
                    const SizedBox(height: GDesign.space24),
                    PrimaryButton(
                      label: context.s(_error != null ? 'Close' : 'Stop'),
                      pill: true,
                      busy: _stopping,
                      onTap: _error != null
                          ? () => Navigator.of(context).pop()
                          : _stop,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Result
// ───────────────────────────────────────────────────────────────────────────

/// One run explained: the score and tier, a verdict, and what each part
/// means in daily use, each with a bar against a Galaxy S22.
class BenchResultPage extends ConsumerWidget {
  const BenchResultPage({
    required this.run,
    this.previous,
    this.fresh = false,
    super.key,
  });

  final BenchResult run;
  final BenchResult? previous;

  /// Straight after a run, the bars grow in.
  final bool fresh;

  static Route<void> route(
    BenchResult run, {
    BenchResult? previous,
    bool fresh = false,
  }) => MaterialPageRoute<void>(
    builder: (BuildContext context) =>
        BenchResultPage(run: run, previous: previous, fresh: fresh),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final BenchTier tier = ladderOf(ref).tierOf(run.total);
    final String? change = previous == null
        ? null
        : _delta(run.total, previous!.total);
    final List<(String, double, BenchMeaning, String)>
    parts = <(String, double, BenchMeaning, String)>[
      (
        'Apps',
        run.single,
        BenchMeanings.single(run.single),
        'One core ${run.single.round()}',
      ),
      (
        'Multitasking',
        run.multi,
        BenchMeanings.multi(run.multi),
        '${run.cores} cores ${run.multi.round()}',
      ),
      (
        'Games',
        run.gpu,
        BenchMeanings.gpu(run.gpu),
        'Graphics ${run.gpu.round()}',
      ),
      (
        'Memory',
        run.memory,
        BenchMeanings.memory(run.memoryGbs),
        '${run.memoryGbs.toStringAsFixed(1)} GB/s',
      ),
      (
        'Storage',
        run.storage,
        BenchMeanings.storage(run.writeMbs),
        run.readMbs == null
            ? 'Write ${run.writeMbs.round()} MB/s'
            : 'Write ${run.writeMbs.round()}, read ${run.readMbs!.round()} MB/s',
      ),
    ];
    final BenchMeaning screen = BenchMeanings.screen(run.refreshRate);
    final BenchMeaning? heat = BenchMeanings.heat(run.heatRise);

    return LargeTitlePage(
      title: context.s('Result'),
      grouped: true,
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.trash,
          semanticLabel: context.s('Delete run'),
          onTap: () async {
            await ref.read(benchHistoryProvider.notifier).remove(run);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: GDesign.space8),
                Row(
                  children: <Widget>[
                    CountUpText(
                      value: run.total.round(),
                      format: (num v) => v.round().toString(),
                      style: g.largeTitle().copyWith(fontSize: 64, height: 1),
                    ),
                    const SizedBox(width: GDesign.space12),
                    TierBadge(tier: tier),
                    if (change != null) ...<Widget>[
                      const Spacer(),
                      Text(
                        change,
                        style: g.headline(
                          color: change.startsWith('+') ? g.success : g.danger,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: GDesign.space8),
                Text(
                  context.s(BenchMeanings.verdict(run.total)),
                  style: g.title2(),
                ),
                const SizedBox(height: GDesign.space4),
                Text(
                  '${(run.total / 1000).toStringAsFixed(1)}× a Galaxy S22'
                  ' · ${context.s(tier.label)}',
                  style: g.headline(color: g.muted),
                ),
                const SizedBox(height: GDesign.space4),
                Text(
                  '${run.device} · ${MaterialLocalizations.of(context).formatMediumDate(run.at)}',
                  style: g.caption(color: g.faint),
                ),
                const SizedBox(height: GDesign.space24),
                for (int i = 0; i < parts.length; i++)
                  Reveal(
                    index: i,
                    child: _PartBar(
                      label: context.s(parts[i].$1),
                      score: parts[i].$2,
                      meaning: parts[i].$3,
                      figure: parts[i].$4,
                      grow: fresh,
                    ),
                  ),
                const SizedBox(height: GDesign.space16),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: <Widget>[
              ListRow(
                icon: GIcons.star,
                title: context.s('See where it ranks'),
                detail: '${tier.letter} · ${context.s(tier.label)}',
                onTap: () =>
                    Navigator.of(context).push(LadderPage.route(mine: run)),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: context.s('Also measured'),
            children: <Widget>[
              ListRow(
                leading: _Dot(level: screen.level),
                title: context.s(screen.line),
              ),
              if (heat != null)
                ListRow(
                  leading: _Dot(level: heat.level),
                  title: context.s(heat.line),
                ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space48)),
      ],
    );
  }
}

Color _levelColor(GDesignTheme g, BenchLevel level) => switch (level) {
  BenchLevel.great => g.success,
  BenchLevel.good => g.success.withValues(alpha: 0.75),
  BenchLevel.fair => g.warning,
  BenchLevel.weak => g.danger,
};

class _Dot extends StatelessWidget {
  const _Dot({required this.level});

  final BenchLevel level;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: _levelColor(GDesignTheme.of(context), level),
      shape: BoxShape.circle,
    ),
  );
}

/// One category: what it means in words, its score as a bar, and a tick
/// where a Galaxy S22 sits (1000).
class _PartBar extends StatelessWidget {
  const _PartBar({
    required this.label,
    required this.score,
    required this.meaning,
    required this.figure,
    required this.grow,
  });

  final String label;
  final double score;
  final BenchMeaning meaning;
  final String figure;
  final bool grow;

  /// Full width is this score, so a Galaxy S22 sits at a third and today's
  /// flagships, near 3000, fill the bar.
  static const double _scale = 3000;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Color tint = _levelColor(g, meaning.level);
    final double fraction = (score / _scale).clamp(0.02, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: GDesign.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: g.headline()),
              const Spacer(),
              Text(figure, style: g.caption(color: g.muted)),
            ],
          ),
          const SizedBox(height: GDesign.space4),
          Text(
            context.s(meaning.line),
            style: g.caption(color: tint, weight: FontWeight.w600),
          ),
          const SizedBox(height: GDesign.space8),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) =>
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: grow ? 0 : fraction,
                    end: fraction,
                  ),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, double f, _) => SizedBox(
                    height: 10,
                    child: Stack(
                      children: <Widget>[
                        Container(
                          decoration: BoxDecoration(
                            color: g.fill,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        Container(
                          width: box.maxWidth * f,
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        Positioned(
                          left: box.maxWidth * (1000 / _scale) - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: g.text),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
