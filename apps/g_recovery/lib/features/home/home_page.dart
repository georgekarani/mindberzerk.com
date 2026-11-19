import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../bridge/messages_api.g.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/recovery_bridge.dart';
import '../../bridge/storage_api.g.dart';
import '../../bridge/storage_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/file_thumbnail.dart';
import '../../ui/g_sort.dart';
import '../../ui/g_thumbnail.dart';
import '../../ui/media/media_stage.dart';
import '../../ui/media/playable_media.dart';
import '../messages/messages_page.dart';
import '../messages/state/messages_providers.dart';
import '../recovery/category_page.dart';
import '../recovery/sources_page.dart';
import '../recovery/state/recovery_providers.dart';
import '../review/review_page.dart';
import '../search/search_page.dart';
import '../storage/state/storage_files.dart';
import '../storage/state/storage_providers.dart';
import '../viewer/media_viewer.dart';
import 'widgets/empty_scenes.dart';

/// Home: the category bar leads, the user's own deleted photos fill the card
/// under it, and anything that needs attention follows as plain rows.
///
/// Picking a category changes the feed in place, the way Airbnb's bar does;
/// the full lists open from the card.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.category = 0});

  /// The category open first, by its place on the bar.
  final int category;

  /// Everything that can come back, pushed from the dashboard.
  static Route<void> route({int category = 0}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => HomePage(category: category),
  );

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late _Category _category =
      _Category.values[widget.category.clamp(0, _Category.values.length - 1)];

  Future<void> _refresh() async {
    ref.invalidate(prescanProvider);
    ref.invalidate(recoveryItemsProvider);
    await ref.read(prescanProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    // A background scan that has just finished changes every count here, so
    // the prescan and the lists are asked again the moment it stops.
    ref.listen<AsyncValue<BackgroundScanState?>>(backgroundScanProvider, (
      AsyncValue<BackgroundScanState?>? was,
      AsyncValue<BackgroundScanState?> now,
    ) {
      final bool wasRunning = was?.value?.running ?? false;
      final bool isRunning = now.value?.running ?? false;
      if (wasRunning && !isRunning) {
        ref.invalidate(prescanProvider);
        ref.invalidate(recoveryItemsProvider);
      }
    });

    final _HomeView view = _HomeView.read(ref);

    return LargeTitlePage(
      title: context.s('Can come back'),
      backLabel: context.s('Recovery'),
      onBack: () => Navigator.of(context).pop(),
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.radar,
          semanticLabel: context.s('Where it looks'),
          onTap: () => Navigator.of(context).push(SourcesPage.route()),
        ),
        NavAction.icon(
          icon: GIcons.search,
          semanticLabel: context.s('Search files, photos, messages'),
          onTap: () => Navigator.of(context).push(SearchPage.route()),
        ),
      ],
      pinned: CategoryBar(
        items: <CategoryItem>[
          for (final _Category c in _Category.values)
            CategoryItem(icon: c.icon, label: c.label(context)),
        ],
        selected: _category.index,
        onSelected: (int i) => setState(() => _category = _Category.values[i]),
      ),
      pinnedExtent: GDesign.categoryBarHeight,
      onRefresh: _refresh,
      slivers: <Widget>[
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space24)),
        if (view.mode == _Mode.ready || view.mode == _Mode.running) ...<Widget>[
          if (view.mode == _Mode.running)
            SliverToBoxAdapter(child: _ScanCard(scan: view.scan!)),
          SliverToBoxAdapter(
            child: DirectionalSwitcher(
              index: _category.index,
              child: _category == _Category.messages
                  ? const _MessagesFeed(key: ValueKey<String>('messages'))
                  : _Feed(
                      key: ValueKey<_Category>(_category),
                      category: _category,
                    ),
            ),
          ),
        ] else
          SliverToBoxAdapter(child: _StatusCard(mode: view.mode)),
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space32)),
      ],
    );
  }
}

