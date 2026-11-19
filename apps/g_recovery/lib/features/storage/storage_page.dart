import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../bridge/apps_api.g.dart';
import '../../bridge/apps_bridge.dart';
import '../../bridge/compare_api.g.dart';
import '../../bridge/compare_bridge.dart';
import '../../bridge/compare_ledger.dart';
import '../../bridge/compress_api.g.dart';
import '../../bridge/compress_bridge.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/server_api.g.dart';
import '../../bridge/server_bridge.dart';
import '../../bridge/storage_api.g.dart';
import '../../bridge/storage_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/file_thumbnail.dart';
import '../apps/apps_page.dart';
import '../recovery/state/recovery_providers.dart';
import '../server/server_page.dart';
import 'browse/browse_page.dart';
import 'compare/blur_review_page.dart';
import 'compare/compare_review_page.dart';
import 'compress/compress_page.dart';
import 'model/storage_view.dart';
import 'state/storage_breakdown.dart';
import 'state/storage_files.dart';
import 'state/storage_providers.dart';
import 'storage_files_page.dart';
import 'widgets/shrink_art.dart';

/// Clean up: what can go, led by the user's own photos.
///
/// The tab exists to answer "my phone is full, what can I get rid of?". The
/// largest measured saving leads as a photo card with one action; the other
/// ways to free space follow as picture cards; what is using space sits
/// last, as plain rows, for anyone who wants the breakdown.
///
/// Every saving shown is measured from the files themselves. Nothing here
/// deletes for good: files go to the system trash and can come back from
/// Recovery for 30 days.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StorageOverview? overview = ref.watch(storageOverviewProvider).value;
    final RecoveryAccess? access = ref.watch(recoveryAccessProvider).value;
    final bool blind = access != null && !access.allFilesAccess;
    final List<_Win> wins = _wins(context, ref);

    return LargeTitlePage(
      title: context.s('Clean up'),
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.info,
          semanticLabel: context.s('How storage is counted'),
          onTap: () => _explainGap(context),
        ),
      ],
      onRefresh: () async {
        ref.invalidate(storageOverviewProvider);
        ref.invalidate(storageFilesProvider);
        await ref.read(storageOverviewProvider.future);
      },
      slivers: <Widget>[
        if (overview != null)
          SliverToBoxAdapter(child: _Space(overview: overview)),
        if (blind)
          const SliverToBoxAdapter(child: _Blind())
        else if (overview != null) ...<Widget>[
          const SliverToBoxAdapter(child: _ScanStatus()),
          if (wins.isNotEmpty)
            SliverToBoxAdapter(
              child: Reveal(child: _Lead(win: wins.first)),
            ),
          if (wins.length > 1)
            SliverToBoxAdapter(child: _MoreWays(wins: wins.sublist(1))),
          SliverToBoxAdapter(child: _Using(overview: overview)),
        ],
      ],
    );
  }

  /// Every way to free space this phone has right now, largest first. A
  /// way with nothing in it is left out rather than shown as zero.
  static List<_Win> _wins(BuildContext context, WidgetRef ref) {
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    final AsyncValue<ScanRecord?> scan = ref.watch(compareProvider);
    final List<CompareGroup> similar = ref.watch(similarGroupsProvider);
    final List<CompareGroup> exact = ref.watch(exactGroupsProvider);
    final List<BlurredImage> blurred = ref.watch(blurredProvider);
    final StorageQueryResult? large = ref
        .watch(storageFilesProvider(kLargeFilesScope))
        .value;
    final StorageQueryResult? stale = ref
        .watch(storageFilesProvider(kStaleScope))
        .value;
    final CompressSummary? compress = ref.watch(compressSummaryProvider).value;

    ImageProvider thumb(String id, {String kind = 'image'}) =>
        FileThumbnail(fileId: id, bridge: bridge, kind: kind, maxPixels: 480);
    int wasted(List<CompareGroup> g) =>
        g.fold<int>(0, (int s, CompareGroup x) => s + x.wastedBytes);
    List<ImageProvider> fromGroups(List<CompareGroup> g) => <ImageProvider>[
      for (final CompareGroup x in g.take(4)) thumb(x.keepFileId),
    ];

    final List<_Win> wins = <_Win>[
      if (similar.isNotEmpty)
        _Win(
          title: context.s('Similar photos'),
          chip: similar.length == 1
              ? context.s('1 set of near-identical shots')
              : context.s1(
                  '{} sets of near-identical shots',
                  GFormat.count(similar.length),
                ),
          detail: context.s1(
            'Keep the best of each and free {}',
            GFormat.bytes(wasted(similar)),
          ),
          action: context.s('Review similar photos'),
          brief: context.s1('Frees {}', GFormat.bytes(wasted(similar))),
          bytes: wasted(similar),
          photos: fromGroups(similar),
          open: (BuildContext c) =>
              Navigator.of(c).push(CompareReviewPage.route('similar')),
        ),
      if (exact.isNotEmpty)
        _Win(
          title: context.s('Exact copies'),
          chip: exact.length == 1
              ? context.s('1 set of copies')
              : context.s1('{} sets of copies', GFormat.count(exact.length)),
          detail: context.s1(
            'Identical files, free {}',
            GFormat.bytes(wasted(exact)),
          ),
          action: context.s('Review copies'),
          brief: context.s1('Frees {}', GFormat.bytes(wasted(exact))),
          bytes: wasted(exact),
          photos: fromGroups(exact),
          open: (BuildContext c) =>
              Navigator.of(c).push(CompareReviewPage.route('exact')),
        ),
      if (blurred.isNotEmpty)
        _Win(
          title: context.s('Blurred'),
          chip: context.s1('{} blurry photos', GFormat.count(blurred.length)),
          detail: context.s1(
            '{} photos worth a second look',
            GFormat.count(blurred.length),
          ),
          action: context.s('Review blurred photos'),
          brief: context.s1('{} photos', GFormat.count(blurred.length)),
          bytes: blurred.fold<int>(
            0,
            (int s, BlurredImage b) => s + b.sizeBytes,
          ),
          photos: <ImageProvider>[
            for (final BlurredImage b in blurred.take(4)) thumb(b.fileId),
          ],
          open: (BuildContext c) =>
              Navigator.of(c).push(BlurReviewPage.route()),
        ),
      if (large != null && large.files.isNotEmpty)
        _Win(
          title: context.s('Biggest files'),
          chip: context.s('The ten biggest'),
          detail: context.s1(
            '{} in your ten biggest files',
            GFormat.bytes(
              large.files
                  .take(10)
                  .fold<int>(0, (int s, StorageFile f) => s + f.sizeBytes),
            ),
          ),
          action: context.s('See biggest files'),
          brief: context.s1(
            '{} in ten files',
            GFormat.bytes(
              large.files
                  .take(10)
                  .fold<int>(0, (int s, StorageFile f) => s + f.sizeBytes),
            ),
          ),
          bytes: large.files
              .take(10)
              .fold<int>(0, (int s, StorageFile f) => s + f.sizeBytes),
          photos: <ImageProvider>[
            for (final StorageFile f in large.files.where(_visual).take(4))
              thumb(f.fileId, kind: f.kind),
          ],
          open: (BuildContext c) => Navigator.of(c).push(
            StorageFilesPage.route(
              kLargeFilesScope,
              backLabel: c.s('Clean up'),
            ),
          ),
        ),
      if (stale != null && stale.matchBytes >= _worthShowing)
        _Win(
          title: context.s('Untouched'),
          chip: context.s('Two years or older'),
          detail: context.s1(
            '{} not opened in two years',
            GFormat.bytes(stale.matchBytes),
          ),
          action: context.s('See untouched files'),
          brief: GFormat.bytes(stale.matchBytes),
          bytes: stale.matchBytes,
          photos: <ImageProvider>[
            for (final StorageFile f in stale.files.where(_visual).take(4))
              thumb(f.fileId, kind: f.kind),
          ],
          open: (BuildContext c) => Navigator.of(c).push(
            StorageFilesPage.route(kStaleScope, backLabel: c.s('Clean up')),
          ),
        ),
      if (compress != null && _held(compress) > 0)
        _Win(
          title: context.s('Make smaller'),
          chip: context.s('Same picture, smaller file'),
          detail: context.s1(
            '{} in photos and screenshots',
            GFormat.bytes(_held(compress)),
          ),
          action: context.s('Make files smaller'),
          brief: context.s1('{} to shrink', GFormat.bytes(_held(compress))),
          bytes: _held(compress),
          photos: const <ImageProvider>[],
          art: (bool compact) => ShrinkArt(compact: compact),
          open: (BuildContext c) => Navigator.of(
            c,
          ).push(CompressPage.route(backLabel: c.s('Clean up'))),
        ),
    ]..sort((_Win a, _Win b) => b.bytes.compareTo(a.bytes));

    // Before the photo scan has run, the scan itself is the next step.
    if (scan.value == null && !scan.isLoading) {
      wins.add(
        _Win(
          title: context.s('Similar and duplicate photos'),
          chip: context.s('Not checked yet'),
          detail: context.s('Copies and blur'),
          action: context.s('Check my photos'),
          brief: context.s('Not checked yet'),
          bytes: -1,
          photos: const <ImageProvider>[],
          icon: GIcons.scan,
          open: (BuildContext c) => _startScan(ref),
        ),
      );
    }
    return wins;
  }

  static const int _worthShowing = 10 * 1024 * 1024;

  static bool _visual(StorageFile f) => f.kind == 'image' || f.kind == 'video';

  static int _held(CompressSummary c) =>
      c.screenshotBytes + c.photoBytes + (c.videoBytes ?? 0);

  void _explainGap(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        Widget line(String text) => Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space8),
          child: Text(text, style: g.body(color: g.muted)),
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
            Text(context.s('How storage is counted'), style: g.title2()),
            const SizedBox(height: GDesign.space12),
            line(
              context.s(
                'Every saving here is measured from the files themselves. '
                'Nothing is deleted for good: files go to the system trash and '
                'can come back from Recovery for 30 days.',
              ),
            ),
            line(
              context.s(
                'Apps and the system are one figure, because no app, '
                'including this one, can list what is inside them.',
              ),
            ),
          ],
        );
      },
    );
  }
}

