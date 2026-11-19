import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/storage_api.g.dart';
import '../../bridge/storage_bridge.dart';
import '../../core/date_groups.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../core/messenger/g_message.dart';
import '../../core/messenger/g_messenger.dart';
import '../../ui/file_thumbnail.dart';
import '../../ui/g_sort.dart';
import '../../ui/media/media_stage.dart';
import '../../ui/media/playable_media.dart';
import 'file_viewer.dart';
import 'state/cleanup_actions.dart';
import 'state/storage_files.dart';
import 'state/storage_providers.dart';

/// Files still on the phone for one scope (biggest files, one kind, one
/// folder, untouched), as a ranked list.
///
/// Sorted by size the list is one ranked run, because grouping by date
/// would hide the order the page exists to show. Sorted by date it groups
/// by day. Hold a file to start choosing; the bar then trashes the chosen
/// files, or deletes them for good after a confirmation.
class StorageFilesPage extends ConsumerStatefulWidget {
  const StorageFilesPage({required this.scope, super.key, this.backLabel});

  final StorageScope scope;

  /// The previous screen's title, beside the back chevron.
  final String? backLabel;

  static Route<void> route(StorageScope scope, {String? backLabel}) =>
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            StorageFilesPage(scope: scope, backLabel: backLabel),
      );

  @override
  ConsumerState<StorageFilesPage> createState() => _StorageFilesPageState();
}