/// The categories on the bar, in a fixed order so the bar never reshuffles
/// under the user's thumb as counts change.
enum _Category {
  photos(GIcons.photos),
  video(GIcons.video),
  statuses(GIcons.status),
  messages(GIcons.messages),
  docs(GIcons.docs),
  audio(GIcons.audio),
  previews(GIcons.previews);

  const _Category(this.icon);

  final IconData icon;

  String label(BuildContext context) => switch (this) {
    _Category.photos => context.s('Photos'),
    _Category.video => context.s('Video'),
    _Category.statuses => context.s('Statuses'),
    _Category.messages => context.s('Messages'),
    _Category.docs => context.s('Docs'),
    _Category.audio => context.s('Audio'),
    _Category.previews => context.s('Previews'),
  };

  /// What this category lists. Deleted items only, except statuses and
  /// previews, which are their own groups.
  RecoveryQuery get query => switch (this) {
    _Category.photos => const RecoveryQuery(
      sourceIds: kAllSourceIds,
      kind: 'image',
    ),
    _Category.video => const RecoveryQuery(
      sourceIds: kAllSourceIds,
      kind: 'video',
    ),
    _Category.statuses => const RecoveryQuery(
      sourceIds: <String>['app_trash'],
      roles: <String>{kRoleStatus},
    ),
    _Category.docs => const RecoveryQuery(
      sourceIds: kAllSourceIds,
      kind: 'document',
    ),
    _Category.audio => const RecoveryQuery(
      sourceIds: kAllSourceIds,
      kind: 'audio',
    ),
    _Category.previews => const RecoveryQuery(
      sourceIds: <String>['thumbnails'],
      roles: <String>{kRoleCache},
    ),
    _Category.messages => const RecoveryQuery(sourceIds: <String>[]),
  };

  /// Photos lead with a picture; documents and audio lead with their names.
  bool get visual =>
      this == _Category.photos ||
      this == _Category.video ||
      this == _Category.statuses ||
      this == _Category.previews;

  /// "128 photos can come back", with the singular spelled out so no
  /// language has to guess at plural rules from a number.
  String headline(BuildContext context, int n) {
    final String count = GFormat.count(n);
    return switch (this) {
      _Category.photos =>
        n == 1
            ? context.s('1 photo can come back')
            : context.s1('{} photos can come back', count),
      _Category.video =>
        n == 1
            ? context.s('1 video can come back')
            : context.s1('{} videos can come back', count),
      _Category.statuses =>
        n == 1
            ? context.s('1 status can be saved')
            : context.s1('{} statuses can be saved', count),
      _Category.docs =>
        n == 1
            ? context.s('1 document can come back')
            : context.s1('{} documents can come back', count),
      _Category.audio =>
        n == 1
            ? context.s('1 audio file can come back')
            : context.s1('{} audio files can come back', count),
      _Category.previews =>
        n == 1
            ? context.s('1 preview of a lost photo')
            : context.s1('{} previews of lost photos', count),
      _Category.messages => context.s1('{} messages kept', count),
    };
  }

  void openAll(BuildContext context) {
    final RecoveryQuery q = query;
    Navigator.of(context).push(
      CategoryPage.route(
        title: label(context),
        backLabel: context.s('Recovery'),
        kind: q.kind,
        sourceIds: q.sourceIds,
        roles: q.roles,
      ),
    );
  }
}

/// What the screen as a whole is showing, before any category applies.
enum _Mode {
  /// The prescan has not answered yet.
  loading,

  /// A full scan is walking the phone.
  running,

  /// Nothing was counted because file access is off.
  blind,

  /// Nothing in the bins, and no full scan has run.
  empty,

  /// Nothing in the bins after a full scan.
  clear,

  /// There is something to bring back.
  ready,
}

/// One read of every provider the mode depends on, so the card and its
/// action can never disagree about which state the screen is in.
@immutable
class _HomeView {
  const _HomeView({required this.mode, this.summary, this.scan});

