import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/compare_api.g.dart';
import '../../bridge/compare_bridge.dart';
import '../../bridge/compress_api.g.dart';
import '../../bridge/compress_bridge.dart';
import '../../bridge/messages_api.g.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/recovery_bridge.dart';
import '../../bridge/server_api.g.dart';
import '../../bridge/server_bridge.dart';
import '../../bridge/storage_api.g.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/file_thumbnail.dart';
import '../../ui/g_sort.dart';
import '../../ui/g_thumbnail.dart';
import '../device/benchmark/benchmark_card.dart';
import '../device/state/device_providers.dart';
import '../device/tools/screen_test_page.dart';
import '../device/tools/sound_test_page.dart';
import '../messages/messages_page.dart';
import '../messages/state/messages_providers.dart';
import '../more/settings_pages.dart';
import '../recovery/category_page.dart';
import '../recovery/state/recovery_providers.dart';
import '../search/search_page.dart';
import '../server/server_page.dart';
import '../storage/compare/compare_review_page.dart';
import '../storage/compress/compress_page.dart';
import '../storage/state/storage_files.dart';
import '../storage/state/storage_providers.dart';
import '../viewer/media_viewer.dart';
import 'home_page.dart';
import 'widgets/vpn_row.dart';

/// The newest photos on the phone, the art for the protection card.
const StorageScope _recent = StorageScope(
  title: 'Recent photos',
  kind: 'image',
  sort: GSortMode.newest,
);

const RecoveryQuery _deletedPhotos = RecoveryQuery(
  sourceIds: kAllSourceIds,
  kind: 'image',
);
const RecoveryQuery _deletedVideo = RecoveryQuery(
  sourceIds: kAllSourceIds,
  kind: 'video',
);
const RecoveryQuery _statuses = RecoveryQuery(
  sourceIds: <String>['app_trash'],
  roles: <String>{kRoleStatus},
);
const RecoveryQuery _everything = RecoveryQuery(sourceIds: kAllSourceIds);
const RecoveryQuery _docs = RecoveryQuery(
  sourceIds: kAllSourceIds,
  kind: 'document',
);
const RecoveryQuery _audio = RecoveryQuery(
  sourceIds: kAllSourceIds,
  kind: 'audio',
);
const RecoveryQuery _previews = RecoveryQuery(
  sourceIds: <String>['thumbnails'],
  roles: <String>{kRoleCache},
);

/// Home as a daily dashboard: is the phone protected, how it is doing, what
/// can come back, and the tools. Something is always here, even on a phone
/// where nothing has been deleted. Every figure is measured on the phone.
class HomeDashboard extends ConsumerWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LargeTitlePage(
      title: context.s('Recovery'),
      grouped: true,
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.search,
          semanticLabel: context.s('Search files, photos, messages'),
          onTap: () => Navigator.of(context).push(SearchPage.route()),
        ),
      ],
      onRefresh: () async {
        ref.invalidate(prescanProvider);
        ref.invalidate(recoveryItemsProvider);
        ref.invalidate(storageOverviewProvider);
        ref.invalidate(deviceSnapshotProvider);
        await ref.read(prescanProvider.future);
      },
      slivers: const <Widget>[
        SliverToBoxAdapter(child: Reveal(child: _Protection())),
        SliverToBoxAdapter(child: Reveal(index: 1, child: _Rings())),
        SliverToBoxAdapter(child: Reveal(index: 2, child: BenchmarkCard())),
        SliverToBoxAdapter(child: Reveal(index: 3, child: _CanComeBack())),
        SliverToBoxAdapter(child: Reveal(index: 4, child: _Tools())),
        SliverToBoxAdapter(child: VpnRow()),
        SliverToBoxAdapter(child: SizedBox(height: GDesign.space32)),
      ],
    );
  }
}

