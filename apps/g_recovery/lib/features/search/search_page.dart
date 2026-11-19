import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/recovery_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/g_thumbnail.dart';
import '../recovery/state/recovery_actions.dart';
import '../recovery/state/recovery_providers.dart';
import '../viewer/media_viewer.dart';
import 'state/search_providers.dart';

/// Search across what can come back and what is still on the phone.
///
/// The field leads, the way the system search does, with Cancel beside it.
/// Photos come back as the same edge-to-edge grid as everywhere else and
/// open with the same zoom; other files are rows. A long press selects, and
/// the tab bar becomes the restore toolbar.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const SearchPage(),
  );

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  bool _selecting = false;
  late final GShellNav _nav;

  /// Snapshot targets for the flight and the dust, one per result.
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _nav = ref.read(gShellNavHiddenProvider.notifier);
    _controller.text = ref.read(searchQueryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      ref.read(selectionProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    if (_selecting) _nav.show();
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String itemId) =>
      _keys.putIfAbsent(itemId, () => GlobalKey(debugLabel: itemId));

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      ref.read(searchQueryProvider.notifier).set(value);
      ref.read(recentSearchesProvider.notifier).remember(value);
    });
  }

  void _useRecent(String term) {
    _controller.text = term;
    ref.read(searchQueryProvider.notifier).set(term);
  }

  void _setSelecting(bool on) {
    if (on == _selecting) return;
    if (on) {
      _focus.unfocus();
      _nav.hide();
    } else {
      _nav.show();
      ref.read(selectionProvider.notifier).clear();
    }
    setState(() => _selecting = on);
  }

  void _tap(List<RecoverableItem> list, RecoverableItem item, bool restorable) {
    if (_selecting) {
      if (!restorable) return;
      Haptics.select();
      ref.read(selectionProvider.notifier).toggle(item.itemId);
      return;
    }
    _open(list, item, restorable);
  }

  void _press(RecoverableItem item) {
    if (!_selecting) _setSelecting(true);
    ref.read(selectionProvider.notifier).toggle(item.itemId);
  }

  void _open(
    List<RecoverableItem> list,
    RecoverableItem item,
    bool restorable,
  ) {
    _focus.unfocus();
    Navigator.of(context).push(
      MediaViewer.route(
        items: list,
        index: list.indexOf(item),
        heroPrefix: 'search',
        viewOnly: !restorable,
      ),
    );
  }

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
    _finish(result);
  }

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
    _finish(result);
  }

  void _finish(RecoveryActionResult result) {
    reportRecoveryProblem(context, result);
    _setSelecting(false);
    refreshRecovery(ref);
    ref.invalidate(searchResultsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final String query = ref.watch(searchQueryProvider);
    final AsyncValue<List<RecoverableItem>> async = ref.watch(
      searchResultsProvider,
    );
    final SearchGroups groups = ref.watch(searchGroupsProvider);
    final List<String> recent = ref.watch(recentSearchesProvider);
    final Set<String> selected = ref.watch(selectionProvider);
    final List<String> chosen = <String>[
      for (final RecoverableItem item in groups.deleted)
        if (selected.contains(item.itemId)) item.itemId,
    ];
    final bool idle = query.trim().length < 2;
    final EdgeInsets inset = MediaQuery.paddingOf(context);

    final List<Widget> slivers = <Widget>[
      if (idle) ...<Widget>[
        SliverToBoxAdapter(child: _Suggestions(onPick: _useRecent)),
        if (recent.isNotEmpty) ...<Widget>[
          SliverToBoxAdapter(
            child: SectionHeader(
              context.s('Recent'),
              actionLabel: context.s('Clear'),
              onAction: () => ref.read(recentSearchesProvider.notifier).clear(),
            ),
          ),
          SliverToBoxAdapter(
            child: GroupedSection(
              children: <Widget>[
                for (final String term in recent)
                  ListRow(
                    icon: GIcons.clock,
                    title: term,
                    onTap: () => _useRecent(term),
                  ),
              ],
            ),
          ),
        ],
      ] else if (async.isLoading && groups.isEmpty)
        SliverToBoxAdapter(child: _Note(title: context.s('Searching')))
      else if (groups.isEmpty)
        SliverToBoxAdapter(child: _Note(title: context.s('Nothing matched')))
      else ...<Widget>[
        if (groups.deleted.isNotEmpty)
          ..._section(
            context,
            title: context.s('Deleted, can come back'),
            items: groups.deleted,
            selected: selected,
            restorable: true,
          ),
        if (groups.live.isNotEmpty)
          ..._section(
            context,
            title: context.s('Still on the device'),
            items: groups.live,
            selected: selected,
            restorable: false,
          ),
      ],
    ];

    return Material(
      color: g.grouped,
      child: Stack(
        children: <Widget>[
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: SizedBox(height: inset.top + _SearchBar.height),
              ),
              ...slivers,
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      inset.bottom +
                      GDesign.space24 +
                      (_selecting ? ActionBar.extent(context) : 0),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _SearchBar(
              controller: _controller,
              focus: _focus,
              hasText: query.isNotEmpty,
              selecting: _selecting,
              count: chosen.length,
              onChanged: _onChanged,
              onClear: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).clear();
              },
              onCancel: () => _selecting
                  ? _setSelecting(false)
                  : Navigator.of(context).maybePop(),
            ),
          ),
          if (_selecting)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ActionBar(
                center: PrimaryButton(
                  pill: true,
                  label: chosen.isEmpty
                      ? context.s('Restore')
                      : '${context.s('Restore')} ${GFormat.count(chosen.length)}',
                  onTap: chosen.isEmpty ? null : () => _restore(chosen),
                ),
                trailing: BarIconButton(
                  icon: GIcons.trash,
                  semanticLabel: context.s('Delete for good'),
                  onTap: chosen.isEmpty ? null : () => _delete(chosen),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A heading, then photos as a grid and every other file as rows.
  List<Widget> _section(
    BuildContext context, {
    required String title,
    required List<RecoverableItem> items,
    required Set<String> selected,
    required bool restorable,
  }) {
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    final List<RecoverableItem> photos = <RecoverableItem>[
      for (final RecoverableItem i in items)
        if (i.kind == 'image' || i.kind == 'video') i,
    ];
    final List<RecoverableItem> files = <RecoverableItem>[
      for (final RecoverableItem i in items)
        if (i.kind != 'image' && i.kind != 'video') i,
    ];

    return <Widget>[
      SliverToBoxAdapter(
        child: SectionHeader(
          title,
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space24,
            GDesign.gutter,
            GDesign.space8,
          ),
        ),
      ),
      if (photos.isNotEmpty)
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
            final RecoverableItem item = photos[i];
            return RepaintBoundary(
              key: _keyFor(item.itemId),
              child: PhotoGridTile(
                image: ItemThumbnail(
                  itemId: item.itemId,
                  bridge: bridge,
                  maxPixels: 360,
                ),
                heroTag: 'search-${item.itemId}',
                selected: _selecting && restorable
                    ? selected.contains(item.itemId)
                    : null,
                onTap: () => _tap(photos, item, restorable),
                onLongPress: restorable ? () => _press(item) : null,
              ),
            );
          }, childCount: photos.length),
        ),
      if (files.isNotEmpty) ...<Widget>[
        if (photos.isNotEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space16)),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: <Widget>[
              for (final RecoverableItem item in files)
                RepaintBoundary(
                  key: _keyFor(item.itemId),
                  child: ListRow(
                    icon: switch (item.kind) {
                      'audio' => GIcons.audio,
                      'document' => GIcons.docs,
                      _ => GIcons.folder,
                    },
                    title: item.name,
                    subtitle: GFormat.bytes(item.sizeBytes),
                    trailing: _selecting && restorable
                        ? SelectMark(selected: selected.contains(item.itemId))
                        : null,
                    onTap: () => _tap(files, item, restorable),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}

/// The search field on a grey track, and Cancel. While selecting, the field
/// gives way to the count.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focus,
    required this.hasText,
    required this.selecting,
    required this.count,
    required this.onChanged,
    required this.onClear,
    required this.onCancel,
  });

  static const double height = 60;

  final TextEditingController controller;
  final FocusNode focus;
  final bool hasText;
  final bool selecting;
  final int count;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return ColoredBox(
      color: g.grouped,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          GDesign.gutter,
          MediaQuery.paddingOf(context).top + GDesign.space8,
          GDesign.space8,
          GDesign.space8,
        ),
        child: SizedBox(
          height: 44,
          child: Row(
            children: <Widget>[
              Expanded(
                child: selecting
                    ? Text(
                        count == 0
                            ? context.s('Select items')
                            : context.s1('{} selected', GFormat.count(count)),
                        style: g.headline(),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: g.isDark ? g.card : const Color(0x0F000000),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SizedBox(
                          height: 40,
                          child: Row(
                            children: <Widget>[
                              const SizedBox(width: 10),
                              Icon(GIcons.search, size: 18, color: g.muted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  focusNode: focus,
                                  onChanged: onChanged,
                                  textInputAction: TextInputAction.search,
                                  cursorColor: g.accent,
                                  style: g.body(),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: context.s(
                                      'Name, app, or file type',
                                    ),
                                    hintStyle: g.body(color: g.muted),
                                  ),
                                ),
                              ),
                              if (hasText)
                                BarIconButton(
                                  icon: GIcons.close,
                                  semanticLabel: context.s('Clear'),
                                  onTap: onClear,
                                  color: g.muted,
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
              NavAction.text(
                label: selecting ? context.s('Done') : context.s('Cancel'),
                onTap: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet note in place of results.
class _Note extends StatelessWidget {
  const _Note({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space32,
        GDesign.gutter,
        0,
      ),
      child: Text(title, style: g.headline()),
    );
  }
}

/// Ready made searches shown before anything is typed. Each fills the field
/// with a fragment that real file names carry, and the chips drift gently
/// so the empty page does not sit still.
class _Suggestions extends StatefulWidget {
  const _Suggestions({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  State<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends State<_Suggestions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    // Label, icon, and the fragment the file names actually contain.
    final List<(String, IconData, String)> picks = <(String, IconData, String)>[
      (context.s('Screenshots'), GIcons.monitor, 'Screenshot'),
      ('WhatsApp', GIcons.messages, '-WA'),
      (context.s('Camera photos'), GIcons.camera, 'IMG_'),
      (context.s('Videos'), GIcons.video, 'VID'),
      (context.s('Voice notes'), GIcons.audio, 'PTT'),
      ('PDF', GIcons.docs, '.pdf'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space16,
        GDesign.gutter,
        GDesign.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.s('Try'), style: g.footnote(weight: FontWeight.w600)),
          const SizedBox(height: GDesign.space12),
          AnimatedBuilder(
            animation: _drift,
            builder: (BuildContext context, Widget? _) => Wrap(
              spacing: GDesign.space8,
              runSpacing: GDesign.space12,
              children: <Widget>[
                for (int i = 0; i < picks.length; i++)
                  Reveal(
                    index: i,
                    child: Transform.translate(
                      // Each chip bobs on its own phase.
                      offset: Offset(
                        0,
                        2.5 *
                            math.sin(
                              (_drift.value + i / picks.length) * math.pi * 2,
                            ),
                      ),
                      child: Pressable(
                        onTap: () {
                          Haptics.select();
                          widget.onPick(picks[i].$3);
                        },
                        semanticLabel: picks[i].$1,
                        scale: 0.94,
                        child: Container(
                          height: GDesign.pillHeight - 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: GDesign.space16,
                          ),
                          decoration: BoxDecoration(
                            color: g.card,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(picks[i].$2, size: 18, color: g.accentText),
                              const SizedBox(width: GDesign.space8),
                              Text(picks[i].$1, style: g.body()),
                            ],
                          ),
                        ),
                      ),
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