void _startScan(WidgetRef ref) => ref
    .read(compareProvider.notifier)
    .run(
      fingerprint: storageFingerprint(ref.read(storageOverviewProvider).value),
    );

/// One way to free space, as the cards show it.
@immutable
class _Win {
  const _Win({
    required this.title,
    required this.chip,
    required this.detail,
    required this.action,
    required this.bytes,
    required this.photos,
    required this.brief,
    required this.open,
    this.icon,
    this.art,
  });

  final String title;

  /// One short figure for the small cards, such as "Frees 53.6 MB".
  final String brief;

  /// Over the lead photo.
  final String chip;
  final String detail;

  /// The lead card's button.
  final String action;

  /// Measured saving, for ordering. Negative for a step with no figure yet.
  final int bytes;

  /// Up to four of the user's own files, for the collage.
  final List<ImageProvider> photos;

  /// Shown instead of photos when the way has none to show.
  final IconData? icon;

  /// A live picture drawn instead of the collage, given whether the card is
  /// the small one.
  final Widget Function(bool compact)? art;
  final void Function(BuildContext context) open;
}

// ── Free space ───────────────────────────────────────────────────────────

/// "117 GB free", the total, and one slim bar.
class _Space extends StatelessWidget {
  const _Space({required this.overview});

  final StorageOverview overview;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int total = overview.volume.totalBytes;
    final double used = total <= 0 ? 0 : overview.volume.usedBytes / total;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: CountUpText(
                  value: overview.volume.freeBytes,
                  format: (num v) =>
                      context.s1('{} free', GFormat.bytes(v.round())),
                  style: g.figures(g.headline()),
                ),
              ),
              Text(
                context.s1('of {}', GFormat.bytes(total)),
                style: g.figures(g.footnote()),
              ),
            ],
          ),
          const SizedBox(height: GDesign.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(color: g.isDark ? g.hairline : g.fill),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: used.clamp(0.0, 1.0),
                    child: ColoredBox(color: g.text.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo scan while it runs: progress and Stop.
class _ScanStatus extends ConsumerWidget {
  const _ScanStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    if (!ref.watch(compareProvider).isLoading) return const SizedBox.shrink();
    final CompareProgress? p = ref.watch(compareProgressProvider).value;
    final bool sized = p != null && p.total > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        0,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(context.s('Reading your photos'), style: g.headline()),
                const SizedBox(height: GDesign.space8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: sized ? (p.scanned / p.total).clamp(0.0, 1.0) : null,
                    minHeight: 4,
                    color: g.accent,
                    backgroundColor: g.fill,
                  ),
                ),
                const SizedBox(height: GDesign.space4),
                Text(
                  sized
                      ? '${GFormat.count(p.scanned)} / ${GFormat.count(p.total)}'
                      : context.s('Starting'),
                  style: g.figures(g.footnote()),
                ),
              ],
            ),
          ),
          NavAction.text(
            label: context.s('Stop'),
            onTap: () => ref.read(compareProvider.notifier).cancel(),
          ),
        ],
      ),
    );
  }
}

