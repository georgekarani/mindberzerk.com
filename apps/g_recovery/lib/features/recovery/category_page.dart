import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/recovery_bridge.dart';
import '../../bridge/storage_api.g.dart';
import '../../bridge/storage_bridge.dart';
import '../../core/date_groups.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/file_thumbnail.dart';
import '../../ui/g_sort.dart';
import '../../ui/g_thumbnail.dart';
import '../../ui/media/media_peek.dart';
import '../../ui/media/media_stage.dart';
import '../../ui/media/playable_media.dart';
import '../home/widgets/empty_scenes.dart';
import '../review/review_page.dart';
import '../viewer/media_viewer.dart';
import '../storage/state/storage_files.dart';
import '../storage/state/storage_providers.dart';
import 'state/recovery_actions.dart';
import 'state/recovery_providers.dart';
import 'state/view_prefs.dart';
import 'widgets/grid_tools.dart';

/// One category of what can come back: an edge-to-edge photo grid for
/// pictures and video, rows on a card for everything else, grouped by the
/// day each item was deleted.
///
/// Select turns the tab bar into a toolbar with one primary action. Restore
/// flies each photo home; Delete for good turns it to dust.
class CategoryPage extends ConsumerStatefulWidget {
  const CategoryPage({
    required this.query,
    required this.title,
    super.key,
    this.backLabel,
  });

  final RecoveryQuery query;
  final String title;

  /// The previous screen's title, shown beside the back chevron.
  final String? backLabel;

  static Route<void> route({
    required String title,
    String? kind,
    List<String> sourceIds = kAllSourceIds,
    Set<String> roles = kRolesDeleted,
    String? backLabel,
  }) => MaterialPageRoute<void>(
    builder: (BuildContext context) => CategoryPage(
      title: title,
      backLabel: backLabel,
      query: RecoveryQuery(sourceIds: sourceIds, kind: kind, roles: roles),
    ),
  );

  /// Media still inside a chat app can be looked at, never restored or purged.
  bool get viewOnly => query.roles.every((String r) => r == kRoleMedia);

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

/// The three groups a photo or video can belong to, as segments.
enum _Group {
  deleted(kRolesDeleted),
  previews(<String>{kRoleCache}),
  inApps(<String>{kRoleMedia});

  const _Group(this.roles);

  final Set<String> roles;

