import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/theme/tokens.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/recovery_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../core/messenger/g_message.dart';
import '../../core/messenger/g_messenger.dart';
import '../../ui/g_badge.dart';
import '../../ui/g_thumbnail.dart';
import '../recovery/state/recovery_providers.dart';
import '../viewer/media_viewer.dart';
import 'state/search_providers.dart';

/// Unified search across deleted and present files.
///
/// One field, one list, two sections. The user who cannot remember whether
/// they deleted the file does not have to pick a tab before they can look for
/// it, which is the actual state most people are in when they open a recovery
/// app.
///
/// Immersive layout: the field floats where every other screen has its title,
/// results run edge to edge, and a selection raises one floating bar with the
/// two actions.
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

  /// Height of the floating selection bar, padding included.
  static const double _barHeight = 64;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      // Cleared on the way IN, not on the way out.
      //
      // Selection is app wide, so a leftover from a category page would arm a
      // restore bar here over items that are not in this list. Clearing on
      // dispose looked like the same fix and was not: ref is unusable once the
      // element is deactivated. Every page that uses the selection clearing it
      // as it opens makes a stale one impossible to observe.
      ref.read(selectionProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 220 ms: one query per word at a normal typing speed rather than one per
  /// letter. Without it every keystroke starts a MediaStore query on the
  /// platform thread and the field stutters on a budget device.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      ref.read(searchQueryProvider.notifier).set(value);
      ref.read(recentSearchesProvider.notifier).remember(value);
    });
  }

  void _clear() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).clear();
  }

  void _useRecent(String term) {
    _controller.text = term;
    ref.read(searchQueryProvider.notifier).set(term);
  }

  /// Opens the viewer on a list, positioned at the row that was tapped.
  ///
  /// Only things with a preview go into the deck. A document has nothing to
  /// look at, so tapping one does nothing rather than opening a page of grey.
  void _open(List<RecoverableItem> list, int index) {
    final List<RecoverableItem> viewable = list.where(_viewable).toList();
    final int start = viewable.indexOf(list[index]);
    if (start < 0) return;
    // rootNavigator, because the viewer is the one screen that must cover the
    // floating nav. Everything else belongs inside its tab's stack.
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MediaViewer.route(items: viewable, index: start));
  }

  static bool _viewable(RecoverableItem item) =>
      item.kind == 'image' || item.kind == 'video';

  /// Save, not Restore, when everything picked is status media. The file was
  /// never deleted, so restoring it is a word that describes nothing.
  static String _verb(List<RecoverableItem> items, List<String> chosen) {
    final Set<String> ids = chosen.toSet();
    final Iterable<RecoverableItem> picked = items.where(
      (RecoverableItem item) => ids.contains(item.itemId),
    );
    if (picked.isEmpty) return 'Restore';
    return picked.every((RecoverableItem item) => item.role == 'status')
        ? 'Save'
        : 'Restore';
  }

  /// Purging empties the trash for good, so it asks first, exactly as the
  /// category list does. It used to run on one tap from here.
  Future<void> _confirmDelete(List<String> itemIds) async {
    final bool go = await showConfirmSheet(
      context: context,
      title: 'Delete ${GFormat.count(itemIds.length)} permanently',
      message: context.s(
        'These leave the trash for good. This app cannot bring them back '
        'afterwards, and neither can anything else.',
      ),
      confirmLabel: context.s('Delete'),
      cancelLabel: context.s('Keep'),
    );
    if (!go || !mounted) return;
    await _act(itemIds, purge: true);
  }

  Future<void> _act(List<String> itemIds, {required bool purge}) async {
    final List<RestoreOutcome> outcomes = purge
        ? await ref.read(recoveryBridgeProvider).purge(itemIds)
        : await ref.read(recoveryBridgeProvider).restore(itemIds);
    if (!mounted) return;
    final int ok = outcomes
        .where((RestoreOutcome outcome) => outcome.status == 'restored')
        .length;
    RestoreOutcome? problem;
    for (final RestoreOutcome outcome in outcomes) {
      if (outcome.status != 'restored') {
        problem = outcome;
        break;
      }
    }
    // The first failure is reported verbatim. The statuses differ because the
    // user's next action differs, and collapsing them into "some items failed"
    // throws that away.
    GMessenger.show(
      context,
      problem == null
          ? GMessage.success(purge ? '$ok deleted' : '$ok restored')
          : GMessage.warning('$ok done. ${problem.detail}'),
    );
    ref.read(selectionProvider.notifier).clear();
    ref.invalidate(searchResultsProvider);
    ref.invalidate(prescanProvider);
  }

  @override
  Widget build(BuildContext context) {
    final GTokens t = context.g;
    final String query = ref.watch(searchQueryProvider);
    final AsyncValue<List<RecoverableItem>> async = ref.watch(
      searchResultsProvider,
    );
    final SearchGroups groups = ref.watch(searchGroupsProvider);
    final List<String> recent = ref.watch(recentSearchesProvider);
    final Set<String> selected = ref.watch(selectionProvider);
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);

    // Only deleted results can be acted on. Native resolves a restore through
    // the scan index, and a live file is deliberately never registered there.
    final List<String> chosen = groups.deleted
        .map((RecoverableItem item) => item.itemId)
        .where(selected.contains)
        .toList();

    final double bottom = MediaQuery.paddingOf(context).bottom;
    final bool idle = query.trim().length < 2;

    return Scaffold(
      backgroundColor: t.ink,
      body: Stack(
        children: <Widget>[
          ListView(
            padding: EdgeInsets.only(
              top: FloatHeader.extent(context) + GDesign.space8,
              bottom:
                  bottom +
                  GDesign.space16 +
                  (chosen.isEmpty ? 0 : _barHeight + GDesign.space12),
            ),
            children: <Widget>[
              if (idle) ...<Widget>[
                if (recent.isNotEmpty) ...<Widget>[
                  SectionLabel(context.s('Recent')),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GDesign.gutter,
                    ),
                    child: Wrap(
                      spacing: GDesign.space8,
                      children: <Widget>[
                        for (final String term in recent)
                          FloatChip(
                            label: term,
                            solid: true,
                            onTap: () => _useRecent(term),
                          ),
                      ],
                    ),
                  ),
                ],
              ] else if (async.isLoading && groups.isEmpty)
                _Note(text: context.s('Searching'))
              else if (groups.isEmpty)
                _Note(
                  title: context.s('Nothing matched'),
                  // The honest empty state. Saying why beats an illustration
                  // of a magnifying glass.
                  text: context.s(
                    'Only files still on the device and files sitting '
                    'in a trash folder can be searched. Anything erased '
                    'outside a trash folder leaves no name behind.',
                  ),
                )
              else ...<Widget>[
                if (groups.deleted.isNotEmpty) ...<Widget>[
                  SectionLabel(
                    context.s('Deleted, restorable'),
                    trailing: _Count(groups.deleted.length),
                  ),
                  for (int i = 0; i < groups.deleted.length; i++)
                    _ResultRow(
                      item: groups.deleted[i],
                      bridge: bridge,
                      selected: selected.contains(groups.deleted[i].itemId),
                      // Tap views, long press selects, and once anything is
                      // selected tap selects too. Same grammar as the category
                      // list, so nothing has to be learned twice.
                      onTap: () => selected.isEmpty
                          ? _open(groups.deleted, i)
                          : ref
                                .read(selectionProvider.notifier)
                                .toggle(groups.deleted[i].itemId),
                      onLongPress: () => ref
                          .read(selectionProvider.notifier)
                          .toggle(groups.deleted[i].itemId),
                    ),
                ],
                if (groups.live.isNotEmpty) ...<Widget>[
                  SectionLabel(
                    context.s('Still on the device'),
                    trailing: GBadge(label: context.s('Not deleted')),
                  ),
                  // No selection on live files. The row opens and that is all
                  // it can honestly offer.
                  for (int i = 0; i < groups.live.length; i++)
                    _ResultRow(
                      item: groups.live[i],
                      bridge: bridge,
                      onTap: () => _open(groups.live, i),
                    ),
                ],
              ],
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _SearchHeader(
              controller: _controller,
              focus: _focus,
              hasText: query.isNotEmpty,
              onChanged: _onChanged,
              onClear: _clear,
            ),
          ),
          if (chosen.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: bottom + GDesign.space12,
              child: _SelectionBar(
                deleteLabel: 'Delete ${chosen.length}',
                actLabel: '${_verb(groups.deleted, chosen)} ${chosen.length}',
                onDelete: () => _confirmDelete(chosen),
                onAct: () => _act(chosen, purge: false),
              ),
            ),
        ],
      ),
    );
  }
}