// ── Lead and more ways ───────────────────────────────────────────────────

/// Up to four photos as one rounded block: one fills it, two split it,
/// three or four make a grid.
class _Collage extends StatelessWidget {
  const _Collage({
    required this.photos,
    required this.radius,
    this.icon,
    this.art,
  });

  final List<ImageProvider> photos;
  final double radius;
  final IconData? icon;
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Widget body;
    if (art != null) {
      body = art!;
    } else if (photos.isEmpty) {
      body = ColoredBox(
        color: g.isDark ? g.card : g.fill,
        child: Center(
          child: Icon(icon ?? GIcons.photos, size: 40, color: g.muted),
        ),
      );
    } else if (photos.length == 1) {
      body = SizedPhoto(image: photos.first);
    } else if (photos.length == 2) {
      body = Row(
        children: <Widget>[
          Expanded(child: SizedPhoto(image: photos[0])),
          const SizedBox(width: 2),
          Expanded(child: SizedPhoto(image: photos[1])),
        ],
      );
    } else {
      body = GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        childAspectRatio: 1.33,
        children: <Widget>[
          for (final ImageProvider p in photos.take(4)) SizedPhoto(image: p),
        ],
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: body);
  }
}

/// The biggest saving: a collage of the user's own photos, what it is, what
/// it frees, and the screen's one primary action.
class _Lead extends StatelessWidget {
  const _Lead({required this.win});

