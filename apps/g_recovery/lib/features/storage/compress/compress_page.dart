import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/compress_api.g.dart';
import '../../../bridge/compress_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../widgets/shrink_art.dart';
import 'compress_list_page.dart';
import 'compressed_page.dart';
import 'video_list_page.dart';

/// Make smaller: pick screenshots, photos or video.
///
/// The animated card leads with the user's own largest photo shrinking to
/// its measured size. Below it, what these files weigh now (a query, so it
/// is real before anything is encoded) and one row per kind. The saving
/// itself is measured when a list opens.
class CompressPage extends ConsumerWidget {
  const CompressPage({super.key, this.backLabel});

  final String? backLabel;

  static Route<void> route({String? backLabel}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => CompressPage(backLabel: backLabel),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompressSummary? summary = ref.watch(compressSummaryProvider).value;
    final List<CompressedEntry> history =
        ref.watch(compressHistoryProvider).value ?? const <CompressedEntry>[];

    final int shots = summary?.screenshotCount ?? 0;
    final int photos = summary?.photoCount ?? 0;
    final int clips = summary?.videoCount ?? 0;
    final int held =
        (summary?.screenshotBytes ?? 0) +
        (summary?.photoBytes ?? 0) +
        (summary?.videoBytes ?? 0);
    final int freed = history.fold<int>(
      0,
      (int sum, CompressedEntry e) => sum + (e.originalBytes - e.newBytes),
    );
    final bool empty =
        summary != null && shots == 0 && photos == 0 && clips == 0;

    return LargeTitlePage(
      onBack: () => Navigator.of(context).pop(),
      title: context.s('Make smaller'),
      backLabel: backLabel,
      grouped: true,
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.info,
          semanticLabel: context.s('What this does'),
          onTap: () => _explain(context),
        ),
      ],
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Reveal(
            child: _Hero(held: held, empty: empty),
          ),
        ),
        if (!empty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: GDesign.space32),
              child: GroupedSection(
                header: context.s('Choose'),
                children: <Widget>[
                  if (shots > 0)
                    ListRow(
                      icon: GIcons.monitor,
                      title: context.s('Screenshots'),
                      subtitle: context.s1(
                        '{} files, nothing lost',
                        GFormat.count(shots),
                      ),
                      detail: GFormat.bytesOrNull(summary?.screenshotBytes),
                      onTap: () => Navigator.of(
                        context,
                      ).push(CompressListPage.route('screenshot')),
                    ),
                  if (photos > 0)
                    ListRow(
                      icon: GIcons.photos,
                      title: context.s('Photos'),
                      subtitle: context.s1(
                        '{} worth re-saving',
                        GFormat.count(photos),
                      ),
                      detail: GFormat.bytesOrNull(summary?.photoBytes),
                      onTap: () => Navigator.of(
                        context,
                      ).push(CompressListPage.route('photo')),
                    ),
                  ListRow(
                    icon: GIcons.video,
                    title: context.s('Video'),
                    subtitle: clips > 0
                        ? context.s1(
                            clips == 1
                                ? '{} clip in an older format'
                                : '{} clips in an older format',
                            GFormat.count(clips),
                          )
                        : context.s('Already as small as it gets'),
                    detail: clips > 0
                        ? GFormat.bytesOrNull(summary?.videoBytes)
                        : null,
                    onTap: () =>
                        Navigator.of(context).push(VideoListPage.route()),
                  ),
                ],
              ),
            ),
          ),
        if (history.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: GDesign.space32),
              child: GroupedSection(
                header: context.s('Already done'),
                footer: context.s('Originals stay in the trash for 30 days.'),
                children: <Widget>[
                  ListRow(
                    icon: GIcons.checkCircle,
                    title: context.s('Made smaller'),
                    subtitle: context.s1(
                      '{} files',
                      GFormat.count(history.length),
                    ),
                    detail: GFormat.bytes(freed),
                    onTap: () =>
                        Navigator.of(context).push(CompressedPage.route()),
                  ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space48)),
      ],
    );
  }

  void _explain(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: g.muted),
              const SizedBox(width: GDesign.space12),
              Expanded(
                child: Text(text, style: g.body(color: g.muted)),
              ),
            ],
          ),
        );
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space8,
            GDesign.gutter,
            GDesign.space24,
          ),
          children: <Widget>[
            Text(sheet.s('What this does'), style: g.headline()),
            const SizedBox(height: GDesign.space16),
            point(
              GIcons.gauge,
              sheet.s('Every saving is measured by really re-saving the file.'),
            ),
            point(
              GIcons.photos,
              sheet.s('Pictures keep their size, date and place.'),
            ),
            point(
              GIcons.shieldCheck,
              sheet.s('Screenshots keep every pixel. Photos lose a little.'),
            ),
            point(
              GIcons.trash,
              sheet.s('Originals go to the trash for 30 days.'),
            ),
          ],
        );
      },
    );
  }
}

/// The animated card and what the eligible files weigh now.
class _Hero extends StatelessWidget {
  const _Hero({required this.held, required this.empty});

  final int held;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GDesign.cardRadius),
              child: const ShrinkArt(),
            ),
          ),
          const SizedBox(height: GDesign.space16),
          if (empty)
            Text(
              context.s('Everything is already as small as it gets'),
              style: g.headline(),
            )
          else ...<Widget>[
            CountUpText(
              value: held,
              format: (num v) =>
                  context.s1('{} could get smaller', GFormat.bytes(v.round())),
              style: g.figures(g.headline()),
            ),
          ],
        ],
      ),
    );
  }
}