  factory _HomeView.read(WidgetRef ref) {
    final RecoverySummary? summary = ref.watch(prescanProvider).value;
    final bool scanned = ref.watch(scanControllerProvider).value != null;
    final BackgroundScanState? scan = ref.watch(backgroundScanProvider).value;

    final _Mode mode;
    if (scan?.running ?? false) {
      mode = _Mode.running;
    } else if (summary == null) {
      mode = _Mode.loading;
    } else if (summary.deletedItems == 0 && summary.partial) {
      mode = _Mode.blind;
    } else if (summary.deletedItems == 0 &&
        summary.statusItems == 0 &&
        summary.previewItems == 0) {
      // Media still inside chat apps is not something to bring back, so it
      // does not make the screen ready on its own.
      mode = scanned ? _Mode.clear : _Mode.empty;
    } else {
      mode = _Mode.ready;
    }
    return _HomeView(mode: mode, summary: summary, scan: scan);
  }

  final _Mode mode;
  final RecoverySummary? summary;
  final BackgroundScanState? scan;
}

// ── Feed ─────────────────────────────────────────────────────────────────

/// One category's feed: the lead, the primary action, then what is about to
/// leave the trash.
class _Feed extends ConsumerWidget {
  const _Feed({required this.category, super.key});

  final _Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecoverableItem>> items = ref.watch(
      recoveryItemsProvider(category.query),
    );

    return items.when(
      skipLoadingOnRefresh: true,
      loading: () => _LeadPlaceholder(visual: category.visual),
      error: (Object _, StackTrace _) => _Quiet(
        text: context.s('This list could not be read. Pull to try again.'),
      ),
      data: (List<RecoverableItem> list) {
        if (list.isEmpty) return _Empty(category: category);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (category.visual)
              _PhotoLead(category: category, items: list)
            else
              _FileLead(category: category, items: list),
            _LeavingSoon(items: list),
          ],
        );
      },
    );
  }
}

/// The newest deleted photo as a large card, with the count and size under
/// it and the screen's one primary action below.
class _PhotoLead extends ConsumerWidget {
  const _PhotoLead({required this.category, required this.items});

  final _Category category;
  final List<RecoverableItem> items;

  /// A lone photo opens straight onto its string; more open the grid.
  void _open(BuildContext context, WidgetRef ref) {
    if (items.length == 1) {
      openHangingReview(context, ref, items);
    } else {
      category.openAll(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    final RecoverableItem lead = items.first;
    final bool viewOnly = category == _Category.previews;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PhotoCard(
            image: ItemThumbnail(
              itemId: lead.itemId,
              bridge: bridge,
              maxPixels: 1080,
            ),
            semanticLabel: lead.name,
            chip: _deletedLabel(context, lead),
            title: category.headline(context, items.length),
            detail: _sizeLine(context, items),
            onTap: () => _open(context, ref),
          ),
          if (!viewOnly) ...<Widget>[
            const SizedBox(height: GDesign.space16),
            PrimaryButton(
              label: context.s('Review and restore'),
              onTap: () => _open(context, ref),
            ),
          ],
        ],
      ),
    );
  }
}

/// Documents and audio: the count, the five newest by name, and the action.
class _FileLead extends StatelessWidget {
  const _FileLead({required this.category, required this.items});

  final _Category category;
  final List<RecoverableItem> items;

  static const int _shown = 5;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<RecoverableItem> top = items.take(_shown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                category.headline(context, items.length),
                style: g.headline(),
              ),
              const SizedBox(height: 2),
              Text(_sizeLine(context, items), style: g.footnote()),
              const SizedBox(height: GDesign.space16),
            ],
          ),
        ),
        _FileRows(icon: category.icon, items: top, all: items),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space16,
            GDesign.gutter,
            0,
          ),
          child: PrimaryButton(
            label: context.s('Review and restore'),
            onTap: () => category.openAll(context),
          ),
        ),
      ],
    );
  }
}

/// Rows on a card, the grouped-list look on a plain ground.
class _FileRows extends ConsumerWidget {
  const _FileRows({required this.icon, required this.items, required this.all});

