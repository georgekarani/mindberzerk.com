import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../core/i18n/g_strings.dart';
import 'learn_page.dart';
import 'state/learn_model.dart';
import 'state/learn_providers.dart';
import 'widgets/content_block_view.dart';

/// One chapter as a reading page: a large icon that settles in, the text,
/// then the next chapter as one tap at the end.
class ChapterPage extends ConsumerWidget {
  const ChapterPage({required this.chapterId, super.key});

  final String chapterId;

  static Route<void> route(String chapterId) => MaterialPageRoute<void>(
    builder: (BuildContext context) => ChapterPage(chapterId: chapterId),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final LearnBook? book = ref.watch(learnBookProvider).value;
    final LearnChapter? chapter = book?.chapter(chapterId);
    final int at = book == null || chapter == null
        ? -1
        : book.chapters.indexOf(chapter);
    final LearnChapter? next = at >= 0 && at + 1 < book!.chapters.length
        ? book.chapters[at + 1]
        : null;

    return LargeTitlePage(
      title: chapter?.title ?? context.s('Chapter'),
      backLabel: context.s('Guide'),
      onBack: () => Navigator.of(context).maybePop(),
      slivers: <Widget>[
        if (chapter == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                context.s('Not in this version of the guide'),
                style: g.footnote(),
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
              child: Row(
                children: <Widget>[
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.4, end: 1),
                    duration: GDesign.motion(context, GDesign.slow),
                    curve: Curves.easeOutBack,
                    builder: (BuildContext context, double s, Widget? child) =>
                        Transform.scale(scale: s, child: child),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: g.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        LearnPage.iconFor(chapter.id),
                        size: 28,
                        color: g.accentText,
                      ),
                    ),
                  ),
                  const SizedBox(width: GDesign.space16),
                  Expanded(
                    child: Text(
                      context.s1('Chapter {}, ${chapter.minutes} min', at + 1),
                      style: g.figures(g.footnote()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            sliver: SliverList.builder(
              itemCount: chapter.blocks.length,
              itemBuilder: (BuildContext context, int i) => Reveal(
                index: i,
                child: ContentBlockView(block: chapter.blocks[i]),
              ),
            ),
          ),
          if (next != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: GDesign.space24),
                child: GroupedSection(
                  header: context.s('Next'),
                  children: <Widget>[
                    ListRow(
                      icon: LearnPage.iconFor(next.id),
                      title: next.title,
                      detail: context.s1('{} min', next.minutes),
                      onTap: () => Navigator.of(
                        context,
                      ).pushReplacement(ChapterPage.route(next.id)),
                    ),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space48)),
        ],
      ],
    );
  }
}
