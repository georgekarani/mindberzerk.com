import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/compress_api.g.dart';
import '../../../bridge/compress_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';

/// The run: layers pressing flat, and what has been freed so far.
class CompressRunning extends ConsumerWidget {
  const CompressRunning({super.key, this.note});

  /// One short line under the progress, such as "You can leave the app".
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final CompressProgress? p = ref.watch(compressProgressProvider).value;
    final int done = p?.done ?? 0;
    final int total = p?.total ?? 0;
    final int saved = p?.savedBytes ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter * 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const _Squeezing(),
          const SizedBox(height: GDesign.space32),
          CountUpText(
            value: saved,
            format: (num v) => context.s1('{} freed', GFormat.bytes(v.round())),
            style: g.figures(g.largeTitle()),
          ),
          const SizedBox(height: GDesign.space16),
          if (total > 0) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0,
                    end: (done / total).clamp(0.0, 1.0),
                  ),
                  duration: GDesign.motion(context, GDesign.slow),
                  curve: GDesign.enter,
                  builder: (BuildContext context, double v, Widget? _) =>
                      LinearProgressIndicator(
                        value: v,
                        backgroundColor: g.fill,
                        color: g.accent,
                      ),
                ),
              ),
            ),
            const SizedBox(height: GDesign.space8),
            Text(
              context.s1('{} of ${GFormat.count(total)}', GFormat.count(done)),
              style: g.figures(g.footnote()),
            ),
          ],
          if (note != null) ...<Widget>[
            const SizedBox(height: GDesign.space24),
            Text(note!, textAlign: TextAlign.center, style: g.footnote()),
          ],
        ],
      ),
    );
  }
}

/// Eight bars that press flat in a wave and spring back, on a loop.
class _Squeezing extends StatefulWidget {
  const _Squeezing();

  @override
  State<_Squeezing> createState() => _SqueezingState();
}

class _SqueezingState extends State<_Squeezing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  static const List<double> _widths = <double>[
    0.94,
    0.72,
    0.88,
    0.63,
    0.80,
    0.70,
    0.86,
    0.58,
  ];
  static const double _tall = 10;
  static const double _short = 3;
  static const double _gap = 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 is full height, 1 is pressed flat. Each bar starts a little later.
  double _settled(int i) {
    double t = (_controller.value - i * 0.045) % 1.0;
    if (t < 0) t += 1;
    if (t < 0.35) return 0;
    if (t < 0.62) return Curves.easeOut.transform((t - 0.35) / 0.27);
    if (t < 0.88) return 1;
    return 1 - Curves.easeIn.transform((t - 0.88) / 0.12);
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 120,
      height: _widths.length * (_tall + _gap),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) => Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            for (int i = _widths.length - 1; i >= 0; i--)
              Padding(
                padding: const EdgeInsets.only(top: _gap),
                child: FractionallySizedBox(
                  widthFactor: _widths[i],
                  child: Container(
                    height:
                        _tall - (_tall - _short) * (still ? 1 : _settled(i)),
                    decoration: BoxDecoration(
                      color: g.accent.withValues(
                        alpha: 0.35 + (still ? 1 : _settled(i)) * 0.6,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
