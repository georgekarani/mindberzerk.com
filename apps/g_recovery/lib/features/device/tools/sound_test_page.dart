import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/hardware_bridge.dart';
import '../../../core/i18n/g_strings.dart';
import '../widgets/device_detail.dart';

/// Speakers drawn as two cones that ripple while they play, a pitch picker,
/// and the vibration motor.
class SoundTestPage extends ConsumerStatefulWidget {
  const SoundTestPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const SoundTestPage(),
  );

  @override
  ConsumerState<SoundTestPage> createState() => _SoundTestPageState();
}

class _SoundTestPageState extends ConsumerState<SoundTestPage> {
  /// 'left', 'right' or 'both' while a tone plays.
  String? _playing;
  double _hertz = 440;

  /// How long one tone lasts.
  static const int _toneMillis = 1200;

  late final HardwareBridge _bridge;

  @override
  void initState() {
    super.initState();
    // Read once here: ref cannot be used in dispose, where the tone stops.
    _bridge = ref.read(hardwareBridgeProvider);
  }

  @override
  void dispose() {
    _bridge.stopTone();
    super.dispose();
  }

  Future<void> _play(String channel) async {
    Haptics.select();
    setState(() => _playing = channel);
    await _bridge.playTone(_hertz, _toneMillis, channel);
    await Future<void>.delayed(const Duration(milliseconds: _toneMillis));
    if (mounted && _playing == channel) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    bool on(String side) => _playing == side || _playing == 'both';

    return DeviceDetail(
      title: context.s('Speakers'),
      onInfo: () =>
          showDeviceNote(context, context.s('Testing speakers'), <String>[
            context.s(
              'Turn the volume up. Left and right play through one side.',
            ),
            context.s(
              'A rattle or buzz at one pitch and not another is a damaged '
              'speaker.',
            ),
          ]),
      hero: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _Speaker(
                  label: context.s('Left'),
                  playing: on('left'),
                  onTap: () => _play('left'),
                ),
              ),
              Expanded(
                child: _Speaker(
                  label: context.s('Right'),
                  playing: on('right'),
                  onTap: () => _play('right'),
                ),
              ),
            ],
          ),
          const SizedBox(height: GDesign.space16),
          SecondaryButton(
            pill: true,
            icon: GIcons.volume,
            label: context.s('Both'),
            onTap: () => _play('both'),
          ),
        ],
      ),
      sections: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          child: Segmented<double>(
            semanticLabel: context.s('Pitch'),
            segments: <(double, String)>[
              (150, context.s('Low')),
              (440, context.s('Mid')),
              (2000, context.s('High')),
              (8000, context.s('Very high')),
            ],
            value: _hertz,
            onChanged: (double hz) {
              setState(() => _hertz = hz);
              _play(_playing ?? 'both');
            },
          ),
        ),
        GroupedSection(
          header: context.s('Vibration'),
          children: <Widget>[
            for (final (String, String) v in <(String, String)>[
              ('short', context.s('Short')),
              ('long', context.s('Long')),
              ('double', context.s('Double')),
            ])
              ListRow(
                icon: GIcons.vibrate,
                title: v.$2,
                trailing: const SizedBox.shrink(),
                onTap: () => _bridge.vibrate(v.$1),
              ),
          ],
        ),
      ],
    );
  }
}

/// One speaker: a cone that sends out rings while it plays.
class _Speaker extends StatefulWidget {
  const _Speaker({
    required this.label,
    required this.playing,
    required this.onTap,
  });

  final String label;
  final bool playing;
  final VoidCallback onTap;

  @override
  State<_Speaker> createState() => _SpeakerState();
}

class _SpeakerState extends State<_Speaker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(_Speaker old) {
    super.didUpdateWidget(old);
    final bool run = widget.playing && !MediaQuery.disableAnimationsOf(context);
    if (run && !_rings.isAnimating) {
      _rings.repeat();
    } else if (!run && _rings.isAnimating) {
      _rings
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Pressable(
      onTap: widget.onTap,
      semanticLabel: widget.label,
      scale: 0.94,
      child: Column(
        children: <Widget>[
          SizedBox.square(
            dimension: 132,
            child: AnimatedBuilder(
              animation: _rings,
              builder: (BuildContext context, Widget? child) => CustomPaint(
                painter: _RingsPainter(
                  t: widget.playing ? _rings.value : null,
                  color: g.accent,
                ),
                child: child,
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: GDesign.motion(context, GDesign.fast),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: widget.playing ? g.accent : g.fill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    GIcons.volume,
                    size: 28,
                    color: widget.playing ? g.onAccent : g.muted,
                  ),
                ),
              ),
            ),
          ),
          Text(widget.label, style: g.headline()),
        ],
      ),
    );
  }
}

/// Three rings travelling outward, each fading as it grows.
class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.t, required this.color});

  /// Animation phase, or null when silent.
  final double? t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == null) return;
    final Offset c = size.center(Offset.zero);
    const double start = 36;
    final double end = size.shortestSide / 2;
    for (int i = 0; i < 3; i++) {
      final double p = (t! + i / 3) % 1;
      canvas.drawCircle(
        c,
        start + (end - start) * p,
        Paint()
          ..color = color.withValues(alpha: (1 - p) * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}

/// Multi-touch: a circle under every finger, and the most seen at once.
class TouchTestPage extends StatefulWidget {
  const TouchTestPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const TouchTestPage(),
  );

  @override
  State<TouchTestPage> createState() => _TouchTestPageState();
}

class _TouchTestPageState extends State<TouchTestPage> {
  final Map<int, Offset> _points = <int, Offset>{};
  int _peak = 0;

  void _update(int id, Offset at) => setState(() {
    _points[id] = at;
    if (_points.length > _peak) _peak = _points.length;
  });

  void _remove(int id) => setState(() => _points.remove(id));

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    return Material(
      color: const Color(0xFF000000),
      child: Listener(
        onPointerDown: (PointerDownEvent e) =>
            _update(e.pointer, e.localPosition),
        onPointerMove: (PointerMoveEvent e) =>
            _update(e.pointer, e.localPosition),
        onPointerUp: (PointerUpEvent e) => _remove(e.pointer),
        onPointerCancel: (PointerCancelEvent e) => _remove(e.pointer),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: SizedBox.expand()),
            for (final MapEntry<int, Offset> p in _points.entries)
              Positioned(
                left: p.value.dx - 40,
                top: p.value.dy - 40,
                child: IgnorePointer(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: g.accent.withValues(alpha: 0.3),
                      border: Border.all(color: g.accent, width: 2),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            if (_points.isEmpty)
              IgnorePointer(
                child: Center(
                  child: Text(
                    context.s('Put all your fingers down'),
                    style: g.headline(color: g.onAccent),
                  ),
                ),
              ),
            Positioned(
              left: GDesign.space12,
              right: GDesign.space12,
              top: inset.top + GDesign.space8,
              child: Row(
                children: <Widget>[
                  FloatIconButton(
                    icon: GIcons.back,
                    semanticLabel: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: PhotoChip(
                        context.s1('Most at once: {}', _peak),
                        icon: GIcons.touch,
                      ),
                    ),
                  ),
                  const SizedBox(width: GDesign.touch),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
