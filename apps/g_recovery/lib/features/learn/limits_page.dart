import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

import '../../app/theme/tokens.dart';
import '../../core/i18n/g_strings.dart';

/// What can come back, and what cannot, told as three outcomes after an
/// illustration of files coming apart.
class LimitsPage extends StatelessWidget {
  const LimitsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const LimitsPage(),
  );

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return LargeTitlePage(
      title: context.s('What can come back'),
      backLabel: context.s('More'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      slivers: <Widget>[
        const SliverToBoxAdapter(child: DustArt(height: 170)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GDesign.gutter,
              GDesign.space16,
              GDesign.gutter,
              GDesign.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.s('Deleting is not one thing'), style: g.title2()),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          sliver: SliverList.list(
            children: <Widget>[
              Reveal(
                index: 0,
                child: _Tier(
                  level: 3,
                  verdict: context.s('Comes back whole'),
                  title: context.s('It went to a trash folder'),
                  body: context.s('Kept for 30 days, restored exactly.'),
                ),
              ),
              const SizedBox(height: GDesign.space12),
              Reveal(
                index: 1,
                child: _Tier(
                  level: 1,
                  verdict: context.s('Comes back smaller'),
                  title: context.s('Only the preview survived'),
                  body: context.s('A small copy outlived the original.'),
                ),
              ),
              const SizedBox(height: GDesign.space12),
              Reveal(
                index: 2,
                child: _Tier(
                  level: 0,
                  verdict: context.s('Does not come back'),
                  title: context.s('It was erased outside a bin'),
                  body: context.s('The phone wiped it within seconds.'),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: GDesign.space24,
              bottom: GDesign.space32,
            ),
            child: GroupedSection(
              children: <Widget>[
                ListRow(
                  icon: GIcons.shield,
                  title: context.s('Why no app can do more'),
                  onTap: () => _explain(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _explain(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        Widget point(String heading, String body) => Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(heading, style: g.headline()),
              const SizedBox(height: GDesign.space4),
              Text(body, style: g.body(color: g.muted)),
            ],
          ),
        );
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space8,
            GDesign.gutter,
            GDesign.space24,
          ),
          children: <Widget>[
            Text(context.s('Why no app can do more'), style: g.title2()),
            const SizedBox(height: GDesign.space16),
            point(
              context.s('The storage erases itself'),
              context.s(
                'Phone storage is flash. When a file is deleted the phone '
                'tells the chip those blocks are free, and the chip clears '
                'them within seconds.',
              ),
            ),
            point(
              context.s('No app may read the disk'),
              context.s(
                'Android gives an app a view of files, never of the disk '
                'underneath, so the scan desktop tools perform cannot be tried.',
              ),
            ),
            point(
              context.s('It is all encrypted anyway'),
              context.s(
                'Each file is encrypted with its own key, destroyed with the '
                'file. Even the raw blocks would read as noise.',
              ),
            ),
            point(
              context.s('So what is left'),
              context.s(
                'Everything not yet truly deleted: the system trash, the bins '
                'apps keep, media an app forgot, and the preview cache. That '
                'is where this app looks.',
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One outcome: how much comes back as a three-step meter, the verdict, a
/// title and the reason.
class _Tier extends StatelessWidget {
  const _Tier({
    required this.level,
    required this.verdict,
    required this.title,
    required this.body,
  });

  /// Filled steps out of three: 3 whole, 1 smaller, 0 nothing.
  final int level;
  final String verdict;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.card,
        borderRadius: BorderRadius.circular(GDesign.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(GDesign.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                for (int i = 0; i < 3; i++)
                  Container(
                    width: 18,
                    height: 6,
                    margin: const EdgeInsetsDirectional.only(end: 3),
                    decoration: BoxDecoration(
                      color: i < level
                          ? g.accent
                          : (g.isDark ? g.hairline : g.fill),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: GDesign.space8),
                Text(
                  verdict,
                  style: g.footnote(
                    color: level > 0 ? g.accentText : g.muted,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: GDesign.space12),
            Text(title, style: g.headline()),
            const SizedBox(height: GDesign.space4),
            Text(body, style: g.body(color: g.muted)),
          ],
        ),
      ),
    );
  }
}

/// Files falling and coming apart.
///
/// The subject of the page, drawn. A card descends, breaks into particles part
/// way down, and the particles fade before they land. Nothing reaches the
/// bottom, which is the entire point: there is no pile of recoverable debris
/// down there for an app to sift through.
class DustArt extends StatefulWidget {
  const DustArt({super.key, this.height = 190});

  final double height;

  @override
  State<DustArt> createState() => _DustArtState();
}

class _DustArtState extends State<DustArt> with SingleTickerProviderStateMixin {
  // Constructed here, never as a late final with an initialiser. The lazy form
  // can run its initialiser from inside dispose, where createTicker reads
  // TickerMode off a deactivated element.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6400),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GTokens t = context.g;

    if (MediaQuery.disableAnimationsOf(context)) {
      return SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: _DustPainter(tokens: t, phase: 0.5),
          size: Size.infinite,
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _DustPainter(tokens: t, phase: _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DustPainter extends CustomPainter {
  const _DustPainter({required this.tokens, required this.phase});

  final GTokens tokens;
  final double phase;

  static const int _files = 4;
  static const int _motes = 9;

  /// Where the card stops being a card. Before this it falls whole; after, it
  /// is particles that spread and fade.
  static const double _breakAt = 0.46;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < _files; i++) {
      final double local = (phase + i / _files) % 1;
      _fall(canvas, size, local, i);
    }
  }

  void _fall(Canvas canvas, Size size, double local, int index) {
    final double x =
        size.width * (0.2 + 0.2 * index) +
        math.sin(local * math.pi * 2 + index) * size.width * 0.03;
    final double y = size.height * (0.08 + local * 0.78);

    final Color colour = <Color>[
      tokens.photo,
      tokens.video,
      tokens.docs,
      tokens.audio,
    ][index % 4];

    if (local < _breakAt) {
      // Whole, and fading slightly as it goes. A card at full strength right up
      // to the moment it shatters looks like a cut rather than a decay.
      final double fade = 1 - (local / _breakAt) * 0.25;
      final double w = size.width * 0.13;
      final double h = w * 0.8;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(local * 4 + index) * 0.3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          Radius.circular(w * 0.16),
        ),
        Paint()..color = colour.withValues(alpha: 0.85 * fade),
      );
      canvas.restore();
      return;
    }

    // Coming apart. Spread grows with distance past the break, opacity falls to
    // nothing before the particles reach the bottom edge.
    final double since = (local - _breakAt) / (1 - _breakAt);
    final double spread = size.width * 0.14 * since;
    final double alpha = (1 - since) * 0.7;
    if (alpha <= 0.01) return;

    final Paint paint = Paint()..color = colour.withValues(alpha: alpha);
    for (int m = 0; m < _motes; m++) {
      final double angle = (m / _motes) * math.pi * 2 + index;
      final double drift = 0.5 + ((m * 37 + index * 11) % 50) / 100;
      canvas.drawCircle(
        Offset(
          x + math.cos(angle) * spread * drift,
          y + math.sin(angle) * spread * drift * 0.6,
        ),
        size.width * (0.013 - 0.006 * since),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) =>
      old.phase != phase || old.tokens.ink != tokens.ink;
}
