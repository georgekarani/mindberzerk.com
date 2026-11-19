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

/// Sets of near-identical (or byte-identical) photos, one set per section.
///
/// The photo being kept leads each set, large, under a "Keeping this one"
/// chip. The others sit below it, ticked to go. Tapping a tile unticks it
/// to keep it too; holding a tile makes it the one that leads. One button
/// at the bottom trashes every ticked photo and turns them to dust.
class CompareReviewPage extends ConsumerStatefulWidget {
  const CompareReviewPage({required this.kind, super.key});

  /// 'similar' or 'exact'.
  final String kind;

  static Route<void> route(String kind) => MaterialPageRoute<void>(
    builder: (BuildContext context) => CompareReviewPage(kind: kind),
  );

  @override
  ConsumerState<CompareReviewPage> createState() => _CompareReviewPageState();
}

class _CompareReviewPageState extends ConsumerState<CompareReviewPage> {
  /// Per set: the photo that leads, then any others the user chose to keep.
  final Map<String, String> _lead = <String, String>{};
  final Map<String, Set<String>> _alsoKeep = <String, Set<String>>{};

  /// Sets already dealt with, hidden until the scan forgets them.
  final Set<String> _done = <String>{};
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  late final CompareController _compare;
  late final GShellNav _nav;
  bool _busy = false;

  bool get _exact => widget.kind == 'exact';

  @override
  void initState() {
    super.initState();
    _compare = ref.read(compareProvider.notifier);
    _nav = ref.read(gShellNavHiddenProvider.notifier)..hide();
  }

  @override
  void dispose() {
    _nav.show();
    if (_done.isNotEmpty) _compare.forgetGroups(_done);
    super.dispose();
  }