  final IconData icon;
  final List<RecoverableItem> items;
  final List<RecoverableItem> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: g.hairline, width: 0.5),
          borderRadius: BorderRadius.circular(GDesign.cardRadius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GDesign.cardRadius),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                _RowSeparator(
                  last: i == items.length - 1,
                  child: ListRow(
                    // Audio and video play right here, without opening.
                    icon:
                        PlayableMedia.canPlay(items[i].kind, items[i].mimeType)
                        ? null
                        : icon,
                    leading:
                        PlayableMedia.canPlay(items[i].kind, items[i].mimeType)
                        ? PlayRing(
                            media: PlayableMedia.recoverable(items[i], bridge),
                          )
                        : null,
                    title: items[i].name,
                    subtitle: _fileLine(context, items[i]),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MediaViewer.route(items: all, index: i)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [ListRow] draws its own separator only inside a [GroupedSection]. Outside
/// one it reads the default (last row, no line), so rows here are wrapped in
/// a section-shaped scope by hand.
class _RowSeparator extends StatelessWidget {
  const _RowSeparator({required this.last, required this.child});

  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    if (last) return child;
    return Stack(
      children: <Widget>[
        child,
        PositionedDirectional(
          start: 54,
          end: 0,
          bottom: 0,
          child: Container(height: 0.5, color: g.hairline),
        ),
      ],
    );
  }
}

/// A sideways row of what leaves the trash first, soonest on the left.
/// Nothing at all when no item carries an expiry date.
class _LeavingSoon extends ConsumerWidget {
  const _LeavingSoon({required this.items});

  final List<RecoverableItem> items;

  static const int _shown = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RecoverableItem> soon =
        items
            .where(
              (RecoverableItem i) =>
                  i.expiresInDays != null &&
                  (i.kind == 'image' || i.kind == 'video'),
            )
            .toList()
          ..sort(
            (RecoverableItem a, RecoverableItem b) =>
                a.expiresInDays!.compareTo(b.expiresInDays!),
          );
    if (soon.isEmpty) return const SizedBox.shrink();
    final List<RecoverableItem> shown = soon.take(_shown).toList();
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          context.s('Leaving soon'),
          actionLabel: soon.length > _shown ? context.s('See all') : null,
          onAction: () => Navigator.of(context).push(
            CategoryPage.route(
              title: context.s('Expiring'),
              sourceIds: kAllSourceIds,
            ),
          ),
        ),
        SizedBox(
          height: 132 + GDesign.space8 + 20,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: GDesign.space12),
            itemBuilder: (BuildContext context, int i) => PhotoTile(
              image: ItemThumbnail(
                itemId: shown[i].itemId,
                bridge: bridge,
                maxPixels: 400,
              ),
              label: _leavesLabel(context, shown[i].expiresInDays!),
              heroTag: 'soon-${shown[i].itemId}',
              onTap: () => Navigator.of(context).push(
                MediaViewer.route(items: shown, index: i, heroPrefix: 'soon'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The message archive in the feed: what is kept, and the way in.
class _MessagesFeed extends ConsumerWidget {
  const _MessagesFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;
    if (capture == null) return const _LeadPlaceholder(visual: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _Category.messages.headline(context, capture.messageCount),
            style: g.headline(),
          ),
          const SizedBox(height: 2),
          Text(
            capture.capturing
                ? context.s('Kept from notifications as they arrive')
                : context.s('Capture is off'),
            style: g.footnote(),
          ),
          const SizedBox(height: GDesign.space16),
          PrimaryButton(
            label: context.s('Open messages'),
            onTap: () => Navigator.of(
              context,
            ).push(MessagesPage.route(backLabel: context.s('Recovery'))),
          ),
        ],
      ),
    );
  }
}

// ── States before there is a feed ────────────────────────────────────────

/// Shown while a full scan walks the phone: where it is, how far, and Stop.
class _ScanCard extends ConsumerWidget {
  const _ScanCard({required this.scan});