/// A section title in the dashboard's larger style, with an optional link.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space32,
        GDesign.gutter,
        GDesign.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(child: Text(text, style: g.title2())),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: GDesign.touch,
                  minWidth: GDesign.touch,
                ),
                child: Center(
                  child: Text(
                    action!,
                    style: g
                        .footnote(color: g.text, weight: FontWeight.w600)
                        .copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Protection ───────────────────────────────────────────────────────────

/// The lead card: one of the user's photos, blurred, as the ground; three
/// recent photos fanned on it; whether the phone is protected and what can
/// come back.
class _Protection extends ConsumerWidget {
  const _Protection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecoveryAccess? access = ref.watch(recoveryAccessProvider).value;
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;
    // The live list, not the cached scan summary, so the headline always
    // matches what the chips below can open.
    final int back =
        ref.watch(recoveryItemsProvider(_everything)).value?.length ?? 0;
    final List<StorageFile> recent =
        ref.watch(storageFilesProvider(_recent)).value?.files ??
        const <StorageFile>[];
    final List<ImageProvider> photos = <ImageProvider>[
      for (final StorageFile f in recent.take(3))
        FileThumbnail(
          fileId: f.fileId,
          bridge: ref.watch(storageBridgeProvider),
          maxPixels: 360,
        ),
    ];

    final int off = <bool>[
      access?.allFilesAccess ?? false,
      capture?.listenerEnabled ?? false,
    ].where((bool on) => !on).length;

    final String chip = off == 0
        ? context.s('Protected')
        : off == 1
        ? context.s('1 switch off')
        : context.s('2 switches off');
    final String headline = back == 0
        ? context.s('Nothing to bring back')
        : back == 1
        ? context.s('1 file can come back')
        : context.s1('{} files can come back', GFormat.count(back));
    final String line = off == 0
        ? context.s('Watching trash, chats and statuses')
        : context.s('Tap to turn protection on');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        0,
      ),
      child: Pressable(
        scale: 0.98,
        onTap: () => Navigator.of(
          context,
        ).push(off > 0 ? PermissionsPage.route() : HomePage.route()),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 196,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (photos.isNotEmpty)
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Transform.scale(
                      scale: 1.3,
                      child: SizedPhoto(image: photos.first),
                    ),
                  )
                else
                  ColoredBox(color: GDesignTheme.of(context).card),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0x0D000000), Color(0x8C000000)],
                    ),
                  ),
                ),
                if (photos.isNotEmpty)
                  PositionedDirectional(
                    end: 8,
                    top: 8,
                    width: 150,
                    height: 120,
                    child: _Fan(photos: photos),
                  ),
                PositionedDirectional(
                  start: GDesign.space16,
                  top: GDesign.space16,
                  child: PhotoChip(
                    chip,
                    icon: off == 0 ? GIcons.shieldCheck : GIcons.shield,
                  ),
                ),
                PositionedDirectional(
                  start: GDesign.space16,
                  end: GDesign.space16,
                  bottom: GDesign.space16,
                  child: _OnPhoto(headline: headline, line: line),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White text over the photo, which stays white in both themes.
class _OnPhoto extends StatelessWidget {
  const _OnPhoto({required this.headline, required this.line});

  final String headline;
  final String line;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(headline, style: g.title2(color: g.onAccent)),
        const SizedBox(height: 2),
        Text(
          line,
          style: g.footnote(color: g.onAccent.withValues(alpha: 0.85)),
        ),
      ],
    );
  }
}

/// Up to three photos fanned like prints, drifting slowly.
class _Fan extends StatefulWidget {
  const _Fan({required this.photos});

  final List<ImageProvider> photos;

  @override
  State<_Fan> createState() => _FanState();
}