  GlobalKey _keyFor(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  String _leadOf(CompareGroup g) => _lead[g.groupId] ?? g.keepFileId;

  bool _keeps(CompareGroup g, String id) =>
      id == _leadOf(g) || (_alsoKeep[g.groupId]?.contains(id) ?? false);

  List<String> _goingIn(CompareGroup g) =>
      g.fileIds.where((String id) => !_keeps(g, id)).toList();

  int _sizeOf(CompareGroup g, String id) {
    final int i = g.fileIds.indexOf(id);
    return i >= 0 && i < g.sizes.length ? g.sizes[i] : 0;
  }

  int _freedBy(CompareGroup g) =>
      _goingIn(g).fold<int>(0, (int s, String id) => s + _sizeOf(g, id));

  void _toggle(CompareGroup g, String id) {
    if (id == _leadOf(g)) return;
    Haptics.select();
    setState(() {
      final Set<String> keep = _alsoKeep.putIfAbsent(
        g.groupId,
        () => <String>{},
      );
      if (!keep.remove(id)) keep.add(id);
    });
  }

  void _makeLead(CompareGroup g, String id) {
    setState(() {
      _alsoKeep[g.groupId]?.remove(id);
      _lead[g.groupId] = id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<CompareGroup> groups =
        (_exact
                ? ref.watch(exactGroupsProvider)
                : ref.watch(similarGroupsProvider))
            .where((CompareGroup g) => !_done.contains(g.groupId))
            .toList();
    final StorageBridge bridge = ref.watch(storageBridgeProvider);

    int count = 0;
    int freed = 0;
    for (final CompareGroup g in groups) {
      count += _goingIn(g).length;
      freed += _freedBy(g);
    }

    return LargeTitlePage(
      title: _exact ? context.s('Exact copies') : context.s('Similar photos'),
      backLabel: context.s('Clean up'),
      onBack: () => Navigator.of(context).pop(),
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.info,
          semanticLabel: context.s('How this works'),
          onTap: () => _explain(context),
        ),
      ],
      bottom: groups.isEmpty
          ? null
          : ActionBar(
              center: PrimaryButton(
                label: count == 0
                    ? context.s('Keeping everything')
                    : '${context.s1('Delete {}', GFormat.count(count))}, '
                          '${context.s1('free {}', GFormat.bytes(freed))}',
                destructive: true,
                busy: _busy,
                onTap: count == 0 || _busy ? null : () => _trash(groups),
              ),
            ),
      bottomExtent: groups.isEmpty ? 0 : ActionBar.extent(context),
      slivers: <Widget>[
        if (groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Empty(exact: _exact),
          )
        else ...<Widget>[
          SliverList.builder(
            itemCount: groups.length,
            itemBuilder: (BuildContext context, int i) {
              final CompareGroup g = groups[i];
              return _SetSection(
                group: g,
                bridge: bridge,
                lead: _leadOf(g),
                keeps: (String id) => _keeps(g, id),
                freed: _freedBy(g),
                keyFor: _keyFor,
                onToggle: (String id) => _toggle(g, id),
                onMakeLead: (String id) => _makeLead(g, id),
                onOpen: (String id) => _open(g, id),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space24)),
        ],
      ],
    );
  }

  void _open(CompareGroup g, String id) {
    Navigator.of(context, rootNavigator: true).push(
      CompareViewerPage.route(
        fileIds: g.fileIds,
        sizes: <String, int>{
          for (final String f in g.fileIds) f: _sizeOf(g, f),
        },
        index: g.fileIds.indexOf(id).clamp(0, g.fileIds.length - 1),
        keeperId: _leadOf(g),
        onKeep: (String f) => _makeLead(g, f),
      ),
    );
  }

  Future<void> _trash(List<CompareGroup> groups) async {
    final List<String> ids = <String>[
      for (final CompareGroup g in groups) ..._goingIn(g),
    ];
    final int freed = groups.fold<int>(
      0,
      (int s, CompareGroup g) => s + _freedBy(g),
    );
    if (ids.isEmpty) return;

    setState(() => _busy = true);
    final TrashResult result = await trashFiles(ref, ids);
    if (!mounted) return;

    await dustAway(context, ids.where(result.done.contains), _keys);
    if (!mounted) return;

    setState(() {
      _busy = false;
      for (final CompareGroup g in groups) {
        if (_goingIn(g).every(result.done.contains)) _done.add(g.groupId);
      }
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
            Text(
              _exact ? context.s('Identical copies') : context.s('Near copies'),
              style: g.title2(),
            ),
            const SizedBox(height: GDesign.space12),
            Text(
              _exact
                  ? context.s(
                      'Every file in a set is byte for byte the same as the '
                      'others, so the space freed is exact.',
                    )
                  : context.s(
                      'These look like the same picture when their shapes and '
                      'edges are compared. They are not identical: one may be a '
                      'crop, another exposure, or the frame where nobody blinked.',
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

/// One set: the kept photo large, the rest as ticked tiles below.
class _SetSection extends StatelessWidget {
  const _SetSection({
    required this.group,
    required this.bridge,
    required this.lead,
    required this.keeps,
    required this.freed,
    required this.keyFor,
    required this.onToggle,
    required this.onMakeLead,
    required this.onOpen,
  });

  final CompareGroup group;
  final StorageBridge bridge;
  final String lead;
  final bool Function(String id) keeps;
  final int freed;
  final GlobalKey Function(String id) keyFor;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onMakeLead;
  final ValueChanged<String> onOpen;

  static const double _tile = 96;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<String> others = group.fileIds
        .where((String id) => id != lead)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: GDesign.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: Text(
                    context.s1(
                      '{} photos',
                      GFormat.count(group.fileIds.length),
                    ),
                    style: g.headline(),
                  ),
                ),
                Text(
                  freed == 0
                      ? context.s('Keeping all')
                      : context.s1('Frees {}', GFormat.bytes(freed)),
                  style: g.figures(g.footnote()),
                ),
              ],
            ),
          ),
          const SizedBox(height: GDesign.space12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            child: Pressable(
              onTap: () => onOpen(lead),
              scale: 0.98,
              semanticLabel: context.s('Keeping this one. Open'),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(GDesign.cardRadius),
                      child: SizedPhoto(
                        image: FileThumbnail(
                          fileId: lead,
                          bridge: bridge,
                          maxPixels: 1080,
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: GDesign.space12,
                      top: GDesign.space12,
                      child: PhotoChip(
                        context.s('Keeping this one'),
                        icon: GIcons.check,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: GDesign.space12),
          SizedBox(
            height: _tile,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
              itemCount: others.length,
              separatorBuilder: (_, _) => const SizedBox(width: GDesign.space8),
              itemBuilder: (BuildContext context, int i) {
                final String id = others[i];
                final bool going = !keeps(id);
                return SizedBox.square(
                  dimension: _tile,
                  child: Pressable(
                    onTap: () => onToggle(id),
                    onLongPress: () => onMakeLead(id),
                    haptic: false,
                    selected: going,
                    semanticLabel: going
                        ? context.s('Will be deleted. Tap to keep')
                        : context.s('Kept. Tap to delete'),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        RepaintBoundary(
                          key: keyFor(id),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              GDesign.tileRadius,
                            ),
                            child: AnimatedOpacity(
                              opacity: going ? 1 : 0.55,
                              duration: GDesign.motion(context, GDesign.fast),
                              child: SizedPhoto(
                                image: FileThumbnail(
                                  fileId: id,
                                  bridge: bridge,
                                ),
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          end: GDesign.space4,
                          top: GDesign.space4,
                          child: SelectMark(selected: going),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.exact});

  final bool exact;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(GDesign.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(GIcons.checkCircle, size: 40, color: g.muted),
          const SizedBox(height: GDesign.space12),
          Text(
            exact
                ? context.s('No copies left')
                : context.s('No similar photos left'),
            style: g.headline(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GDesign.space4),
          Text(
            context.s('Anything you deleted waits in Recovery for 30 days.'),
            style: g.footnote(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