class _StorageFilesPageState extends ConsumerState<StorageFilesPage> {
  final Set<String> _picked = <String>{};
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  late final GShellNav _nav;
  bool _selecting = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nav = ref.read(gShellNavHiddenProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(gSortProvider.notifier).select(widget.scope.sort);
    });
  }

  @override
  void dispose() {
    if (_selecting) _nav.show();
    super.dispose();
  }

  GlobalKey _keyFor(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  void _setSelecting(bool on) {
    if (on == _selecting) return;
    on ? _nav.hide() : _nav.show();
    setState(() {
      _selecting = on;
      if (!on) _picked.clear();
    });
  }

  void _toggle(String id) {
    Haptics.select();
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final GSortMode sort = ref.watch(gSortProvider);
    final StorageScope scope = widget.scope.sorted(sort);
    final AsyncValue<StorageQueryResult?> query = ref.watch(
      storageFilesProvider(scope),
    );
    final StorageQueryResult? result = query.value;
    final List<StorageFile> files = result?.files ?? const <StorageFile>[];
    final bool ranked = sort.ranksGroups || sort == GSortMode.name;
    final int chosenBytes = files
        .where((StorageFile f) => _picked.contains(f.fileId))
        .fold<int>(0, (int s, StorageFile f) => s + f.sizeBytes);

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _setSelecting(false);
      },
      child: LargeTitlePage(
        title: widget.scope.title,
        backLabel: widget.backLabel,
        onBack: () => Navigator.of(context).maybePop(),
        grouped: true,
        actions: <Widget>[
          if (_selecting)
            NavAction.text(
              label: context.s('Done'),
              onTap: () => _setSelecting(false),
            )
          else
            NavAction.icon(
              icon: GIcons.more,
              semanticLabel: context.s('Options'),
              onTap: () => _options(context),
            ),
        ],
        onRefresh: () async => ref.invalidate(storageFilesProvider(scope)),
        bottom: _selecting
            ? ActionBar(
                leading: BarIconButton(
                  icon: GIcons.checkCircle,
                  semanticLabel: context.s('Select all'),
                  onTap: () => setState(() {
                    if (_picked.length == files.length) {
                      _picked.clear();
                    } else {
                      _picked.addAll(files.map((StorageFile f) => f.fileId));
                    }
                  }),
                ),
                center: PrimaryButton(
                  label: _picked.isEmpty
                      ? context.s('Choose files')
                      : '${context.s1('Trash {}', GFormat.count(_picked.length))}, '
                            '${context.s1('free {}', GFormat.bytes(chosenBytes))}',
                  busy: _busy,
                  onTap: _picked.isEmpty || _busy
                      ? null
                      : () => _remove(permanent: false),
                ),
                trailing: BarIconButton(
                  icon: GIcons.trash,
                  semanticLabel: context.s('Delete for good'),
                  onTap: _picked.isEmpty || _busy
                      ? () {}
                      : () => _remove(permanent: true),
                ),
              )
            : null,
        bottomExtent: _selecting ? ActionBar.extent(context) : 0,
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                GDesign.gutter,
                0,
                GDesign.gutter,
                GDesign.space16,
              ),
              child: Text(
                result == null
                    ? context.s('Counting')
                    : <String>[
                        context.s1(
                          '{} files',
                          GFormat.count(result.matchCount),
                        ),
                        GFormat.bytes(result.matchBytes),
                        context.s(sort.label),
                        if (result.matchCount > files.length)
                          context.s1('showing {}', GFormat.count(files.length)),
                      ].join(', '),
                style: g.figures(g.footnote()),
              ),
            ),
          ),
          if (result != null && files.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(context.s('Nothing here'), style: g.footnote()),
              ),
            )
          else if (ranked)
            _section(files, files)
          else
            for (final DateGroup<StorageFile> group in groupByDate<StorageFile>(
              files,
              dateOf: (StorageFile f) => f.dateModifiedMillis,
              sizeOf: (StorageFile f) => f.sizeBytes,
            )) ...<Widget>[
              SliverToBoxAdapter(
                child: SectionHeader(
                  '${group.label}, ${GFormat.bytes(group.bytes)}',
                ),
              ),
              _section(group.items, files),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space32)),
        ],
      ),
    );
  }

  /// One white rounded section of rows, built lazily so a long list only
  /// asks for the thumbnails on screen.
  Widget _section(List<StorageFile> rows, List<StorageFile> all) {
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      sliver: SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (BuildContext context, int i) {
          final StorageFile file = rows[i];
          return _FileRow(
            file: file,
            bridge: bridge,
            first: i == 0,
            last: i == rows.length - 1,
            boundary: _keyFor(file.fileId),
            selected: _selecting ? _picked.contains(file.fileId) : null,
            onTap: _selecting
                ? () => _toggle(file.fileId)
                : () => _open(all, file),
            onLongPress: () {
              _setSelecting(true);
              _toggle(file.fileId);
            },
          );
        },
      ),
    );
  }

  void _open(List<StorageFile> files, StorageFile file) {
    final int index = files.indexOf(file);
    if (index < 0) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(FileViewer.route(files: files, index: index));
  }

  Future<void> _remove({required bool permanent}) async {
    final List<String> ids = _picked.toList();
    final List<StorageFile> files =
        ref
            .read(
              storageFilesProvider(
                widget.scope.sorted(ref.read(gSortProvider)),
              ),
            )
            .value
            ?.files ??
        const <StorageFile>[];
    final int freed = files
        .where((StorageFile f) => _picked.contains(f.fileId))
        .fold<int>(0, (int s, StorageFile f) => s + f.sizeBytes);

    if (permanent) {
      final bool go = await showConfirmSheet(
        context: context,
        title: context.s1('Delete {} for good', GFormat.count(ids.length)),
        message: context.s(
          'These skip the trash and leave the phone for good. Nothing, '
          'including this app, can bring them back.',
        ),
        confirmLabel: context.s('Delete for good'),
        cancelLabel: context.s('Keep'),
      );
      if (!go || !mounted) return;
    }

    setState(() => _busy = true);
    final TrashResult result = permanent
        ? await _deleteForGood(ids)
        : await trashFiles(ref, ids);
    if (!mounted) return;

    await dustAway(context, ids.where(result.done.contains), _keys);
    if (!mounted) return;

    if (permanent && result.done.isNotEmpty && !result.consent) {
      GMessenger.show(
        context,
        GMessage.success(context.s1('Freed {}', GFormat.bytes(freed))),
      );
    } else {
      reportTrash(context, result, freed);
    }
    setState(() => _busy = false);
    _setSelecting(false);
    ref.invalidate(storageFilesProvider);
    ref.invalidate(storageOverviewProvider);
  }

  Future<TrashResult> _deleteForGood(List<String> ids) async {
    final List<StorageOutcome> outcomes = await ref
        .read(storageBridgeProvider)
        .remove(ids, permanent: true);
    return TrashResult(
      done: <String>{
        for (final StorageOutcome o in outcomes)
          if (o.status == 'trashed' || o.status == 'deleted') o.fileId,
      },
      consent: outcomes.any((StorageOutcome o) => o.status == 'needsConsent'),
    );
  }

  void _options(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        return Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            final GSortMode sort = ref.watch(gSortProvider);
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: GDesign.space24),
              children: <Widget>[
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
                  ],
                ),
                const SizedBox(height: GDesign.space16),
                GroupedSection(
                  header: context.s('Sort by'),
                  children: <Widget>[
                    for (final GSortMode m in GSortMode.values)
                      ListRow(
                        title: m.label,
                        trailing: m == sort
                            ? Icon(GIcons.check, size: 20, color: g.accentText)
                            : const SizedBox(width: 20),
                        onTap: () {
                          Haptics.select();
                          ref.read(gSortProvider.notifier).select(m);
                          Navigator.of(sheet).pop();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: GDesign.space16),
                GroupedSection(
                  footer: context.s(
                    'Everything here is still on your phone. Trash keeps a file '
                    'for 30 days, and Recovery can bring it back. Delete for '
                    'good frees the space at once and cannot be undone.',
                  ),
                  children: <Widget>[
                    ListRow(
                      icon: GIcons.info,
                      title: context.s('These files are not deleted'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// One file: a picture or kind glyph, its name, where and when, and its
/// size, in a row of a rounded section.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.bridge,
    required this.first,
    required this.last,
    required this.boundary,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final StorageFile file;
  final StorageBridge bridge;
  final bool first;
  final bool last;
  final GlobalKey boundary;

  /// Null when not choosing.
  final bool? selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const double _thumb = 56;

  /// A glyph from the kind, falling back to the file's extension, so an
  /// installer, an archive or a database reads as what it is.
  static IconData glyph(StorageFile file) {
    switch (file.kind) {
      case 'image':
        return GIcons.photos;
      case 'video':
        return GIcons.video;
      case 'audio':
        return GIcons.audio;
      case 'document':
        return GIcons.docs;
    }
    final String name = file.name.toLowerCase();
    final int dot = name.lastIndexOf('.');
    final String ext = dot < 0 ? '' : name.substring(dot + 1);
    return switch (ext) {
      'apk' || 'apks' || 'xapk' => GIcons.download,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => GIcons.archive,
      'db' || 'crypt14' || 'crypt15' || 'sqlite' || 'json' => GIcons.docs,
      'mp3' || 'm4a' || 'opus' || 'ogg' || 'wav' => GIcons.audio,
      _ => GIcons.docs,
    };
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final String mime = file.mimeType ?? '';
    final bool visual =
        file.kind == 'image' ||
        file.kind == 'video' ||
        mime.startsWith('image/') ||
        mime.startsWith('video/');
    const Radius r = Radius.circular(GDesign.cardRadius);
    final String? folder = _folder(file.relativePath);
    final int? millis = file.dateModifiedMillis;
    final String when = millis == null
        ? ''
        : MaterialLocalizations.of(
            context,
          ).formatMediumDate(DateTime.fromMillisecondsSinceEpoch(millis));

    return Container(
      decoration: BoxDecoration(
        color: g.card,
        borderRadius: BorderRadius.vertical(
          top: first ? r : Radius.zero,
          bottom: last ? r : Radius.zero,
        ),
      ),
      child: Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        scale: 0.99,
        semanticLabel: '${file.name}, ${GFormat.bytes(file.sizeBytes)}',
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: GDesign.space12),
          child: Row(
            children: <Widget>[
              RepaintBoundary(
                key: boundary,
                child: SizedBox.square(
                  dimension: _thumb,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: file.kind == 'audio' || mime.startsWith('audio/')
                        ? ColoredBox(
                            color: g.isDark ? g.hairline : g.fill,
                            child: PlayRing(
                              media: PlayableMedia.storageFile(file, bridge),
                            ),
                          )
                        : visual
                        ? SizedPhoto(
                            image: FileThumbnail(
                              fileId: file.fileId,
                              bridge: bridge,
                              kind: file.kind,
                              name: file.name,
                              mimeType: file.mimeType,
                              maxPixels: 168,
                            ),
                          )
                        : ColoredBox(
                            color: g.isDark ? g.hairline : g.fill,
                            child: Icon(glyph(file), size: 22, color: g.muted),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: GDesign.space12),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsetsDirectional.only(
                    end: GDesign.space16,
                  ),
                  decoration: BoxDecoration(
                    border: last
                        ? null
                        : Border(
                            bottom: BorderSide(color: g.hairline, width: 0.5),
                          ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: g.body(),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              <String>[
                                ?folder,
                                if (when.isNotEmpty) when,
                              ].join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: g.footnote(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GDesign.space12),
                      if (selected == null)
                        Text(
                          GFormat.bytes(file.sizeBytes),
                          style: g.figures(
                            g.body(color: g.text, weight: FontWeight.w600),
                          ),
                        )
                      else
                        SelectMark(selected: selected!),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The last folder in a relative path, which is the one people recognise.
  static String? _folder(String? relative) {
    if (relative == null || relative.isEmpty) return null;
    final List<String> parts = relative
        .split('/')
        .where((String p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.last;
  }
}
