import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

/// Watches for a two finger pinch over [child] without joining the gesture
/// arena, so one finger still scrolls. Spreading past a threshold asks for
/// fewer, bigger columns; pinching in asks for more.
class PinchColumns extends StatefulWidget {
  const PinchColumns({required this.onStep, required this.child, super.key});

  /// Called once per threshold crossed. Returns whether the grid changed.
  final bool Function({required bool fewer}) onStep;
  final Widget child;

  @override
  State<PinchColumns> createState() => _PinchColumnsState();
}

class _PinchColumnsState extends State<PinchColumns> {
  final Map<int, Offset> _pointers = <int, Offset>{};

  /// Finger spread when the current step started, or null with fewer than
  /// two fingers down.
  double? _base;

  static const double _spread = 1.3;
  static const double _squeeze = 0.77;

  double _distance() {
    final List<Offset> p = _pointers.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) _base = _distance();
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final double? base = _base;
    if (_pointers.length < 2 || base == null || base <= 0) return;
    final double ratio = _distance() / base;
    if (ratio > _spread || ratio < _squeeze) {
      if (widget.onStep(fewer: ratio > _spread)) Haptics.select();
      // Measure the next step from here.
      _base = _distance();
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _base = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

/// A thin handle down the right edge of a long list. It shows while the
/// list moves, can be dragged to jump anywhere, and while dragged a bubble
/// names the section under the thumb.
class TimelineScrubber extends StatefulWidget {
  const TimelineScrubber({
    required this.controller,
    required this.labelAt,
    super.key,
    this.top = 0,
    this.bottom = 0,
  });

  final ScrollController controller;

  /// The section name at a scroll fraction from 0 to 1.
  final String? Function(double fraction) labelAt;

  /// Space kept clear above and below the track.
  final double top;
  final double bottom;

  @override
  State<TimelineScrubber> createState() => _TimelineScrubberState();
}

class _TimelineScrubberState extends State<TimelineScrubber> {
  double _fraction = 0;
  bool _visible = false;
  bool _dragging = false;
  Timer? _hide;

  static const double _thumb = 44;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TimelineScrubber old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  /// Only worth showing when the list is several screens long.
  bool get _long {
    if (!widget.controller.hasClients) return false;
    final ScrollPosition p = widget.controller.position;
    return p.maxScrollExtent > p.viewportDimension * 3;
  }

  void _onScroll() {
    if (!_long) return;
    final ScrollPosition p = widget.controller.position;
    setState(() {
      _fraction = (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
      _visible = true;
    });
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_dragging) setState(() => _visible = false);
    });
  }

  void _drag(double dy, double track) {
    final ScrollPosition p = widget.controller.position;
    final double next = (_fraction + dy / track).clamp(0.0, 1.0);
    p.jumpTo(next * p.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double track =
            box.maxHeight - widget.top - widget.bottom - _thumb;
        if (track <= 0) return const SizedBox.shrink();
        final double y = widget.top + _fraction * track;
        final String? label = _dragging ? widget.labelAt(_fraction) : null;
        return Stack(
          children: <Widget>[
            Positioned(
              right: 0,
              top: y,
              child: AnimatedOpacity(
                opacity: _visible || _dragging ? 1 : 0,
                duration: GDesign.motion(context, GDesign.normal),
                child: IgnorePointer(
                  ignoring: !_visible && !_dragging,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) {
                      Haptics.select();
                      setState(() => _dragging = true);
                    },
                    onVerticalDragUpdate: (DragUpdateDetails d) =>
                        _drag(d.delta.dy, track),
                    onVerticalDragEnd: (_) {
                      setState(() => _dragging = false);
                      _scheduleHide();
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        if (label != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: PhotoChip(label),
                          ),
                        SizedBox(
                          width: GDesign.touch,
                          height: _thumb,
                          child: Center(
                            child: AnimatedContainer(
                              duration: GDesign.motion(context, GDesign.fast),
                              width: _dragging ? 8 : 5,
                              height: _thumb,
                              decoration: BoxDecoration(
                                color: _dragging ? g.accent : g.muted,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One section on the shelf: up to three of its pictures stacked like
/// prints in a case, its name and count under them. A tap pulls the front
/// print up before [onOpen] runs.
class ShelfCase extends StatefulWidget {
  const ShelfCase({
    required this.images,
    required this.label,
    required this.detail,
    required this.onOpen,
    super.key,
  });

  final List<ImageProvider> images;
  final String label;
  final String detail;
  final VoidCallback onOpen;

  @override
  State<ShelfCase> createState() => _ShelfCaseState();
}

class _ShelfCaseState extends State<ShelfCase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pull = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Angle of each print, back to front.
  static const List<double> _tilt = <double>[-0.12, 0.09, 0];

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    Haptics.select();
    if (!MediaQuery.disableAnimationsOf(context)) await _pull.forward();
    widget.onOpen();
    if (mounted) _pull.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<ImageProvider> shown = widget.images.take(3).toList();
    final int skip = _tilt.length - shown.length;
    return Pressable(
      onTap: _open,
      semanticLabel: widget.label,
      scale: 0.97,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedBuilder(
              animation: _pull,
              builder: (BuildContext context, Widget? _) => Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  for (int i = 0; i < shown.length; i++)
                    Transform.translate(
                      // Only the front print slides up out of the case.
                      offset: Offset(
                        0,
                        i == shown.length - 1
                            ? -18 * Curves.easeOut.transform(_pull.value)
                            : 0,
                      ),
                      child: Transform.rotate(
                        angle: _tilt[i + skip],
                        child: FractionallySizedBox(
                          widthFactor: 0.78,
                          heightFactor: 0.78,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: g.card, width: 3),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: g.shadow,
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedPhoto(image: shown[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: GDesign.space8),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: g.body(weight: FontWeight.w600),
          ),
          Text(widget.detail, style: g.figures(g.footnote())),
        ],
      ),
    );
  }
}

/// The index of the section under a scroll fraction, given each section's
/// share of the list. Used to name the scrubber bubble.
int sectionAt(double fraction, List<int> sizes) {
  final int total = sizes.fold<int>(0, (int s, int n) => s + n);
  if (total == 0) return 0;
  final double target = fraction * total;
  int seen = 0;
  for (int i = 0; i < sizes.length; i++) {
    seen += sizes[i];
    if (seen >= target) return i;
  }
  return math.max(0, sizes.length - 1);
}