/// Back and the search field, floating where other screens carry their title.
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focus,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final TextStyle field = g.sans.copyWith(
      fontSize: GDesign.body,
      color: g.text,
    );

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + GDesign.headerGap,
        left: 12,
        right: 12,
      ),
      child: Row(
        children: <Widget>[
          FloatIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: context.s('Back'),
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: GDesign.space8),
          Expanded(
            child: GlassSurface(
              borderRadius: BorderRadius.circular(GDesign.headerHeight / 2),
              child: SizedBox(
                height: GDesign.headerHeight,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: GDesign.space16),
                    Icon(Icons.search_rounded, size: 20, color: g.muted),
                    const SizedBox(width: GDesign.space8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focus,
                        onChanged: onChanged,
                        textInputAction: TextInputAction.search,
                        cursorColor: g.accent,
                        style: field,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: context.s('Name, app, or file type'),
                          hintStyle: field.copyWith(color: g.muted),
                        ),
                      ),
                    ),
                    if (hasText)
                      IconButton(
                        onPressed: onClear,
                        tooltip: context.s('Clear'),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: g.muted,
                        ),
                      )
                    else
                      const SizedBox(width: GDesign.space16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One result, edge to edge: thumbnail, name, facts, and what it can become.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.bridge,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  final RecoverableItem item;
  final RecoveryBridge bridge;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  bool get _isLive => item.sourceId == 'live_files';

  @override
  Widget build(BuildContext context) {
    return EdgeRow(
      leading: SizedBox.square(
        dimension: 40,
        child: GThumbnail(
          itemId: item.itemId,
          bridge: bridge,
          kind: item.kind,
          maxPixels: 128,
          radius: 8,
        ),
      ),
      title: item.name,
      subtitle: _facts(),
      trailing: _stamp(),
      selected: selected,
      chevron: false,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  String _facts() {
    final List<String> parts = <String>[
      if (item.origin != null) item.origin!,
      if (item.relativePath != null)
        item.relativePath!.replaceAll(RegExp(r'/$'), ''),
      GFormat.bytes(item.sizeBytes),
      if (item.expiresInDays != null)
        item.expiresInDays == 0
            ? 'expires today'
            : '${item.expiresInDays} days left',
    ];
    return parts.join('  ·  ');
  }

  /// Status first, because it changes what the action means, not just what
  /// quality to expect. A status was never deleted; it is on a 24 hour timer.
  Widget _stamp() {
    if (_isLive) return GBadge(label: 'On device');
    if (item.role == 'media') return GBadge.live('In the app');
    if (item.role == 'status') return GBadge.partial('Status');
    if (item.fidelity == 'preview') return GBadge.partial('Preview');
    return GBadge.full('Restore');
  }
}

/// The count at the end of a section label.
class _Count extends StatelessWidget {
  const _Count(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Text(
      GFormat.count(value),
      style: g.mono.copyWith(fontSize: 12, color: g.muted),
    );
  }
}

/// Plain text for searching and empty states. No card, no illustration.
class _Note extends StatelessWidget {
  const _Note({required this.text, this.title});

  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space16,
        GDesign.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: g.sans.copyWith(
                fontSize: GDesign.title,
                height: 28 / 22,
                fontWeight: FontWeight.w700,
                color: g.text,
              ),
            ),
            const SizedBox(height: GDesign.space8),
          ],
          Text(
            text,
            style: g.sans.copyWith(
              fontSize: GDesign.body,
              height: 22 / 15,
              color: title == null ? g.muted : g.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating glass bar with the two things a selection can become.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.deleteLabel,
    required this.actLabel,
    required this.onDelete,
    required this.onAct,
  });

  final String deleteLabel;
  final String actLabel;
  final VoidCallback onDelete;
  final VoidCallback onAct;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return GlassSurface(
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.all(GDesign.space8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _Pill(
                label: deleteLabel,
                background: g.danger.withValues(alpha: 0.16),
                foreground: g.danger,
                onTap: onDelete,
              ),
            ),
            const SizedBox(width: GDesign.space8),
            Expanded(
              child: _Pill(
                label: actLabel,
                background: g.accent,
                foreground: g.onAccent,
                onTap: onAct,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return SizedBox(
      height: GDesign.touch,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(GDesign.touch / 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: g.sans.copyWith(
                fontSize: GDesign.body,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
