import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../core/i18n/g_strings.dart';
import '../../ui/g_card.dart';
import 'chapter_page.dart';
import 'state/learn_model.dart';
import 'state/learn_providers.dart';

/// The guide: seven short chapters, each a numbered row with its icon and
/// reading time.
class LearnPage extends ConsumerWidget {
  const LearnPage({super.key, this.backLabel});

  final String? backLabel;

  static Route<void> route({String? backLabel}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => LearnPage(backLabel: backLabel),
  );

  /// One glyph per chapter, shared with the chapter page's hero.
  static IconData iconFor(String id) => switch (id) {
    LearnIds.whereFilesLive => GIcons.device,
    LearnIds.standardFolders => GIcons.folder,
    LearnIds.androidData => GIcons.lock,
    LearnIds.theTrash => GIcons.trash,
    LearnIds.thumbnails => GIcons.images,
    LearnIds.scopedStorage => GIcons.shield,
    LearnIds.factoryReset => GIcons.refresh,
    _ => GIcons.docs,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final LearnBook? book = ref.watch(learnBookProvider).value;
    final int minutes =
        book?.chapters.fold<int>(0, (int m, LearnChapter c) => m + c.minutes) ??
        0;

    return GGroundScope(
      grouped: true,
      child: LargeTitlePage(
        title: context.s('How storage works'),
        grouped: true,
        backLabel: backLabel ?? context.s('Browse'),
        onBack: () => Navigator.of(context).maybePop(),
        slivers: <Widget>[
          if (book == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else ...<Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  0,
                  GDesign.gutter,
                  GDesign.space24,
                ),
                child: Text(
                  context.s1(
                    '${book.chapters.length} chapters, {} minutes',
                    minutes,
                  ),
                  style: g.figures(g.footnote()),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: GroupedSection(
                children: <Widget>[
                  for (int i = 0; i < book.chapters.length; i++)
                    ListRow(
                      leading: _Number(n: i + 1),
                      title: book.chapters[i].title,
                      // Under the title, so long titles keep the full width.
                      subtitle: context.s1('{} min', book.chapters[i].minutes),
                      onTap: () => Navigator.of(
                        context,
                      ).push(ChapterPage.route(book.chapters[i].id)),
                    ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: GDesign.space48)),
          ],
        ],
      ),
    );
  }
}

/// The chapter number in an accent ring.
class _Number extends StatelessWidget {
  const _Number({required this.n});

  final int n;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: g.accentText, width: 1.5),
      ),
      child: Text(
        '$n',
        style: g.figures(
          g.caption(color: g.accentText, weight: FontWeight.w600),
        ),
      ),
    );
  }
}
