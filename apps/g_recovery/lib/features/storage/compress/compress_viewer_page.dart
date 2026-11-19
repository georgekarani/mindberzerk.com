import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/compress_api.g.dart';
import '../../../bridge/compress_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';

/// Before and after, full screen, on black.
///
/// A photo shows the original on the left of a draggable divider and the
/// re-saved file on the right, both decoded from the same encode the saving
/// was measured on. A screenshot is re-saved losslessly, so there is only
/// one picture to show and a chip saying it is identical. Swiping pages
/// between files; the divider follows a tap anywhere, or a drag on its
/// handle.
class CompressViewerPage extends ConsumerStatefulWidget {
  const CompressViewerPage({
    required this.fileIds,
    required this.index,
    required this.quality,
    required this.lossless,
    required this.excluded,
    this.onExclude,
    super.key,
  });

  final List<String> fileIds;
  final int index;
  final int quality;
  final bool lossless;

  /// The list page's left-out set, read live so the button stays in step.
  final Set<String> excluded;
  final void Function(String fileId)? onExclude;

  static Route<void> route({
    required List<String> fileIds,
    required int index,
    required int quality,
    required bool lossless,
    required Set<String> excluded,
    void Function(String)? onExclude,
  }) => PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (BuildContext context, Animation<double> a, _) =>
        FadeTransition(
          opacity: a,
          child: CompressViewerPage(
            fileIds: fileIds,
            index: index,
            quality: quality,
            lossless: lossless,
            excluded: excluded,
            onExclude: onExclude,
          ),
        ),
  );

  @override
  ConsumerState<CompressViewerPage> createState() => _CompressViewerPageState();
}

class _CompressViewerPageState extends ConsumerState<CompressViewerPage> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _at = widget.index;

  /// Where the divider sits, 0 (all after) to 1 (all original).
  double _split = 0.5;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    final String current = widget.fileIds[_at];
    final bool left = widget.excluded.contains(current);
    final CompressComparison? shot = ref
        .watch(
          compressComparisonProvider((
            fileId: current,
            quality: widget.quality,
          )),
        )
        .value;

    return Material(
      // Photos are judged on black, as in the gallery.
      color: const Color(0xFF000000),
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pages,
            itemCount: widget.fileIds.length,
            onPageChanged: (int i) => setState(() {
              _at = i;
              _split = 0.5;
            }),
            itemBuilder: (BuildContext context, int i) => Padding(
              padding: EdgeInsets.only(
                top: inset.top + 64,
                bottom: inset.bottom + 132,
              ),
              child: _Stage(
                fileId: widget.fileIds[i],
                quality: widget.quality,
                lossless: widget.lossless,
                split: i == _at ? _split : 0.5,
                onSplit: (double v) => setState(() => _split = v),
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
                      context.s1(
                        '{} of ${GFormat.count(widget.fileIds.length)}',
                        GFormat.count(_at + 1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: GDesign.touch),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedSwitcher(
                  duration: GDesign.motion(context, GDesign.normal),
                  child: shot == null
                      ? const SizedBox(height: GDesign.chipHeight)
                      : PhotoChip(
                          key: ValueKey<String>(current),
                          '${GFormat.bytes(shot.originalBytes)} to '
                          '${GFormat.bytes(shot.newBytes)}',
                        ),
                ),
                ActionBar(
                  floating: true,
                  center: widget.onExclude == null
                      ? null
                      : PrimaryButton(
                          pill: true,
                          label: left
                              ? context.s('Include this one')
                              : context.s('Leave this one out'),
                          onTap: () {
                            Haptics.select();
                            widget.onExclude!(current);
                            setState(() {});
                          },
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

/// One file: both decodes stacked, the original clipped to the divider.
class _Stage extends ConsumerWidget {
  const _Stage({
    required this.fileId,
    required this.quality,
    required this.lossless,
    required this.split,
    required this.onSplit,
  });

  final String fileId;
  final int quality;
  final bool lossless;
  final double split;
  final ValueChanged<double> onSplit;

  /// Width of the divider's drag handle, the only area that takes
  /// horizontal drags away from the page swipe.
  static const double _handle = GDesign.touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final CompressComparison? shot = ref
        .watch(compressComparisonProvider((fileId: fileId, quality: quality)))
        .value;

    if (shot == null) {
      return Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(color: g.accent, strokeWidth: 2.2),
        ),
      );
    }

    final Widget after = Image.memory(
      shot.encoded,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );

    if (lossless) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          after,
          Align(
            alignment: Alignment.topCenter,
            child: PhotoChip(
              context.s1(
                'Identical, {} smaller',
                GFormat.bytes(shot.originalBytes - shot.newBytes),
              ),
              icon: GIcons.checkCircle,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double x = box.maxWidth * split;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // A tap anywhere moves the divider there.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails d) {
                Haptics.select();
                onSplit((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0));
              },
              child: after,
            ),
            ClipRect(
              clipper: _LeftOf(x),
              child: IgnorePointer(
                child: Image.memory(
                  shot.original,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
            // The divider line.
            Positioned(
              left: x - 1,
              top: 0,
              bottom: 0,
              child: const IgnorePointer(
                child: SizedBox(
                  width: 2,
                  child: ColoredBox(color: Color(0xE6FFFFFF)),
                ),
              ),
            ),
            // The handle: a glass knob centred on the line.
            Positioned(
              left: x - _handle / 2,
              top: 0,
              bottom: 0,
              width: _handle,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => Haptics.select(),
                onHorizontalDragUpdate: (DragUpdateDetails d) =>
                    onSplit(((x + d.delta.dx) / box.maxWidth).clamp(0.0, 1.0)),
                child: Center(
                  child: GlassSurface(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Icon(GIcons.sort, size: 18, color: g.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              start: GDesign.space12,
              top: GDesign.space12,
              child: AnimatedOpacity(
                opacity: split > 0.12 ? 1 : 0,
                duration: GDesign.motion(context, GDesign.fast),
                child: PhotoChip(context.s('Original')),
              ),
            ),
            PositionedDirectional(
              end: GDesign.space12,
              top: GDesign.space12,
              child: AnimatedOpacity(
                opacity: split < 0.88 ? 1 : 0,
                duration: GDesign.motion(context, GDesign.fast),
                child: PhotoChip(context.s('After')),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Clips to everything left of [x].
class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.x);

  final double x;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, x, size.height);

  @override
  bool shouldReclip(_LeftOf old) => old.x != x;
}
