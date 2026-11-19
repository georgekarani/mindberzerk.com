import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../app/shell.dart';
import '../../../bridge/compare_api.g.dart';
import '../../../bridge/compare_bridge.dart';
import '../../../bridge/storage_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../../ui/file_thumbnail.dart';
import '../state/cleanup_actions.dart';
import '../state/storage_providers.dart';
import 'compare_viewer_page.dart';

/// Photos that scored soft, softest first, in one grid.
///
/// Some blur is deliberate, so nothing starts selected. Tap to pick, hold
/// to look closer. One button trashes the picked photos and turns them to
/// dust.
class BlurReviewPage extends ConsumerStatefulWidget {
  const BlurReviewPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const BlurReviewPage(),
  );

  @override
  ConsumerState<BlurReviewPage> createState() => _BlurReviewPageState();
}

class _BlurReviewPageState extends ConsumerState<BlurReviewPage> {
  final Set<String> _picked = <String>{};

  /// Already trashed, hidden until the scan forgets them.
  final Set<String> _done = <String>{};
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  late final CompareController _compare;
  late final GShellNav _nav;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _compare = ref.read(compareProvider.notifier);
    _nav = ref.read(gShellNavHiddenProvider.notifier)..hide();
  }

  @override
  void dispose() {
    _nav.show();
    if (_done.isNotEmpty) _compare.forgetBlurred(_done);
    super.dispose();
  }

  GlobalKey _keyFor(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  void _toggle(String id) {
    Haptics.select();
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    final List<BlurredImage> blurred = ref
        .watch(blurredProvider)
        .where((BlurredImage b) => !_done.contains(b.fileId))
        .toList();
    final int bytes = blurred
        .where((BlurredImage b) => _picked.contains(b.fileId))
        .fold<int>(0, (int s, BlurredImage b) => s + b.sizeBytes);
    final bool all = blurred.isNotEmpty && _picked.length == blurred.length;

    return LargeTitlePage(
      title: context.s('Blurred'),
      backLabel: context.s('Clean up'),
      onBack: () => Navigator.of(context).pop(),
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.info,
          semanticLabel: context.s('How this is measured'),
          onTap: () => _explain(context),
        ),
      ],
      bottom: blurred.isEmpty
          ? null
          : ActionBar(
              leading: BarIconButton(
                icon: GIcons.checkCircle,
                semanticLabel: all
                    ? context.s('Select none')
                    : context.s('Select all'),
                onTap: () => setState(() {
                  if (all) {
                    _picked.clear();
                  } else {
                    _picked.addAll(blurred.map((BlurredImage b) => b.fileId));
                  }
                }),
              ),
              center: PrimaryButton(
                label: _picked.isEmpty
                    ? context.s('Tap photos to pick')
                    : '${context.s1('Delete {}', GFormat.count(_picked.length))}, '
                          '${context.s1('free {}', GFormat.bytes(bytes))}',
                destructive: true,
                busy: _busy,
                onTap: _picked.isEmpty || _busy ? null : _trash,
              ),
            ),
      bottomExtent: blurred.isEmpty ? 0 : ActionBar.extent(context),
      slivers: <Widget>[
        if (blurred.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                context.s('Everything looks sharp.'),
                style: g.footnote(),
              ),
            ),
          )
        else ...<Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: blurred.length,
              itemBuilder: (BuildContext context, int i) {
                final BlurredImage b = blurred[i];
                return RepaintBoundary(
                  key: _keyFor(b.fileId),
                  child: PhotoGridTile(
                    image: FileThumbnail(fileId: b.fileId, bridge: bridge),
                    selected: _picked.contains(b.fileId),
                    onTap: () => _toggle(b.fileId),
                    onLongPress: () => _open(blurred, i),
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space24)),
        ],
      ],
    );
  }

  void _open(List<BlurredImage> blurred, int at) {
    Navigator.of(context, rootNavigator: true).push(
      CompareViewerPage.route(
        fileIds: blurred.map((BlurredImage b) => b.fileId).toList(),
        sizes: <String, int>{
          for (final BlurredImage b in blurred) b.fileId: b.sizeBytes,
        },
        index: at,
        keeperId: '',
      ),
    );
  }

  Future<void> _trash() async {
    final List<String> ids = _picked.toList();
    final int freed = ref
        .read(blurredProvider)
        .where((BlurredImage b) => _picked.contains(b.fileId))
        .fold<int>(0, (int s, BlurredImage b) => s + b.sizeBytes);

    setState(() => _busy = true);
    final TrashResult result = await trashFiles(ref, ids);
    if (!mounted) return;

    await dustAway(context, ids.where(result.done.contains), _keys);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _done.addAll(result.done);
      _picked.removeAll(result.done);
    });
    reportTrash(context, result, freed);
    ref.invalidate(storageOverviewProvider);
  }

  void _explain(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space8,
            GDesign.gutter,
            GDesign.space24,
          ),
          children: <Widget>[
            Text(context.s('How this is measured'), style: g.title2()),
            const SizedBox(height: GDesign.space12),
            Text(
              context.s(
                'Each photo is scored on how sharply its brightness changes. '
                'A sharp picture has hard edges somewhere; a soft one changes '
                'gently everywhere. Night shots and close ups can score soft '
                'and still be exactly what you wanted.',
              ),
              style: g.body(color: g.muted),
            ),
            const SizedBox(height: GDesign.space12),
            Text(
              context.s(
                'Nothing is deleted for good. Photos go to the system trash and '
                'can come back from Recovery for 30 days.',
              ),
              style: g.body(color: g.muted),
            ),
          ],
        );
      },
    );
  }
}
