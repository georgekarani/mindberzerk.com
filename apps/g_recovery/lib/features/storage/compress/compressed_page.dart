import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/compress_api.g.dart';
import '../../../bridge/compress_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../state/storage_files.dart';

/// Every file already made smaller, with how long its original can still
/// come back from the trash.
///
/// Nothing here moved: each file is still in the gallery. The days left on
/// the original are the one actionable fact on a row, so they get the
/// trailing slot.
class CompressedPage extends ConsumerWidget {
  const CompressedPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const CompressedPage(),
  );

  /// Android keeps a trashed item for 30 days on every supported device.
  static const int _trashDays = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<CompressedEntry> entries =
        ref.watch(compressHistoryProvider).value ?? const <CompressedEntry>[];
    final int freed = entries.fold<int>(
      0,
      (int sum, CompressedEntry e) => sum + (e.originalBytes - e.newBytes),
    );

    return LargeTitlePage(
      onBack: () => Navigator.of(context).pop(),
      title: context.s('Made smaller'),
      backLabel: context.s('Make smaller'),
      grouped: true,
      slivers: <Widget>[
        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Reveal(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(GIcons.checkCircle, size: 40, color: g.faint),
                    const SizedBox(height: GDesign.space12),
                    Text(
                      context.s('Nothing made smaller yet'),
                      style: g.headline(),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...<Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                GDesign.gutter,
                GDesign.space8,
                GDesign.gutter,
                GDesign.space24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CountUpText(
                    value: freed,
                    format: (num v) =>
                        context.s1('{} freed', GFormat.bytes(v.round())),
                    style: g.figures(g.largeTitle()),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.s1('{} files', GFormat.count(entries.length)),
                    style: g.figures(g.footnote()),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int i) => Reveal(
                index: i,
                rise: 8,
                child: _Entry(
                  entry: entries[i],
                  first: i == 0,
                  last: i == entries.length - 1,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                GDesign.gutter + GDesign.space16,
                GDesign.space8,
                GDesign.gutter,
                GDesign.space48,
              ),
              child: Text(
                context.s('Originals stay in the trash for 30 days.'),
                style: g.footnote(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One file: thumbnail, before and after, and days left on the original.
class _Entry extends ConsumerWidget {
  const _Entry({required this.entry, required this.first, required this.last});

  final CompressedEntry entry;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Uint8List? thumb = ref
        .watch(
          storageThumbProvider(
            ThumbRequest(fileId: entry.fileId, kind: 'image', maxPixels: 256),
          ),
        )
        .value;

    final DateTime gone = DateTime.fromMillisecondsSinceEpoch(
      entry.whenMillis,
    ).add(const Duration(days: CompressedPage._trashDays));
    final int left = gone.difference(DateTime.now()).inDays;
    const Radius r = Radius.circular(GDesign.cardRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.card,
        borderRadius: BorderRadius.vertical(
          top: first ? r : Radius.zero,
          bottom: last ? r : Radius.zero,
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: GDesign.space12),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(GDesign.tileRadius - 4),
              child: SizedBox.square(
                dimension: 44,
                child: thumb == null
                    ? ColoredBox(
                        color: g.fill,
                        child: Icon(GIcons.photos, size: 18, color: g.faint),
                      )
                    : Image.memory(thumb, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: GDesign.space12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: last
                      ? null
                      : Border(
                          bottom: BorderSide(color: g.hairline, width: 0.5),
                        ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    0,
                    GDesign.space12,
                    GDesign.space16,
                    GDesign.space12,
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
                              style: g.body(),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${GFormat.bytes(entry.originalBytes)} to '
                              '${GFormat.bytes(entry.newBytes)}',
                              style: g.figures(g.footnote()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GDesign.space8),
                      Text(
                        left > 0
                            ? context.s1(
                                left == 1 ? '{} day left' : '{} days left',
                                left,
                              )
                            : context.s('Original gone'),
                        style: g.figures(g.footnote()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