  final _Win win;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Pressable(
            onTap: () => win.open(context),
            scale: 0.98,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _Collage(
                        photos: win.photos,
                        radius: GDesign.cardRadius,
                        icon: win.icon,
                        art: win.art?.call(false),
                      ),
                      PositionedDirectional(
                        start: GDesign.space12,
                        top: GDesign.space12,
                        child: PhotoChip(win.chip),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GDesign.space12),
                Text(win.title, style: g.headline()),
                const SizedBox(height: 2),
                Text(win.detail, style: g.figures(g.footnote())),
              ],
            ),
          ),
          const SizedBox(height: GDesign.space16),
          PrimaryButton(label: win.action, onTap: () => win.open(context)),
        ],
      ),
    );
  }
}

/// The other ways, as a sideways row of picture cards.
class _MoreWays extends StatelessWidget {
  const _MoreWays({required this.wins});

  final List<_Win> wins;

  static const double _side = 150;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(context.s('More ways to free space')),
        SizedBox(
          height: _side + GDesign.space8 + 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            itemCount: wins.length,
            separatorBuilder: (_, _) => const SizedBox(width: GDesign.space12),
            itemBuilder: (BuildContext context, int i) {
              final _Win w = wins[i];
              return Reveal(
                index: i + 1,
                child: Pressable(
                  onTap: () => w.open(context),
                  child: SizedBox(
                    width: _side,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox.square(
                          dimension: _side,
                          child: _Collage(
                            photos: w.photos,
                            radius: GDesign.tileRadius,
                            icon: w.icon,
                            art: w.art?.call(true),
                          ),
                        ),
                        const SizedBox(height: GDesign.space8),
                        Text(
                          w.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: g.footnote(
                            color: g.text,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          w.brief,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: g.figures(g.footnote()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── What is using space ──────────────────────────────────────────────────

/// The breakdown, last and plain: each kind, apps and system, folders.
class _Using extends ConsumerWidget {
  const _Using({required this.overview});

  final StorageOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StorageBreakdown? breakdown = ref.watch(storageBreakdownProvider);
    final AppsState? apps = ref.watch(appsStateProvider).value;
    final ServerConfig? server = ref.watch(serverConfigProvider).value;
    final List<StorageBucket> buckets = <StorageBucket>[
      ...?breakdown?.buckets.where((StorageBucket b) => b.bytes > 0),
    ]..sort((StorageBucket a, StorageBucket b) => b.bytes.compareTo(a.bytes));
    final int gap = breakdown?.unaccountedBytes ?? 0;

    return Padding(
      padding: const EdgeInsets.only(top: GDesign.space32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GroupedSection(
            header: context.s('What is using space'),
            children: <Widget>[
              for (final StorageBucket b in buckets)
                ListRow(
                  icon: _kindIcon(b.id),
                  title: b.label,
                  detail: GFormat.bytes(b.bytes),
                  onTap: b.drillable
                      ? () => Navigator.of(context).push(
                          StorageFilesPage.route(
                            StorageScope(title: b.label, kind: b.id),
                            backLabel: context.s('Clean up'),
                          ),
                        )
                      : null,
                ),
              ListRow(
                icon: GIcons.grid,
                title: context.s('Apps and system'),
                detail: GFormat.bytes(gap),
                subtitle: apps != null && apps.usageAccess
                    ? context.s1(
                        '{} of it is app cache',
                        GFormat.bytes(apps.cacheBytes),
                      )
                    : null,
                onTap: () => Navigator.of(context).push(AppsPage.route()),
              ),
              ListRow(
                icon: GIcons.folderOpen,
                title: context.s('All folders'),
                onTap: () => Navigator.of(
                  context,
                ).push(BrowsePage.route(backLabel: context.s('Clean up'))),
              ),
              if (server != null)
                ListRow(
                  icon: GIcons.server,
                  title: server.label,
                  subtitle: context.s('Files copied to a machine you own'),
                  onTap: () => Navigator.of(context).push(ServerPage.route()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _kindIcon(String id) => switch (id) {
    'image' || 'images' => GIcons.photos,
    'video' || 'videos' => GIcons.video,
    'audio' => GIcons.audio,
    'document' || 'documents' => GIcons.docs,
    _ => GIcons.folder,
  };
}

/// File access is off: the totals are real, nothing under them is visible.
class _Blind extends ConsumerWidget {
  const _Blind();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.s('Only what this app made is visible'),
            style: g.headline(),
          ),
          const SizedBox(height: 2),
          Text(
            context.s('Turn on file access to see the rest.'),
            style: g.footnote(),
          ),
          const SizedBox(height: GDesign.space16),
          PrimaryButton(
            label: context.s('Turn on file access'),
            icon: GIcons.folderOpen,
            onTap: () async {
              await ref.read(recoveryBridgeProvider).requestAllFilesAccess();
              ref.invalidate(recoveryAccessProvider);
            },
          ),
        ],
      ),
    );
  }
}