  String label(BuildContext context) => switch (this) {
    _Group.deleted => context.s('Deleted'),
    _Group.previews => context.s('Previews'),
    _Group.inApps => context.s('In chat apps'),
  };
}

/// How a picture category is laid out.
enum _View { grid, list, shelf }

class _CategoryPageState extends ConsumerState<CategoryPage>
    with TickerProviderStateMixin {
  bool _selecting = false;

  /// Held from initState: ref may not be used once the widget is disposing.
  late final GShellNav _nav;
  late _Group? _group = _initialGroup();

  /// Snapshot targets for the flight and the dust, one per item on screen.
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  /// Section headers, so opening a case on the shelf can scroll to it.
  final Map<String, GlobalKey> _headers = <String, GlobalKey>{};

  /// Drives the timeline scrubber.
  final ScrollController _scroll = ScrollController();

  /// Grid, list of rows, or sections as stacked cases.
  _View _view = _View.grid;

  /// The thumbnail inside each list row, so the morph knows where it lands.
  final Map<String, GlobalKey> _thumbs = <String, GlobalKey>{};

  /// Items whose own picture is hidden while a flying copy moves over it.
  Set<String> _flying = <String>{};

  /// Photos and video by kind, plus statuses and previews, which are
  /// pictures whatever their kind field says.
  bool get _visual =>
      _pictureKind ||
      widget.query.roles.contains(kRoleStatus) ||
      widget.query.roles.contains(kRoleCache);

  bool get _pictureKind =>
      widget.query.kind == 'image' || widget.query.kind == 'video';

  /// Statuses are tall phone-screen pictures, so they get two tall columns.
  bool get _statuses => _query.roles.contains(kRoleStatus);

  /// Segments only make sense for pictures opened from their deleted set.
  _Group? _initialGroup() {
    if (!_pictureKind) return null;
    for (final _Group g in _Group.values) {
      if (setEquals(g.roles, widget.query.roles)) return g;
    }
    return null;
  }

  RecoveryQuery get _query => _group == null
      ? widget.query
      : RecoveryQuery(
          sourceIds: widget.query.sourceIds,
          kind: widget.query.kind,
          roles: _group!.roles,
        );

  bool get _viewOnly => _query.roles.every((String r) => r == kRoleMedia);

  GlobalKey _keyFor(String itemId) =>
      _keys.putIfAbsent(itemId, () => GlobalKey(debugLabel: itemId));

  @override
  void initState() {
    super.initState();
    _nav = ref.read(gShellNavHiddenProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectionProvider.notifier).clear();
      ref.read(scanControllerProvider.notifier).ensure(widget.query.sourceIds);
    });
  }

  @override
  void dispose() {
    if (_selecting) _nav.show();
    _scroll.dispose();
    super.dispose();
  }

  void _setSelecting(bool on) {
    if (on == _selecting) return;
    if (on) {
      _nav.hide();
    } else {
      _nav.show();
    }
    if (!on) ref.read(selectionProvider.notifier).clear();
    setState(() => _selecting = on);
  }

  void _toggle(String itemId) {
    Haptics.select();
    ref.read(selectionProvider.notifier).toggle(itemId);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<BackgroundScanState?>>(backgroundScanProvider, (
      AsyncValue<BackgroundScanState?>? previous,
      AsyncValue<BackgroundScanState?> next,
    ) {
      final bool was = previous?.value?.running ?? false;
      final bool now = next.value?.running ?? false;
      if (was && !now) ref.invalidate(recoveryItemsProvider);
    });

    final AsyncValue<List<RecoverableItem>> async = ref.watch(
      recoveryItemsProvider(_query),
    );
    final Set<String> selected = ref.watch(selectionProvider);
    final GSortMode sort = ref.watch(gSortProvider);
    final List<RecoverableItem> items = _ordered(
      async.value ?? const <RecoverableItem>[],
      sort,
    );
    final List<String> chosen = <String>[
      for (final RecoverableItem item in items)
        if (selected.contains(item.itemId)) item.itemId,
    ];
    final int columns = ref.watch(gridColumnsProvider);
    final GroupBy groupBy = ref.watch(groupByProvider);
    final List<DateGroup<RecoverableItem>> groups = _grouped(
      items,
      sort,
      groupBy,
    );
    final bool shelf =
        _view == _View.shelf && _visual && !_selecting && groups.length > 1;

    final String title = _selecting
        ? (chosen.isEmpty
              ? context.s('Select items')
              : context.s1('{} selected', GFormat.count(chosen.length)))
        : widget.title;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _setSelecting(false);
      },
      child: Stack(
        children: <Widget>[
          PinchColumns(
            onStep: ({required bool fewer}) => _visual && _view == _View.grid
                ? ref.read(gridColumnsProvider.notifier).step(fewer: fewer)
                : false,
            child: LargeTitlePage(
              controller: _scroll,
              title: title,
              onBack: () {
                if (_selecting) {
                  _setSelecting(false);
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              backLabel: widget.backLabel,
              actions: <Widget>[
                if (!_selecting && items.isNotEmpty)
                  NavAction.icon(
                    icon: GIcons.more,
                    semanticLabel: context.s('More options'),
                    onTap: () => _options(context, items),
                  ),
                if (_selecting)
                  NavAction.text(
                    label: context.s('Done'),
                    onTap: () => _setSelecting(false),
                  ),
              ],
              pinned: _group == null
                  ? null
                  : Segmented<_Group>(
                      segments: <(_Group, String)>[
                        for (final _Group g in _Group.values)
                          (g, g.label(context)),
                      ],
                      value: _group!,
                      onChanged: (_Group next) {
                        _setSelecting(false);
                        setState(() => _group = next);
                      },
                    ),
              pinnedExtent: _group == null ? 0 : Segmented.extent,
              onRefresh: () async {
                ref.read(scanControllerProvider.notifier).run(_query.sourceIds);
                ref.invalidate(recoveryItemsProvider(_query));
                await ref.read(recoveryItemsProvider(_query).future);
              },
              bottom: _selecting
                  ? ActionBar(
                      leading: BarIconButton(
                        icon: GIcons.checkCircle,
                        semanticLabel: chosen.length == items.length
                            ? context.s('Deselect all')
                            : context.s('Select all'),
                        onTap: () => _selectAll(items, chosen),
                      ),
                      center: PrimaryButton(
                        pill: true,
                        label: chosen.isEmpty
                            ? _verb(context, items, chosen)
                            : '${_verb(context, items, chosen)} '
                                  '${GFormat.count(chosen.length)}',
                        onTap: chosen.isEmpty ? null : () => _restore(chosen),
                      ),
                      trailing: BarIconButton(
                        icon: GIcons.trash,
                        semanticLabel: context.s('Delete for good'),
                        onTap: chosen.isEmpty ? null : () => _delete(chosen),
                      ),
                    )
                  : null,
              bottomExtent: _selecting ? ActionBar.extent(context) : 0,
              slivers: <Widget>[
                const SliverToBoxAdapter(child: _Progress()),
                if (items.isEmpty)
                  SliverToBoxAdapter(
                    child: _Empty(loading: async.isLoading, query: _query),
                  )
                else ...<Widget>[
                  SliverToBoxAdapter(child: _Facts(items: items)),
                  if (shelf)
                    _shelfSliver(context, groups)
                  else
                    for (final DateGroup<RecoverableItem> group in groups)
                      ..._groupSlivers(
                        context,
                        group,
                        items,
                        selected,
                        columns,
                      ),
                ],
              ],
            ),
          ),
          if (!shelf)
            Positioned.fill(
              child: TimelineScrubber(
                controller: _scroll,
                top: MediaQuery.paddingOf(context).top + GDesign.navBarHeight,
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    (_selecting
                        ? ActionBar.extent(context)
                        : GDesign.tabBarHeight + GDesign.space16),
                labelAt: (double f) => groups.isEmpty
                    ? null
                    : groups[sectionAt(f, <int>[
                            for (final DateGroup<RecoverableItem> g in groups)
                              g.count,
                          ])]
                          .label,
              ),
            ),
        ],
      ),
    );
  }

  /// Every section as a case of stacked prints, two to a row. Opening one
  /// goes back to the grid, scrolled to that section.
  Widget _shelfSliver(
    BuildContext context,
    List<DateGroup<RecoverableItem>> groups,
  ) {
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space16,
        GDesign.gutter,
        GDesign.space32,
      ),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: GDesign.space24,
          crossAxisSpacing: GDesign.space16,
          childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
          final DateGroup<RecoverableItem> group = groups[i];
          return Reveal(
            index: i,
            child: ShelfCase(
              label: group.label,
              detail:
                  '${GFormat.count(group.count)}, ${GFormat.bytes(group.bytes)}',
              images: <ImageProvider>[
                for (final RecoverableItem item in group.items.take(3))
                  ItemThumbnail(
                    itemId: item.itemId,
                    bridge: bridge,
                    maxPixels: 360,
                  ),
              ],
              onOpen: () => _openSection(group.label),
            ),
          );
        }, childCount: groups.length),
      ),
    );
  }

  /// Where a keyed box sits on screen, or null when it is not laid out.
  static Rect? _rectOf(GlobalKey? key) {
    final RenderObject? box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Every keyed box that is at least partly on screen.
  Map<String, Rect> _onScreen(Map<String, GlobalKey> keys) {
    final Size screen = MediaQuery.sizeOf(context);
    final Rect bounds = Offset.zero & screen;
    return <String, Rect>{
      for (final MapEntry<String, GlobalKey> e in keys.entries)
        if (_rectOf(e.value) case final Rect r when r.overlaps(bounds))
          e.key: r,
    };
  }

  /// Changes the layout. Between grid and list, every picture on screen
  /// flies from its tile to its row's thumbnail (or back) while the new
  /// layout settles under it; anything else simply swaps.
  Future<void> _switchView(_View next) async {
    if (next == _view || !mounted) return;
    Haptics.select();
    final bool morph =
        !MediaQuery.disableAnimationsOf(context) &&
        _view != _View.shelf &&
        next != _View.shelf;
    if (!morph) {
      setState(() => _view = next);
      return;
    }

    final bool toList = next == _View.list;
    final Map<String, Rect> from = _onScreen(toList ? _keys : _thumbs);
    // In list mode _keys holds whole rows; only the grid's _keys are tiles.
    if (from.isEmpty) {
      setState(() => _view = next);
      return;
    }
    // The picture nearest the top stays put, so the user keeps their place.
    final String anchor = from.entries
        .reduce(
          (MapEntry<String, Rect> a, MapEntry<String, Rect> b) =>
              a.value.top <= b.value.top ? a : b,
        )
        .key;

    setState(() {
      _view = next;
      _flying = from.keys.toSet();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final Map<String, GlobalKey> targets = toList ? _thumbs : _keys;
    final Rect? landed = _rectOf(targets[anchor]);
    if (landed != null && _scroll.hasClients) {
      final ScrollPosition p = _scroll.position;
      final double to = (p.pixels + landed.top - from[anchor]!.top).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      );
      if (to != p.pixels) {
        p.jumpTo(to);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
    }

    final Map<String, Rect> to = _onScreen(targets);
    final List<String> ids = <String>[
      for (final String id in from.keys)
        if (to.containsKey(id)) id,
    ];
    if (ids.isEmpty) {
      setState(() => _flying = <String>{});
      return;
    }
    await _fly(ids, from, to, toList: toList);
    if (mounted) setState(() => _flying = <String>{});
  }

  /// Draws a copy of each picture over the page and moves it between two
  /// rects, rounding its corners on the way into a row.
  Future<void> _fly(
    List<String> ids,
    Map<String, Rect> from,
    Map<String, Rect> to, {
    required bool toList,
  }) async {
    final OverlayState overlay = Overlay.of(context);
    final RenderBox host = overlay.context.findRenderObject()! as RenderBox;
    final Offset origin = host.localToGlobal(Offset.zero);
    final RecoveryBridge bridge = ref.read(recoveryBridgeProvider);
    final AnimationController run = AnimationController(
      vsync: this,
      duration: GDesign.slow,
    );
    final Animation<double> t = CurvedAnimation(
      parent: run,
      curve: Springs.standardCurve,
    );
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => IgnorePointer(
        child: AnimatedBuilder(
          animation: t,
          builder: (BuildContext _, Widget? _) => Stack(
            children: <Widget>[
              for (final String id in ids)
                Positioned.fromRect(
                  rect: Rect.lerp(from[id], to[id], t.value)!.shift(-origin),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      _PhotoRow.radius * (toList ? t.value : 1 - t.value),
                    ),
                    child: SizedPhoto(
                      image: ItemThumbnail(
                        itemId: id,
                        bridge: bridge,
                        maxPixels: 360,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      await run.forward();
    } finally {
      entry.remove();
      run.dispose();
    }
  }

  /// Leaves the shelf and brings the chosen section's header into view.
  void _openSection(String label) {
    setState(() => _view = _View.grid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? header = _headers[label]?.currentContext;
      if (header == null) return;
      Scrollable.ensureVisible(
        header,
        duration: GDesign.motion(context, GDesign.slow),
        curve: GDesign.enter,
      );
    });
  }

  /// A day's header, then its photos as a grid or its files as rows.
  List<Widget> _groupSlivers(
    BuildContext context,
    DateGroup<RecoverableItem> group,
    List<RecoverableItem> all,
    Set<String> selected,
    int columns,
  ) {
    final GDesignTheme g = GDesignTheme.of(context);
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    final List<String> ids = <String>[
      for (final RecoverableItem item in group.items) item.itemId,
    ];
    final bool allOn = ids.every(selected.contains);

    final Widget header = Padding(
      key: _headers.putIfAbsent(
        group.label,
        () => GlobalKey(debugLabel: group.label),
      ),
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        GDesign.space8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                group.label,
                style: g.headline(color: group.dated ? g.text : g.muted),
              ),
            ),
          ),
          if (_selecting)
            Pressable(
              onTap: () => _selectGroup(ids, allOn),
              child: SizedBox(
                height: GDesign.touch,
                child: Center(
                  child: Text(
                    allOn ? context.s('Deselect') : context.s('Select'),
                    style: g.footnote(color: g.text, weight: FontWeight.w600),
                  ),
                ),
              ),
            )
          else
            Text(
              '${GFormat.count(group.count)}, ${GFormat.bytes(group.bytes)}',
              style: g.figures(g.footnote()),
            ),
        ],
      ),
    );

    if (_visual && _view == _View.list) {
      return <Widget>[
        SliverToBoxAdapter(child: header),
        SliverList.builder(
          itemCount: group.items.length,
          itemBuilder: (BuildContext context, int i) {
            final RecoverableItem item = group.items[i];
            return RepaintBoundary(
              key: _keyFor(item.itemId),
              child: _PhotoRow(
                item: item,
                image: ItemThumbnail(
                  itemId: item.itemId,
                  bridge: bridge,
                  maxPixels: 360,
                ),
                thumbKey: _thumbs.putIfAbsent(
                  item.itemId,
                  () => GlobalKey(debugLabel: 'thumb-${item.itemId}'),
                ),
                hidden: _flying.contains(item.itemId),
                selected: _selecting ? selected.contains(item.itemId) : null,
                onTap: () => _tap(context, all, item),
                onLongPress: _selecting
                    ? () => _toggle(item.itemId)
                    : () => _peek(context, all, item),
              ),
            );
          },
        ),
      ];
    }

    if (_visual) {
      return <Widget>[
        SliverToBoxAdapter(child: header),
        SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            // Statuses are tall, so they run one column fewer.
            crossAxisCount: _statuses ? math.max(2, columns - 1) : columns,
            childAspectRatio: _statuses ? 9 / 16 : 1,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
            final RecoverableItem item = group.items[i];
            final bool on = selected.contains(item.itemId);
            return RepaintBoundary(
              key: _keyFor(item.itemId),
              child: Opacity(
                opacity: _flying.contains(item.itemId) ? 0 : 1,
                child: PhotoGridTile(
                  image: ItemThumbnail(
                    itemId: item.itemId,
                    bridge: bridge,
                    maxPixels: 360,
                  ),
                  heroTag: 'item-${item.itemId}',
                  selected: _selecting ? on : null,
                  badge: item.durationMillis == null
                      ? null
                      : PhotoChip(
                          GFormat.duration(
                            Duration(milliseconds: item.durationMillis!),
                          ),
                        ),
                  onTap: () => _tap(context, all, item),
                  onLongPress: _selecting
                      ? () => _toggle(item.itemId)
                      : () => _peek(context, all, item),
                ),
              ),
            );
          }, childCount: group.items.length),
        ),
      ];
    }

    return <Widget>[
      SliverToBoxAdapter(child: header),
      SliverToBoxAdapter(
        child: GroupedSection(
          children: <Widget>[
            for (final RecoverableItem item in group.items)
              RepaintBoundary(
                key: _keyFor(item.itemId),
                child: ListRow(
                  icon:
                      PlayableMedia.canPlay(item.kind, item.mimeType) &&
                          !_selecting
                      ? null
                      : _kindIcon(item.kind),
                  leading:
                      PlayableMedia.canPlay(item.kind, item.mimeType) &&
                          !_selecting
                      ? PlayRing(media: PlayableMedia.recoverable(item, bridge))
                      : null,
                  title: item.name,
                  subtitle: GFormat.bytes(item.sizeBytes),
                  trailing: _selecting
                      ? SelectMark(selected: selected.contains(item.itemId))
                      : null,
                  onTap: () => _tap(context, all, item),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  /// A closer look on long press: the photo large, or the video playing
  /// silently, with Select and Open under it.
  void _peek(
    BuildContext context,
    List<RecoverableItem> all,
    RecoverableItem item,
  ) {
    final RecoveryBridge bridge = ref.read(recoveryBridgeProvider);
    final Widget still = SizedPhoto(
      image: ItemThumbnail(
        itemId: item.itemId,
        bridge: bridge,
        maxPixels: 1080,
      ),
    );
    final int? w = item.width;
    final int? h = item.height;
    showMediaPeek(
      context,
      aspectRatio: w != null && h != null && w > 0 && h > 0 ? w / h : 3 / 4,
      preview: item.kind == 'video'
          ? MediaStage(
              media: PlayableMedia.recoverable(item, bridge),
              fallback: still,
              compact: true,
            )
          : still,
      actions: <PeekAction>[
        PeekAction(
          label: context.s('Open'),
          icon: GIcons.external,
          onTap: () => _open(context, all, item),
        ),
        if (!_viewOnly)
          PeekAction(
            label: context.s('Select'),
            icon: GIcons.checkCircle,
            onTap: () {
              _setSelecting(true);
              _toggle(item.itemId);
            },
          ),
      ],
    );
  }

  /// Toggles while selecting, opens the viewer otherwise.
  void _tap(
    BuildContext context,
    List<RecoverableItem> all,
    RecoverableItem item,
  ) {
    if (_selecting) {
      _toggle(item.itemId);
    } else {
      _open(context, all, item);
    }
  }

  void _selectGroup(List<String> ids, bool allOn) {
    Haptics.select();
    final SelectionController controller = ref.read(selectionProvider.notifier);
    final Set<String> selected = ref.read(selectionProvider);
    for (final String id in ids) {
      if (selected.contains(id) == allOn) controller.toggle(id);
    }
  }

  void _selectAll(List<RecoverableItem> items, List<String> chosen) {
    final bool clear = chosen.length == items.length;
    _selectGroup(<String>[
      for (final RecoverableItem i in items) i.itemId,
    ], clear);
  }

  void _open(
    BuildContext context,
    List<RecoverableItem> all,
    RecoverableItem item,
  ) {
    // A lone photo opens on its string rather than as a viewer of one.
    if (_visual && all.length == 1 && !_viewOnly) {
      openHangingReview(context, ref, all);
      return;
    }
    Navigator.of(context).push(
      MediaViewer.route(
        items: all,
        index: all.indexOf(item),
        heroPrefix: 'item',
        viewOnly: _viewOnly,
      ),
    );
  }

  /// Restores, then flies each confirmed photo home before the list
  /// refreshes. Only the first two dozen fly; the rest are restored all the
  /// same, and a flock of hundreds would only hide the screen.
  Future<void> _restore(List<String> ids) async {
    final RecoveryActionResult result = await runRecoveryAction(
      ref,
      ids,
      purge: false,
    );
    if (!mounted) return;
    int n = 0;
    for (final String id in ids) {
      final GlobalKey? key = _keys[id];
      if (!result.done.contains(id) || key == null || n >= 24) continue;
      await Flight.home(
        context,
        key,
        stagger: Duration(milliseconds: 30 * n++),
      );
      if (!mounted) return;
    }
    reportRecoveryProblem(context, result);
    _setSelecting(false);
    refreshRecovery(ref);
  }

  /// Asks first, deletes, then turns each confirmed item to dust.
  Future<void> _delete(List<String> ids) async {
    final bool go = await showConfirmSheet(
      context: context,
      title: ids.length == 1
          ? context.s('Delete 1 item for good')
          : context.s1('Delete {} items for good', GFormat.count(ids.length)),
      message: context.s(
        'These leave the trash for good. This app cannot bring them back '
        'afterwards, and neither can anything else.',
      ),
      confirmLabel: context.s('Delete'),
      cancelLabel: context.s('Keep'),
    );
    if (!go || !mounted) return;

    final RecoveryActionResult result = await runRecoveryAction(
      ref,
      ids,
      purge: true,
    );
    if (!mounted) return;
    int n = 0;
    for (final String id in ids) {
      final GlobalKey? key = _keys[id];
      if (!result.done.contains(id) || key == null || n++ >= 24) continue;
      await Dust.scatter(context, key);
      if (!mounted) return;
    }
    reportRecoveryProblem(context, result);
    _setSelecting(false);
    refreshRecovery(ref);
  }

  /// Sort order and the one-by-one review, kept off the bar.
  Future<void> _options(BuildContext context, List<RecoverableItem> items) {
    final List<RecoverableItem> reviewable = items
        .where((RecoverableItem i) => i.kind == 'image' || i.kind == 'video')
        .toList();
    return presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GSortMode sort = ref.read(gSortProvider);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: GDesign.space16),
          children: <Widget>[
            if (_visual)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  GDesign.space8,
                  GDesign.gutter,
                  GDesign.space24,
                ),
                child: Segmented<_View>(
                  semanticLabel: context.s('View'),
                  segments: <(_View, String)>[
                    (_View.grid, context.s('Grid')),
                    (_View.list, context.s('List')),
                    (_View.shelf, context.s('Shelf')),
                  ],
                  value: _view,
                  onChanged: (_View next) {
                    Navigator.of(sheet).pop();
                    // After the sheet starts closing, so the morph is seen.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _switchView(next),
                    );
                  },
                ),
              ),
            if (!_viewOnly) ...<Widget>[
              GroupedSection(
                children: <Widget>[
                  ListRow(
                    icon: GIcons.checkCircle,
                    title: context.s('Select'),
                    onTap: () {
                      Navigator.of(sheet).pop();
                      _setSelecting(true);
                    },
                  ),
                  if (reviewable.isNotEmpty)
                    ListRow(
                      icon: GIcons.images,
                      title: context.s('Review one by one'),
                      onTap: () {
                        Navigator.of(sheet).pop();
                        openHangingReview(context, ref, reviewable);
                      },
                    ),
                ],
              ),
              const SizedBox(height: GDesign.space24),
            ],
            GroupedSection(
              header: context.s('Group by'),
              children: <Widget>[
                for (final GroupBy mode in GroupBy.values)
                  ListRow(
                    title: context.s(mode.label),
                    trailing: mode == ref.read(groupByProvider)
                        ? Icon(
                            GIcons.check,
                            size: 20,
                            color: GDesignTheme.of(sheet).accentText,
                          )
                        : const SizedBox(width: 20),
                    onTap: () {
                      ref.read(groupByProvider.notifier).select(mode);
                      Navigator.of(sheet).pop();
                    },
                  ),
              ],
            ),
            const SizedBox(height: GDesign.space24),
            GroupedSection(
              header: context.s('Sort by'),
              children: <Widget>[
                for (final GSortMode mode in GSortMode.values)
                  ListRow(
                    title: context.s(mode.label),
                    trailing: mode == sort
                        ? Icon(
                            GIcons.check,
                            size: 20,
                            color: GDesignTheme.of(sheet).accentText,
                          )
                        : const SizedBox(width: 20),
                    onTap: () {
                      ref.read(gSortProvider.notifier).select(mode);
                      Navigator.of(sheet).pop();
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// "Save" when everything selected is status media, "Restore" otherwise.
  static String _verb(
    BuildContext context,
    List<RecoverableItem> items,
    List<String> chosen,
  ) {
    final Set<String> ids = chosen.toSet();
    final Iterable<RecoverableItem> picked = items.where(
      (RecoverableItem item) => ids.contains(item.itemId),
    );
    final bool statuses =
        picked.isNotEmpty &&
        picked.every((RecoverableItem item) => item.role == kRoleStatus);
    return statuses ? context.s('Save') : context.s('Restore');
  }

  static IconData _kindIcon(String kind) => switch (kind) {
    'image' => GIcons.photos,
    'video' => GIcons.video,
    'audio' => GIcons.audio,
    'document' => GIcons.docs,
    _ => GIcons.folder,
  };

  static List<RecoverableItem> _ordered(
    List<RecoverableItem> items,
    GSortMode sort,
  ) {
    final List<RecoverableItem> out = List<RecoverableItem>.of(items);
    int byDeleted(RecoverableItem a, RecoverableItem b) =>
        (b.dateDeletedMillis ?? 0).compareTo(a.dateDeletedMillis ?? 0);
    switch (sort) {
      case GSortMode.newest:
        out.sort(byDeleted);
      case GSortMode.oldest:
        out.sort((RecoverableItem a, RecoverableItem b) => byDeleted(b, a));
      case GSortMode.largest:
        out.sort(
          (RecoverableItem a, RecoverableItem b) =>
              b.sizeBytes.compareTo(a.sizeBytes),
        );
      case GSortMode.smallest:
        out.sort(
          (RecoverableItem a, RecoverableItem b) =>
              a.sizeBytes.compareTo(b.sizeBytes),
        );
      case GSortMode.name:
        out.sort(
          (RecoverableItem a, RecoverableItem b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case GSortMode.expiring:
        out.sort((RecoverableItem a, RecoverableItem b) {
          final int left = a.expiresInDays ?? 1 << 30;
          final int right = b.expiresInDays ?? 1 << 30;
          return left.compareTo(right);
        });
    }
    return out;
  }

  static List<DateGroup<RecoverableItem>> _grouped(
    List<RecoverableItem> items,
    GSortMode sort,
    GroupBy by,
  ) {
    switch (by) {
      case GroupBy.app:
        return groupByApp<RecoverableItem>(
          items,
          pathOf: (RecoverableItem i) => i.relativePath,
          sizeOf: (RecoverableItem i) => i.sizeBytes,
        );
      case GroupBy.size:
        return groupBySize<RecoverableItem>(
          items,
          sizeOf: (RecoverableItem i) => i.sizeBytes,
        );
      case GroupBy.date:
        break;
    }
    final List<DateGroup<RecoverableItem>> groups =
        groupByDate<RecoverableItem>(
          items,
          dateOf: (RecoverableItem item) => item.dateDeletedMillis,
          sizeOf: (RecoverableItem item) => item.sizeBytes,
          prefix: 'Deleted',
        );
    if (!sort.ranksGroups) return groups;
    return rankGroupsBySize<RecoverableItem>(
      groups,
      smallestFirst: sort == GSortMode.smallest,
    );
  }
}

/// One line on what this list holds, measured from the items themselves.
/// A picture as a list row: its thumbnail, name, and size.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.item,
    required this.image,
    required this.thumbKey,
    required this.hidden,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final RecoverableItem item;
  final ImageProvider image;

  /// Marks the thumbnail so the grid and list morph can find it.
  final GlobalKey thumbKey;

  /// True while a flying copy is landing on this thumbnail.
  final bool hidden;

  /// Null outside selection.
  final bool? selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const double size = 56;
  static const double radius = 10;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int? millis = item.durationMillis;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: item.name,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GDesign.gutter,
          vertical: 4,
        ),
        child: Row(
          children: <Widget>[
            Opacity(
              opacity: hidden ? 0 : 1,
              child: ClipRRect(
                key: thumbKey,
                borderRadius: BorderRadius.circular(radius),
                child: SizedBox.square(
                  dimension: size,
                  child: SizedPhoto(image: image),
                ),
              ),
            ),
            const SizedBox(width: GDesign.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: g.body(),
                  ),
                  Text(
                    millis == null
                        ? GFormat.bytes(item.sizeBytes)
                        : '${GFormat.bytes(item.sizeBytes)}, '
                              '${GFormat.duration(Duration(milliseconds: millis))}',
                    style: g.figures(g.footnote()),
                  ),
                ],
              ),
            ),
            if (selected != null) SelectMark(selected: selected!),
          ],
        ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.items});

  final List<RecoverableItem> items;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    int bytes = 0;
    int previews = 0;
    for (final RecoverableItem item in items) {
      if (item.fidelity == 'preview') {
        previews++;
      } else {
        bytes += item.sizeBytes;
      }
    }
    final String count = items.length == 1
        ? context.s('1 item')
        : context.s1('{} items', GFormat.count(items.length));
    final String line = bytes > 0 ? '$count, ${GFormat.bytes(bytes)}' : count;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space4,
        GDesign.gutter,
        0,
      ),
      child: Text(
        previews > 0
            ? '$line. ${context.s1('{} are previews only.', GFormat.count(previews))}'
            : line,
        style: g.figures(g.footnote()),
      ),
    );
  }
}

