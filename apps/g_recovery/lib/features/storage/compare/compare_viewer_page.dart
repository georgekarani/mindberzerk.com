import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/storage_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../../ui/file_thumbnail.dart';
import '../state/storage_providers.dart';

/// A set of similar photos side by side, full screen on black.
///
/// Swipe between them, pinch to check detail. A chip on each photo says
/// whether it is the one being kept, a strip along the bottom shows the
/// whole set with the keeper ringed, and one button makes the current photo
/// the keeper instead.
class CompareViewerPage extends ConsumerStatefulWidget {
  const CompareViewerPage({
    required this.fileIds,
    required this.sizes,
    required this.index,
    required this.keeperId,
    this.onKeep,
    super.key,
  });

  final List<String> fileIds;
  final Map<String, int> sizes;
  final int index;

  /// The photo being kept, or '' when nothing in the set is kept (blurred).
  final String keeperId;

  /// Called when the user picks a different keeper. Null hides the choice.
  final void Function(String fileId)? onKeep;

  static Route<void> route({
    required List<String> fileIds,
    required Map<String, int> sizes,
    required int index,
    required String keeperId,
    void Function(String)? onKeep,
  }) => PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (BuildContext context, Animation<double> a, _) =>
        FadeTransition(
          opacity: a,
          child: CompareViewerPage(
            fileIds: fileIds,
            sizes: sizes,
            index: index,
            keeperId: keeperId,
            onKeep: onKeep,
          ),
        ),
  );

  @override
  ConsumerState<CompareViewerPage> createState() => _CompareViewerPageState();
}

class _CompareViewerPageState extends ConsumerState<CompareViewerPage> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _at = widget.index;
  late String _keeper = widget.keeperId;

  /// While zoomed in, swiping pans the photo instead of paging.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _jump(int i) => _pages.animateToPage(
    i,
    duration: GDesign.motion(context, GDesign.normal),
    curve: GDesign.enter,
  );

  @override
  Widget build(BuildContext context) {
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    final String current = widget.fileIds[_at];
    final bool keeping = current == _keeper;
    final bool choosing = widget.onKeep != null;

    return Material(
      color: const Color(0xFF000000),
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pages,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.fileIds.length,
            onPageChanged: (int i) => setState(() {
              _at = i;
              _zoomed = false;
            }),
            itemBuilder: (BuildContext context, int i) => Padding(
              padding: EdgeInsets.only(
                top: inset.top + 64,
                bottom: inset.bottom + 176,
              ),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                onInteractionEnd: (_) {},
                onInteractionUpdate: (ScaleUpdateDetails d) {
                  final bool zoomed = d.scale > 1.01;
                  if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                },
                child: Image(
                  image: FileThumbnail(
                    fileId: widget.fileIds[i],
                    bridge: bridge,
                    maxPixels: 1600,
                  ),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
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
                    child: AnimatedSwitcher(
                      duration: GDesign.motion(context, GDesign.fast),
                      child: PhotoChip(
                        key: ValueKey<String>('$current$_keeper'),
                        !choosing
                            ? context.s1(
                                '{} of ${widget.fileIds.length}',
                                _at + 1,
                              )
                            : keeping
                            ? context.s('Keeping this one')
                            : context.s('Goes to the trash'),
                        icon: choosing
                            ? (keeping ? GIcons.checkCircle : GIcons.trash)
                            : null,
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
                _Strip(
                  fileIds: widget.fileIds,
                  bridge: bridge,
                  at: _at,
                  keeper: choosing ? _keeper : null,
                  onPick: _jump,
                ),
                const SizedBox(height: GDesign.space8),
                PhotoChip(GFormat.bytes(widget.sizes[current] ?? 0)),
                ActionBar(
                  floating: true,
                  center: choosing && !keeping
                      ? PrimaryButton(
                          pill: true,
                          label: context.s('Keep this one instead'),
                          onTap: () {
                            Haptics.confirm();
                            widget.onKeep!(current);
                            setState(() => _keeper = current);
                          },
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole set as small thumbnails: the one on screen is full opacity,
/// the keeper carries an accent ring.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.fileIds,
    required this.bridge,
    required this.at,
    required this.keeper,
    required this.onPick,
  });

  final List<String> fileIds;
  final StorageBridge bridge;
  final int at;
  final String? keeper;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Duration d = GDesign.motion(context, GDesign.fast);
    return SizedBox(
      height: 56,
      child: Center(
        child: ListView.separated(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          itemCount: fileIds.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (BuildContext context, int i) => Pressable(
            onTap: () => onPick(i),
            semanticLabel: context.s1('Photo {}', i + 1),
            child: AnimatedOpacity(
              duration: d,
              opacity: i == at ? 1 : 0.5,
              child: AnimatedContainer(
                duration: d,
                width: i == at ? 52 : 44,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: fileIds[i] == keeper
                        ? g.accent
                        : const Color(0x00000000),
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image(
                    image: FileThumbnail(fileId: fileIds[i], bridge: bridge),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
