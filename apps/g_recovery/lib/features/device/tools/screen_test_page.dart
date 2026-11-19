import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';

/// Full screen colour fields for dead, stuck and tinted pixels, then a touch
/// grid that has to be filled with a finger.
///
/// The colours are the test itself, so they are literal on purpose and do
/// not follow the theme.
class ScreenTestPage extends StatefulWidget {
  const ScreenTestPage({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (BuildContext context, Animation<double> a, _) =>
        FadeTransition(
          opacity: a,
          child: const Material(
            type: MaterialType.transparency,
            child: ScreenTestPage(),
          ),
        ),
  );

  @override
  State<ScreenTestPage> createState() => _ScreenTestPageState();
}

class _ScreenTestPageState extends State<ScreenTestPage> {
  int _step = 0;

  /// Shown on the first field only, then it fades for good.
  bool _hint = true;

  static const List<(String, Color)> _fields = <(String, Color)>[
    ('White', Color(0xFFFFFFFF)),
    ('Black', Color(0xFF000000)),
    ('Red', Color(0xFFFF0000)),
    ('Green', Color(0xFF00FF00)),
    ('Blue', Color(0xFF0000FF)),
    ('Grey', Color(0xFF808080)),
  ];

  bool get _onGrid => _step >= _fields.length;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _next() {
    Haptics.select();
    setState(() {
      _step++;
      _hint = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_onGrid) {
      return _TouchGrid(onDone: () => Navigator.of(context).pop());
    }
    final GDesignTheme g = GDesignTheme.of(context);
    final (String name, Color colour) = _fields[_step];
    final Color ink = colour.computeLuminance() > 0.4
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    final Duration fade = GDesign.motion(context, GDesign.normal);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _next,
      child: AnimatedContainer(
        duration: fade,
        color: colour,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: GDesign.space12),
              // Progress: one dot per step, the touch grid included.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i <= _fields.length; i++)
                    AnimatedContainer(
                      duration: fade,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _step ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: i <= _step ? 0.6 : 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: fade,
                child: Text(
                  context.s(name),
                  key: ValueKey<int>(_step),
                  style: g.headline(color: ink.withValues(alpha: 0.5)),
                ),
              ),
              AnimatedOpacity(
                opacity: _hint ? 1 : 0,
                duration: fade,
                child: Padding(
                  padding: const EdgeInsets.only(top: GDesign.space4),
                  child: Text(
                    context.s('Tap for the next colour'),
                    style: g.footnote(color: ink.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              const SizedBox(height: GDesign.space32),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grid that fills exactly the screen. Every square a finger crosses
/// lights up with a pop; any that stay dark are not registering touch.
class _TouchGrid extends StatefulWidget {
  const _TouchGrid({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_TouchGrid> createState() => _TouchGridState();
}

class _TouchGridState extends State<_TouchGrid> {
  static const int _columns = 6;
  static const int _rows = 12;
  final Set<int> _touched = <int>{};

  int get _total => _columns * _rows;

  void _mark(Offset at, Size size) {
    final int column = (at.dx / size.width * _columns).floor();
    final int row = (at.dy / size.height * _rows).floor();
    if (column < 0 || column >= _columns || row < 0 || row >= _rows) return;
    if (_touched.add(row * _columns + column)) {
      Haptics.select();
      setState(() {});
      if (_touched.length == _total) Haptics.confirm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool done = _touched.length == _total;
    final EdgeInsets inset = MediaQuery.paddingOf(context);

    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final Size size = box.biggest;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (DragDownDetails d) =>
                      _mark(d.localPosition, size),
                  onPanUpdate: (DragUpdateDetails d) =>
                      _mark(d.localPosition, size),
                  child: Column(
                    children: <Widget>[
                      for (int r = 0; r < _rows; r++)
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              for (int c = 0; c < _columns; c++)
                                Expanded(
                                  child: _Cell(
                                    on: _touched.contains(r * _columns + c),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: GDesign.space12,
            right: GDesign.space12,
            top: inset.top + GDesign.space8,
            child: Row(
              children: <Widget>[
                FloatIconButton(
                  icon: GIcons.close,
                  semanticLabel: context.s('Close'),
                  onTap: widget.onDone,
                ),
                Expanded(
                  child: Center(
                    child: PhotoChip(
                      done
                          ? context.s('Every square responds')
                          : context.s1('{} of $_total', _touched.length),
                      icon: done ? GIcons.checkCircle : GIcons.touch,
                    ),
                  ),
                ),
                const SizedBox(width: GDesign.touch),
              ],
            ),
          ),
          if (done)
            Positioned(
              left: 0,
              right: 0,
              bottom: inset.bottom + GDesign.space24,
              child: Center(
                child: Reveal(
                  child: PrimaryButton(
                    pill: true,
                    label: context.s('Done'),
                    onTap: widget.onDone,
                  ),
                ),
              ),
            ),
          // Keeps the first frame readable before anything is touched.
          if (_touched.isEmpty)
            IgnorePointer(
              child: Center(
                child: Text(
                  context.s('Drag over every square'),
                  style: g.headline(color: g.onAccent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One square: dim until touched, then a pop into the accent.
class _Cell extends StatelessWidget {
  const _Cell({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Duration d = GDesign.motion(context, GDesign.normal);
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: AnimatedScale(
        scale: on ? 1 : 0.86,
        duration: d,
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: d,
          decoration: BoxDecoration(
            color: on ? g.accent : const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}