/// The scan that is filling this list, while it runs.
class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final BackgroundScanState? deep = ref.watch(backgroundScanProvider).value;
    final ScanProgress? quick = ref.watch(scanProgressProvider).value;
    final bool scanning = ref.watch(scanControllerProvider).isLoading;

    final (int found, int scanned, int total)? at = (deep?.running ?? false)
        ? (deep!.found, deep.scanned, deep.total)
        : (scanning && quick != null && !quick.done)
        ? (quick.found, quick.scanned, quick.total)
        : null;
    if (at == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        GDesign.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: at.$3 > 0 ? (at.$2 / at.$3).clamp(0.0, 1.0) : null,
              minHeight: 4,
              color: g.accent,
              backgroundColor: g.fill,
            ),
          ),
          const SizedBox(height: GDesign.space8),
          Text(
            context.s1('{} found so far', GFormat.count(at.$1)),
            style: g.figures(g.footnote()),
          ),
        ],
      ),
    );
  }
}

/// The user's newest photos, for the empty scene. Same scope as the home
/// page's, so the list is fetched once and shared.
const StorageScope _recentPhotos = StorageScope(
  title: 'Recent photos',
  kind: 'image',
  sort: GSortMode.newest,
);

/// Nothing to list: a small moving scene of what would be here, one line,
/// the full scan, and the reason behind a quiet link.
class _Empty extends ConsumerWidget {
  const _Empty({required this.loading, required this.query});

