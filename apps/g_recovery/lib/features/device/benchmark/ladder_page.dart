import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import 'bench_ladder.dart';
import 'bench_result.dart';
import 'benchmark_page.dart';
import 'phone_spec.dart';

/// The tier pyramid and real phones on it, with this phone placed by its
/// own run. Each phone is drawn in the x-ray's line style with its own
/// number of rear lenses.
class LadderPage extends ConsumerWidget {
  const LadderPage({this.mine, super.key});

  /// This phone's latest run, if it has one.
  final BenchResult? mine;

  static Route<void> route({BenchResult? mine}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => LadderPage(mine: mine),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final BenchResult? run = mine;
    final int myLenses =
        ref.watch(phoneSpecProvider).value?.rearCameras.length ?? 3;
    final Ladder ladder = ladderOf(ref);
    final List<_Entry> entries = <_Entry>[
      for (final LadderPhone p in ladder.all)
        _Entry(
          name: p.name,
          chip: p.chip,
          lenses: p.lenses,
          index: ladder.indexOf(p),
        ),
      if (run != null)
        _Entry(
          name: run.device,
          chip: '',
          lenses: myLenses,
          index: run.total,
          mine: true,
        ),
    ]..sort((_Entry a, _Entry b) => b.index.compareTo(a.index));
    final double top = entries.first.index;
    final BenchTier? myTier = run == null ? null : ladder.tierOf(run.total);

    return LargeTitlePage(
      title: context.s('Phone ranking'),
      grouped: true,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: <Widget>[
                const SizedBox(height: GDesign.space16),
                _Pyramid(highlight: myTier),
                const SizedBox(height: GDesign.space24),
              ],
            ),
          ),
        ),
        for (final BenchTier tier in BenchTier.values)
          if (entries.any((_Entry e) => ladder.tierOf(e.index) == tier))
            SliverToBoxAdapter(
              child: GroupedSection(
                header: '${tier.letter} · ${context.s(tier.label)}',
                children: <Widget>[
                  for (final _Entry e in entries)
                    if (ladder.tierOf(e.index) == tier)
                      _PhoneRow(entry: e, top: top, tier: tier),
                ],
              ),
            ),
        if (run == null)
          SliverPadding(
            padding: const EdgeInsets.all(GDesign.gutter),
            sliver: SliverToBoxAdapter(
              child: Text(
                context.s('Run the test to place this phone'),
                style: g.headline(color: g.muted),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space48)),
      ],
    );
  }
}

class _Entry {
  const _Entry({
    required this.name,
    required this.chip,
    required this.lenses,
    required this.index,
    this.mine = false,
  });

  final String name;
  final String chip;
  final int lenses;
  final double index;
  final bool mine;
}

/// Five bands from S at the narrow top to D at the wide base. This phone's
/// band is filled; the rest are tinted.
class _Pyramid extends StatelessWidget {
  const _Pyramid({required this.highlight});

  final BenchTier? highlight;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    const List<BenchTier> tiers = BenchTier.values;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => Column(
        children: <Widget>[
          for (int i = 0; i < tiers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: GDesign.space4),
              child: _Band(
                tier: tiers[i],
                width: box.maxWidth * (0.36 + 0.16 * i),
                on: tiers[i] == highlight,
                color: tierColor(g, tiers[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({
    required this.tier,
    required this.width,
    required this.on,
    required this.color,
  });

  final BenchTier tier;
  final double width;
  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return AnimatedContainer(
      duration: GDesign.slow,
      curve: Curves.easeOutCubic,
      width: width,
      height: GDesign.touch,
      padding: const EdgeInsets.symmetric(horizontal: GDesign.space12),
      decoration: BoxDecoration(
        color: on ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GDesign.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          Text(tier.letter, style: g.headline(color: on ? g.onAccent : color)),
          const SizedBox(width: GDesign.space8),
          Expanded(
            child: Text(
              on ? context.s('This phone') : context.s(tier.label),
              overflow: TextOverflow.ellipsis,
              style: g.caption(
                color: on ? g.onAccent : g.muted,
                weight: on ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One phone: its drawing, name, chip, score and a bar against the fastest
/// phone listed.
class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.entry, required this.top, required this.tier});

  final _Entry entry;
  final double top;
  final BenchTier tier;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Color tint = entry.mine
        ? g.accent
        : tierColor(g, tier);
    return Container(
      color: entry.mine ? g.accent.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: GDesign.space16,
        vertical: GDesign.space12,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 30,
            height: 56,
            child: CustomPaint(
              painter: _PhoneGlyph(
                lenses: entry.lenses,
                line: entry.mine ? g.accent : g.text.withValues(alpha: 0.35),
                fill: entry.mine
                    ? g.accent.withValues(alpha: 0.16)
                    : g.text.withValues(alpha: 0.05),
              ),
            ),
          ),
          const SizedBox(width: GDesign.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: g.headline().copyWith(
                          fontWeight: entry.mine ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    Text(
                      entry.index.round().toString(),
                      style: g.headline(color: tint),
                    ),
                  ],
                ),
                Text(
                  entry.mine ? context.s('This phone') : entry.chip,
                  style: g.caption(color: entry.mine ? g.accent : g.muted),
                ),
                const SizedBox(height: GDesign.space8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: entry.index / top),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, double f, _) => LinearProgressIndicator(
                      value: f.clamp(0.02, 1.0),
                      minHeight: 6,
                      color: tint,
                      backgroundColor: g.fill,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A phone's back in outline with its rear lenses: a column for up to
/// three, a square for four.
class _PhoneGlyph extends CustomPainter {
  _PhoneGlyph({required this.lenses, required this.line, required this.fill});

  final int lenses;
  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final RRect body = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(w * 0.22),
    );
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = line;
    canvas
      ..drawRRect(body, Paint()..color = fill)
      ..drawRRect(body.deflate(0.6), stroke);

    final int n = lenses.clamp(1, 4);
    final double r = w * 0.11;
    final Offset origin = Offset(w * 0.3, w * 0.3);
    final List<Offset> at = n == 4
        ? <Offset>[
            origin,
            origin + Offset(r * 2.6, 0),
            origin + Offset(0, r * 2.6),
            origin + Offset(r * 2.6, r * 2.6),
          ]
        : <Offset>[for (int i = 0; i < n; i++) origin + Offset(0, i * r * 2.6)];
    for (final Offset c in at) {
      canvas.drawCircle(c, math.max(r, 2), stroke);
    }
  }

  @override
  bool shouldRepaint(_PhoneGlyph old) =>
      old.lenses != lenses || old.line != line || old.fill != fill;
}
