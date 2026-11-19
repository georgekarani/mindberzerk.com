import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/storage_api.g.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../learn/chapter_page.dart';
import '../../learn/learn_page.dart';
import '../state/storage_providers.dart';
import 'folder_notes.dart';

/// One directory's entries, read fresh each time it is opened.
final browseProvider = FutureProvider.family<List<DirEntry>, String?>(
  (Ref ref, String? path) =>
      ref.watch(storageBridgeProvider).listDirectory(path),
);

/// Whether names starting with a dot are shown, shared by every level.
class HiddenController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final NotifierProvider<HiddenController, bool> showHiddenProvider =
    NotifierProvider<HiddenController, bool>(HiddenController.new);

/// The phone's folders, as a file browser: folders first in rounded
/// sections, each well-known folder with a line on what it is for.
class BrowsePage extends ConsumerWidget {
  const BrowsePage({super.key, this.path, this.title, this.backLabel});

  /// Null for the top level.
  final String? path;
  final String? title;
  final String? backLabel;

  static Route<void> route({String? path, String? title, String? backLabel}) =>
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            BrowsePage(path: path, title: title, backLabel: backLabel),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool showHidden = ref.watch(showHiddenProvider);
    final AsyncValue<List<DirEntry>> listing = ref.watch(browseProvider(path));
    final List<DirEntry> all = listing.value ?? const <DirEntry>[];
    final List<DirEntry> entries =
        (showHidden ? all : all.where((DirEntry e) => !e.hidden).toList())
          ..sort((DirEntry a, DirEntry b) {
            if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    final int hiddenCount = all.where((DirEntry e) => e.hidden).length;
    final String heading = title ?? context.s('Files');

    return LargeTitlePage(
      title: heading,
      backLabel: backLabel,
      onBack: () => Navigator.of(context).maybePop(),
      grouped: true,
      actions: <Widget>[
        if (hiddenCount > 0)
          NavAction.icon(
            icon: showHidden ? GIcons.eye : GIcons.eyeOff,
            semanticLabel: showHidden
                ? context.s('Hide hidden items')
                : context.s('Show hidden items'),
            onTap: () => ref.read(showHiddenProvider.notifier).toggle(),
          ),
      ],
      onRefresh: () async => ref.invalidate(browseProvider(path)),
      slivers: <Widget>[
        if (path != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                GDesign.gutter,
                0,
                GDesign.gutter,
                GDesign.space16,
              ),
              child: Text(
                path!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: g.figures(g.footnote()),
              ),
            ),
          ),
        if (path == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: GDesign.space24),
              child: GroupedSection(
                children: <Widget>[
                  ListRow(
                    icon: GIcons.help,
                    title: context.s('How Android storage works'),
                    subtitle: context.s(
                      'Seven short chapters on these folders',
                    ),
                    onTap: () => Navigator.of(context).push(LearnPage.route()),
                  ),
                ],
              ),
            ),
          ),
        if (listing.isLoading && all.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(GDesign.space32),
              child: Center(
                child: Text(context.s('Reading'), style: g.footnote()),
              ),
            ),
          )
        else if (entries.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(GDesign.space32),
              child: Text(
                all.isEmpty
                    ? context.s('Nothing here')
                    : context.s('Only hidden items here.'),
                textAlign: TextAlign.center,
                style: g.footnote(),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int i) => _EntryRow(
                entry: entries[i],
                first: i == 0,
                last: i == entries.length - 1,
                onOpen: () => Navigator.of(context).push(
                  BrowsePage.route(
                    path: entries[i].path,
                    title: entries[i].name,
                    backLabel: heading,
                  ),
                ),
              ),
            ),
          ),
        if (hiddenCount > 0 && !showHidden)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                GDesign.gutter * 2,
                GDesign.space12,
                GDesign.gutter * 2,
                0,
              ),
              child: Text(
                hiddenCount == 1
                    ? context.s('1 hidden item')
                    : context.s1('{} hidden items', GFormat.count(hiddenCount)),
                style: g.footnote(),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space32)),
      ],
    );
  }
}