  final BackgroundScanState scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool sized = scan.total > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        0,
        GDesign.gutter,
        GDesign.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(context.s('Checking this phone'), style: g.headline()),
          const SizedBox(height: 2),
          Text(_progressLine(context, scan), style: g.figures(g.footnote())),
          const SizedBox(height: GDesign.space12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: sized ? (scan.scanned / scan.total).clamp(0.0, 1.0) : null,
              minHeight: 4,
              color: g.accent,
              backgroundColor: g.fill,
            ),
          ),
          const SizedBox(height: GDesign.space16),
          SecondaryButton(
            label: context.s('Stop'),
            onTap: () async {
              await ref.read(recoveryBridgeProvider).cancelScan();
              ref.invalidate(backgroundScanProvider);
            },
          ),
        ],
      ),
    );
  }

  /// Where the scan is, how far through it, and what it has found so far.
  static String _progressLine(BuildContext context, BackgroundScanState scan) {
    final String where = switch (scan.sourceId) {
      'media_trash' => context.s('Trash folders'),
      'app_trash' => context.s('App leftovers'),
      'thumbnails' => context.s('Thumbnail cache'),
      _ => context.s('Looking'),
    };
    final String found = context.s1('{} found', GFormat.count(scan.found));
    if (scan.total <= 0) return '$where, $found';
    return '$where ${GFormat.count(scan.scanned)} / '
        '${GFormat.count(scan.total)}, $found';
  }
}

/// The screen when there is no feed yet: one line and at most one action.
class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.mode});

  final _Mode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mode == _Mode.loading) return const _LeadPlaceholder(visual: true);
    final GDesignTheme g = GDesignTheme.of(context);

    final (String title, String? detail) = switch (mode) {
      _Mode.blind => (context.s('Turn on file access'), null),
      _Mode.empty => (
        context.s('Nothing in the trash'),
        context.s('A full scan looks further.'),
      ),
      _ => (context.s('Nothing waiting. Your trash is clear.'), null),
    };

    final Widget? action = switch (mode) {
      _Mode.blind => PrimaryButton(
        label: context.s('Turn on file access'),
        icon: GIcons.folderOpen,
        onTap: () async {
          await ref.read(recoveryBridgeProvider).requestAllFilesAccess();
          ref.invalidate(recoveryAccessProvider);
          ref.invalidate(prescanProvider);
        },
      ),
      _Mode.empty => PrimaryButton(
        label: context.s('Scan this phone'),
        icon: GIcons.scan,
        onTap: () async {
          await ref.read(recoveryBridgeProvider).startBackgroundScan();
          ref.invalidate(backgroundScanProvider);
        },
      ),
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: g.headline()),
          if (detail != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(detail, style: g.footnote()),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: GDesign.space16),
            action,
          ],
        ],
      ),
    );
  }
}

/// The lead's shape in the fill colour while its data loads, so nothing
/// jumps when the photo arrives.
class _LeadPlaceholder extends StatelessWidget {
  const _LeadPlaceholder({required this.visual});

  final bool visual;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    Widget bar(double width) => Container(
      width: width,
      height: 14,
      decoration: BoxDecoration(
        color: g.fill,
        borderRadius: BorderRadius.circular(7),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (visual) ...<Widget>[
            AspectRatio(
              aspectRatio: 320 / 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: g.fill,
                  borderRadius: BorderRadius.circular(GDesign.cardRadius),
                ),
              ),
            ),
            const SizedBox(height: GDesign.space12),
          ],
          bar(200),
          const SizedBox(height: GDesign.space8),
          bar(140),
        ],
      ),
    );
  }
}

/// The user's newest photos, for the empty scenes. Same scope as the
/// dashboard's, so the list is fetched once and shared.
const StorageScope _recentPhotos = StorageScope(
  title: 'Recent photos',
  kind: 'image',
  sort: GSortMode.newest,
);

/// An empty category: a small moving scene of what would be there, a title
/// and one line.
class _Empty extends ConsumerWidget {
  const _Empty({required this.category});