  final bool loading;
  final RecoveryQuery query;

  /// The scene that matches what this page holds.
  EmptyKind get _kind {
    if (query.roles.contains(kRoleStatus)) return EmptyKind.statuses;
    if (query.roles.contains(kRoleCache)) return EmptyKind.previews;
    return switch (query.kind) {
      'video' => EmptyKind.video,
      'audio' => EmptyKind.audio,
      'document' => EmptyKind.docs,
      _ => EmptyKind.photos,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final BackgroundScanState? deep = ref.watch(backgroundScanProvider).value;
    final bool busy =
        loading ||
        (deep?.running ?? false) ||
        ref.watch(scanControllerProvider).isLoading;
    final bool timedOut = deep != null && !deep.running && deep.timedOut;

    final StorageBridge storage = ref.watch(storageBridgeProvider);
    final List<StorageFile> recent =
        ref.watch(storageFilesProvider(_recentPhotos)).value?.files ??
        const <StorageFile>[];
    final List<ImageProvider> photos = <ImageProvider>[
      for (final StorageFile f in recent.take(4))
        FileThumbnail(fileId: f.fileId, bridge: storage, maxPixels: 360),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        GDesign.space32,
      ),
      child: Reveal(
        child: Column(
          children: <Widget>[
            EmptyScene(kind: _kind, photos: photos),
            const SizedBox(height: GDesign.space24),
            Text(
              busy ? context.s('Looking') : context.s('Nothing deleted here'),
              style: g.headline(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GDesign.space4),
            Text(
              busy
                  ? context.s('Working through this source')
                  : timedOut
                  ? context.s('The scan ran out of time')
                  : context.s('A real answer, not a failed scan'),
              style: g.footnote(),
              textAlign: TextAlign.center,
            ),
            // Fades in and out with the scan instead of jumping.
            AnimatedSize(
              duration: GDesign.motion(context, GDesign.normal),
              curve: GDesign.enter,
              child: busy
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      children: <Widget>[
                        const SizedBox(height: GDesign.space24),
                        PrimaryButton(
                          pill: true,
                          label: timedOut
                              ? context.s('Scan again')
                              : context.s('Scan my phone'),
                          icon: GIcons.scan,
                          onTap: () async {
                            await ref
                                .read(recoveryBridgeProvider)
                                .startBackgroundScan();
                            ref.invalidate(backgroundScanProvider);
                          },
                        ),
                        const SizedBox(height: GDesign.space8),
                        Pressable(
                          onTap: () => _explain(context),
                          semanticLabel: context.s('Why this is empty'),
                          child: SizedBox(
                            height: GDesign.touch,
                            child: Center(
                              child: Text(
                                context.s('Why this is empty'),
                                style: g.footnote(color: g.accentText),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space8,
            GDesign.gutter,
            GDesign.space24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.s('Why this is empty'), style: g.title2()),
              const SizedBox(height: GDesign.space12),
              Text(
                context.s('Nothing of this kind was deleted recently.'),
                style: g.body(),
              ),
              const SizedBox(height: GDesign.space8),
              Text(
                context.s(
                  'Or it was deleted outside a bin, by a cleaner app or a file '
                  'manager, and nothing kept a copy.',
                ),
                style: g.body(color: g.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}