/// A folder or file: glyph, name, count or size with the date, and for a
/// well-known folder a line on what it holds.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.first,
    required this.last,
    required this.onOpen,
  });

  final DirEntry entry;
  final bool first;
  final bool last;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final FolderNote? note = entry.isDirectory ? noteFor(entry.path) : null;
    final bool locked = entry.isDirectory && !entry.readable;
    const Radius r = Radius.circular(GDesign.cardRadius);

    final Widget body = Padding(
      padding: const EdgeInsetsDirectional.only(start: GDesign.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: GDesign.space12 + 2),
            child: Icon(
              locked
                  ? GIcons.lock
                  : entry.isDirectory
                  ? GIcons.folder
                  : _fileGlyph(entry.name),
              size: 22,
              color: entry.isDirectory && !locked ? g.accentText : g.muted,
            ),
          ),
          const SizedBox(width: GDesign.space12),
          Expanded(
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(
                0,
                GDesign.space12,
                GDesign.space16,
                GDesign.space12,
              ),
              decoration: BoxDecoration(
                border: last
                    ? null
                    : Border(bottom: BorderSide(color: g.hairline, width: 0.5)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: g.body(color: locked ? g.muted : g.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _meta(context, entry),
                          style: g.figures(g.footnote()),
                        ),
                      ],
                    ),
                  ),
                  if (note != null)
                    NavAction.icon(
                      icon: GIcons.info,
                      semanticLabel: context.s('About this folder'),
                      onTap: () => _about(context, note),
                    ),
                  if (entry.isDirectory && !locked)
                    Icon(GIcons.forward, size: 18, color: g.faint),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.card,
        borderRadius: BorderRadius.vertical(
          top: first ? r : Radius.zero,
          bottom: last ? r : Radius.zero,
        ),
      ),
      child: entry.isDirectory && !locked
          ? Pressable(onTap: onOpen, scale: 0.99, child: body)
          : body,
    );
  }

  /// What a well-known folder is for, in a sheet, with its chapter.
  void _about(BuildContext context, FolderNote note) {
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(entry.name, style: g.title2()),
              const SizedBox(height: GDesign.space8),
              Text(note.text, style: g.body(color: g.muted)),
              if (note.chapterId != null) ...<Widget>[
                const SizedBox(height: GDesign.space16),
                SecondaryButton(
                  label: context.s('Read the chapter'),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    Navigator.of(
                      context,
                    ).push(ChapterPage.route(note.chapterId!));
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _meta(BuildContext context, DirEntry entry) {
    final String when = _when(context, entry.modifiedMillis);
    if (!entry.isDirectory) {
      return '${GFormat.bytes(entry.sizeBytes)}, $when';
    }
    final int? count = entry.childCount;
    if (count == null) return context.s('Locked by Android');
    final String items = count == 1
        ? context.s('1 item')
        : context.s1('{} items', GFormat.count(count));
    return '$items, $when';
  }

  static String _when(BuildContext context, int millis) {
    if (millis <= 0) return context.s('date unknown');
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(millis);
    final int days = DateTime.now().difference(at).inDays;
    if (days <= 0) return context.s('today');
    if (days == 1) return context.s('yesterday');
    if (days < 30) return context.s1('{} days ago', '$days');
    return MaterialLocalizations.of(context).formatMediumDate(at);
  }

  static IconData _fileGlyph(String name) {
    final String lower = name.toLowerCase();
    bool ends(List<String> exts) => exts.any(lower.endsWith);
    if (ends(<String>['.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif'])) {
      return GIcons.photos;
    }
    if (ends(<String>['.mp4', '.mkv', '.3gp', '.webm', '.mov'])) {
      return GIcons.video;
    }
    if (ends(<String>['.mp3', '.m4a', '.ogg', '.wav', '.opus'])) {
      return GIcons.audio;
    }
    if (ends(<String>['.apk', '.apks', '.xapk'])) return GIcons.download;
    if (ends(<String>['.zip', '.rar', '.7z', '.tar', '.gz'])) {
      return GIcons.archive;
    }
    return GIcons.docs;
  }
}