  final _Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    final List<StorageFile> recent =
        ref.watch(storageFilesProvider(_recentPhotos)).value?.files ??
        const <StorageFile>[];
    final List<ImageProvider> photos = <ImageProvider>[
      for (final StorageFile f in recent.take(4))
        FileThumbnail(fileId: f.fileId, bridge: bridge, maxPixels: 360),
    ];
    final (EmptyKind kind, String title, String body) = switch (category) {
      _Category.photos => (
        EmptyKind.photos,
        context.s('Nothing deleted'),
        context.s('Deleted photos land here'),
      ),
      _Category.video => (
        EmptyKind.video,
        context.s('No deleted videos'),
        context.s('Deleted videos land here'),
      ),
      _Category.statuses => (
        EmptyKind.statuses,
        context.s('No statuses yet'),
        context.s('Statuses you view land here'),
      ),
      _Category.docs => (
        EmptyKind.docs,
        context.s('No deleted documents'),
        context.s('Deleted documents land here'),
      ),
      _Category.audio => (
        EmptyKind.audio,
        context.s('No deleted audio'),
        context.s('Voice notes and music land here'),
      ),
      _Category.previews => (
        EmptyKind.previews,
        context.s('No previews left behind'),
        context.s('Small copies of lost photos land here'),
      ),
      _Category.messages => (
        EmptyKind.messages,
        context.s('No messages kept yet'),
        context.s('Turn on Keep deleted messages in More'),
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space16,
        GDesign.gutter,
        GDesign.space16,
      ),
      child: Reveal(
        child: Column(
          children: <Widget>[
            EmptyScene(kind: kind, photos: photos),
            const SizedBox(height: GDesign.space24),
            Text(title, style: g.headline(), textAlign: TextAlign.center),
            const SizedBox(height: GDesign.space4),
            Text(body, style: g.footnote(), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// One muted line in place of a feed.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        GDesign.space8,
      ),
      child: Text(text, style: g.body(color: g.muted)),
    );
  }
}

// ── Worth a look ─────────────────────────────────────────────────────────

// ── Copy helpers ─────────────────────────────────────────────────────────

/// "Deleted yesterday" for the chip over the lead photo. Null when the
/// source does not record a deletion date, so no chip is drawn.
String? _deletedLabel(BuildContext context, RecoverableItem item) {
  final int? millis = item.dateDeletedMillis;
  if (millis == null) return null;
  final DateTime when = DateTime.fromMillisecondsSinceEpoch(millis);
  final DateTime now = DateTime.now();
  final int days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(when.year, when.month, when.day)).inDays;
  if (days <= 0) return context.s('Deleted today');
  if (days == 1) return context.s('Deleted yesterday');
  return context.s1('Deleted {} days ago', days);
}

/// "Leaves in 3 days" under a tile.
String _leavesLabel(BuildContext context, int days) {
  if (days <= 0) return context.s('Leaves today');
  if (days == 1) return context.s('Leaves tomorrow');
  return context.s1('Leaves in {} days', days);
}

/// Total size, and when the first of them leaves the trash, measured from
/// the items themselves.
String _sizeLine(BuildContext context, List<RecoverableItem> items) {
  final int bytes = items.fold<int>(
    0,
    (int sum, RecoverableItem i) => sum + i.sizeBytes,
  );
  final Iterable<int> expiries = items
      .map((RecoverableItem i) => i.expiresInDays)
      .whereType<int>();
  final String size = GFormat.bytes(bytes);
  if (expiries.isEmpty) return size;
  final int soonest = expiries.reduce((int a, int b) => a < b ? a : b);
  return '$size, ${_leavesLabel(context, soonest).toLowerCase()}';
}

/// Size and deletion day for a file row.
String _fileLine(BuildContext context, RecoverableItem item) {
  final String size = GFormat.bytes(item.sizeBytes);
  final String? deleted = _deletedLabel(context, item);
  return deleted == null ? size : '$size, ${deleted.toLowerCase()}';
}