class _FanState extends State<_Fan> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
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

  static const List<(double, double, double)> _place =
      <(double, double, double)>[(8, 14, -0.14), (36, 4, 0.06), (62, 18, 0.2)];

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return AnimatedBuilder(
      animation: _drift,
      builder: (BuildContext context, _) {
        final double t = _drift.value * 2 * math.pi;
        return Stack(
          children: <Widget>[
            for (int i = 0; i < widget.photos.length; i++)
              Positioned(
                left: _place[i].$1,
                top: _place[i].$2 + 3 * math.sin(t + i * 1.7),
                child: Transform.rotate(
                  angle: _place[i].$3 + 0.03 * math.sin(t + i),
                  child: Container(
                    width: 72,
                    height: 92,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: g.onAccent, width: 2),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: g.shadow,
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SizedPhoto(image: widget.photos[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Rings ────────────────────────────────────────────────────────────────

/// Storage used, battery, and protection, as rings that fill on arrival.
/// Each opens where that figure lives.
class _Rings extends ConsumerWidget {
  const _Rings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final StorageOverview? overview = ref.watch(storageOverviewProvider).value;
    final BatterySnapshot? battery = ref
        .watch(deviceSnapshotProvider)
        .value
        ?.battery;
    final RecoveryAccess? access = ref.watch(recoveryAccessProvider).value;
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;

    final int total = overview?.volume.totalBytes ?? 0;
    final double used = total <= 0 ? 0 : overview!.volume.usedBytes / total;
    final int? health = battery?.stateOfHealthPercent;
    final int? charge = battery?.percent;
    final double protection =
        <bool>[
          access?.allFilesAccess ?? false,
          capture?.listenerEnabled ?? false,
        ].where((bool on) => on).length /
        2;

    void tab(int i) => ref.read(gShellTabProvider.notifier).select(i);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space16,
        GDesign.gutter,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: g.card,
          borderRadius: BorderRadius.circular(GDesign.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: GDesign.space16,
            horizontal: GDesign.space8,
          ),
          child: Row(
            children: <Widget>[
              _Ring(
                fraction: used,
                value: '${(used * 100).round()}%',
                label: context.s('Storage used'),
                onTap: () => tab(1),
              ),
              _Ring(
                fraction: (health ?? charge ?? 0) / 100,
                value: health != null || charge != null
                    ? '${health ?? charge}%'
                    : '-',
                label: health != null
                    ? context.s('Battery health')
                    : context.s('Battery'),
                onTap: () => tab(2),
              ),
              _Ring(
                fraction: protection,
                value: '${(protection * 100).round()}%',
                label: context.s('Protection'),
                onTap: () =>
                    Navigator.of(context).push(PermissionsPage.route()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.fraction,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final double fraction;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Expanded(
      child: Pressable(
        onTap: onTap,
        semanticLabel: '$label, $value',
        child: Column(
          children: <Widget>[
            SizedBox.square(
              dimension: 76,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: fraction.clamp(0, 1)),
                duration: GDesign.motion(
                  context,
                  const Duration(milliseconds: 1100),
                ),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double f, Widget? child) =>
                    CustomPaint(
                      painter: _Arc(
                        fraction: f,
                        track: g.text.withValues(alpha: 0.1),
                        fill: g.accent,
                      ),
                      child: child,
                    ),
                child: Center(
                  child: Text(value, style: g.figures(g.headline())),
                ),
              ),
            ),
            const SizedBox(height: GDesign.space8),
            Text(label, style: g.footnote(), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Arc extends CustomPainter {
  const _Arc({required this.fraction, required this.track, required this.fill});

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = (Offset.zero & size).deflate(4);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(box, 0, 2 * math.pi, false, p..color = track);
    if (fraction > 0.005) {
      canvas.drawArc(
        box,
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        p..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_Arc old) => old.fraction != fraction || old.fill != fill;
}

// ── Can come back ────────────────────────────────────────────────────────

/// What can be recovered: a chip per kind with its count, and the deleted
/// photos themselves. With nothing deleted, a quiet line instead.
class _CanComeBack extends ConsumerWidget {
  const _CanComeBack();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<RecoverableItem> photos =
        ref.watch(recoveryItemsProvider(_deletedPhotos)).value ??
        const <RecoverableItem>[];
    final int videos =
        ref.watch(recoveryItemsProvider(_deletedVideo)).value?.length ?? 0;
    final int statuses =
        ref.watch(recoveryItemsProvider(_statuses)).value?.length ?? 0;
    final int messages =
        ref.watch(messageCaptureProvider).value?.messageCount ?? 0;
    int count(RecoveryQuery q) =>
        ref.watch(recoveryItemsProvider(q)).value?.length ?? 0;
    final int docs = count(_docs);
    final int audio = count(_audio);
    final int previews = count(_previews);
    final int everything = count(_everything);
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);

    void browse(int category) =>
        Navigator.of(context).push(HomePage.route(category: category));

    final List<Widget> chips = <Widget>[
      // Everything deleted, whatever its kind, so the count always matches
      // the card above even for files no category claims.
      if (everything > 0)
        _Chip(
          GIcons.list,
          context.s('All'),
          everything,
          () => Navigator.of(context).push(
            CategoryPage.route(
              title: context.s('Everything deleted'),
              backLabel: context.s('Recovery'),
            ),
          ),
        ),
      if (photos.isNotEmpty)
        _Chip(
          GIcons.photos,
          context.s('Photos'),
          photos.length,
          () => browse(0),
        ),
      if (videos > 0)
        _Chip(GIcons.video, context.s('Video'), videos, () => browse(1)),
      if (statuses > 0)
        _Chip(GIcons.status, context.s('Statuses'), statuses, () => browse(2)),
      if (messages > 0)
        _Chip(
          GIcons.messages,
          context.s('Messages'),
          messages,
          () => Navigator.of(
            context,
          ).push(MessagesPage.route(backLabel: context.s('Recovery'))),
        ),
      if (docs > 0)
        _Chip(GIcons.docs, context.s('Docs'), docs, () => browse(4)),
      if (audio > 0)
        _Chip(GIcons.audio, context.s('Audio'), audio, () => browse(5)),
      if (previews > 0)
        _Chip(
          GIcons.previews,
          context.s('Previews'),
          previews,
          () => browse(6),
        ),
    ];
    // See all opens the first kind that has something in it.
    final int first = <(int, int)>[
      (photos.length, 0),
      (videos, 1),
      (statuses, 2),
      (messages, 3),
      (docs, 4),
      (audio, 5),
      (previews, 6),
    ].firstWhere(((int, int) c) => c.$1 > 0, orElse: () => (0, 0)).$2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Heading(
          context.s('Can come back'),
          action: context.s('See all'),
          onAction: () => browse(first),
        ),
        if (chips.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            child: Text(
              context.s('Nothing deleted right now.'),
              style: g.body(color: g.muted),
            ),
          )
        else ...<Widget>[
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: GDesign.space8),
              itemBuilder: (_, int i) => chips[i],
            ),
          ),
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GDesign.gutter,
                GDesign.space12,
                GDesign.gutter,
                0,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(GDesign.cardRadius),
                child: SizedBox(
                  height: 108,
                  child: Row(
                    children: <Widget>[
                      for (
                        int i = 0;
                        i < math.min(4, photos.length);
                        i++
                      ) ...<Widget>[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          child: Pressable(
                            scale: 0.97,
                            onTap: () => Navigator.of(context).push(
                              MediaViewer.route(
                                items: photos,
                                index: i,
                                heroPrefix: 'dash',
                              ),
                            ),
                            child: PhotoHero(
                              tag: 'dash-${photos[i].itemId}',
                              child: SizedPhoto(
                                image: ItemThumbnail(
                                  itemId: photos[i].itemId,
                                  bridge: bridge,
                                  maxPixels: 360,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label, this.count, this.onTap);

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GDesign.space12),
        decoration: BoxDecoration(
          color: g.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: g.muted),
            const SizedBox(width: 6),
            Text(label, style: g.body()),
            const SizedBox(width: 6),
            Text(
              GFormat.count(count),
              style: g.figures(g.body(color: g.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tools ────────────────────────────────────────────────────────────────

/// Every tool that works today, as tiles with one measured line each.
class _Tools extends ConsumerWidget {
  const _Tools();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompressSummary? compress = ref.watch(compressSummaryProvider).value;
    final List<CompareGroup> similar = ref.watch(similarGroupsProvider);
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;
    final ServerConfig? server = ref.watch(serverConfigProvider).value;
    final TransferState? transfer = ref.watch(transferProvider).value;

    final int shrink = compress == null
        ? 0
        : compress.screenshotBytes +
              compress.photoBytes +
              (compress.videoBytes ?? 0);
    final int? lastRun = transfer?.lastRunMillis;
    NavigatorState nav() => Navigator.of(context);

    final List<Widget> tiles = <Widget>[
      _Tool(
        icon: GIcons.archive,
        label: context.s('Make smaller'),
        detail: shrink > 0
            ? context.s1('{} to shrink', GFormat.bytes(shrink))
            : context.s('Photos and video'),
        onTap: () =>
            nav().push(CompressPage.route(backLabel: context.s('Home'))),
      ),
      _Tool(
        icon: GIcons.copy,
        label: context.s('Similar photos'),
        detail: similar.isEmpty
            ? context.s('Find near copies')
            : context.s1('{} sets', GFormat.count(similar.length)),
        onTap: () => nav().push(CompareReviewPage.route('similar')),
      ),
      _Tool(
        icon: GIcons.messages,
        label: context.s('Message archive'),
        detail: (capture?.capturing ?? false)
            ? context.s1('{} kept', GFormat.count(capture!.messageCount))
            : context.s('Off'),
        onTap: () =>
            nav().push(MessagesPage.route(backLabel: context.s('Recovery'))),
      ),
      _Tool(
        icon: GIcons.server,
        label: context.s('Home server'),
        detail: server == null
            ? context.s('Not set up')
            : lastRun == null
            ? context.s('Ready')
            : context.s1(
                'Backed up {}',
                GFormat.relativeDay(
                  DateTime.fromMillisecondsSinceEpoch(lastRun),
                  DateTime.now(),
                ),
              ),
        onTap: () => nav().push(ServerPage.route()),
      ),
      _Tool(
        icon: GIcons.monitor,
        label: context.s('Screen test'),
        detail: context.s('Dead pixels'),
        onTap: () => nav().push(ScreenTestPage.route()),
      ),
      _Tool(
        icon: GIcons.volume,
        label: context.s('Speaker test'),
        detail: context.s('Each speaker'),
        onTap: () => nav().push(SoundTestPage.route()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Heading(context.s('Tools')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: GDesign.space12,
            crossAxisSpacing: GDesign.space12,
            childAspectRatio: 1.35,
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++)
                Reveal(index: i, child: tiles[i]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      semanticLabel: '$label, $detail',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: g.card,
          borderRadius: BorderRadius.circular(GDesign.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: g.isDark ? g.hairline : g.fill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: g.accentText),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: g.body(weight: FontWeight.w600),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: g.footnote(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
