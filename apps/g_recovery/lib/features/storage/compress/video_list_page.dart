import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../app/shell.dart';
import '../../../bridge/compress_api.g.dart';
import '../../../bridge/compress_bridge.dart';
import '../../../bridge/storage_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../../core/messenger/g_message.dart';
import '../../../core/messenger/g_messenger.dart';
import '../../../ui/file_thumbnail.dart';
import '../state/storage_providers.dart';
import 'compress_running.dart';
import 'video_preview_page.dart';

/// Clips stored in an older codec or at a higher bitrate than they need.
///
/// Each clip's saving is estimated by really encoding a 15 second sample,
/// one clip at a time, so the grid fills in as the encoder works. A tap
/// leaves a clip out; a long press plays the sample next to the original.
/// Free, like screenshots and photos.
class VideoListPage extends ConsumerStatefulWidget {
  const VideoListPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const VideoListPage(),
  );

  @override
  ConsumerState<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends ConsumerState<VideoListPage> {
  final Set<String> _excluded = <String>{};
  final Map<String, VideoEstimate> _estimates = <String, VideoEstimate>{};

  /// Clips waiting for a sample encode. One runs at a time: the hardware
  /// encoder is a single resource.
  final List<String> _queue = <String>[];
  String? _working;

  /// 'same' keeps the look on a newer codec; 'smaller' also lowers bitrate.
  String _preset = 'same';
  bool _busy = false;

  /// Hides the tab bar so the action bar owns the bottom edge.
  late final GShellNav _nav = ref.read(gShellNavHiddenProvider.notifier);

  @override
  void initState() {
    super.initState();
    _nav.hide();
  }

  @override
  void dispose() {
    _nav.show();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    final AsyncValue<List<VideoCandidate>> source = ref.watch(
      videoCandidatesProvider,
    );
    final List<VideoCandidate> all = source.value ?? const <VideoCandidate>[];
    final List<VideoCandidate> usable = all
        .where((VideoCandidate c) => c.eligible)
        .toList();
    final List<VideoCandidate> refused = all
        .where((VideoCandidate c) => !c.eligible)
        .toList();

    int saving = 0;
    int estimated = 0;
    for (final VideoCandidate clip in usable) {
      if (_excluded.contains(clip.fileId)) continue;
      final VideoEstimate? e = _estimates[clip.fileId];
      if (e == null) continue;
      estimated++;
      final int delta = e.originalBytes - e.estimatedBytes;
      if (delta > 0) saving += delta;
    }
    final int picked = usable.length - _excluded.length;
    final bool all0 = _excluded.isEmpty;
    final bool showBar = usable.isNotEmpty && !_busy;

    return LargeTitlePage(
      onBack: () => Navigator.of(context).pop(),
      title: context.s('Video'),
      backLabel: context.s('Make smaller'),
      bottom: showBar
          ? ActionBar(
              leading: BarIconButton(
                icon: GIcons.checkCircle,
                semanticLabel: all0
                    ? context.s('Select none')
                    : context.s('Select all'),
                onTap: () => setState(() {
                  if (all0) {
                    _excluded.addAll(
                      usable.map((VideoCandidate c) => c.fileId),
                    );
                  } else {
                    _excluded.clear();
                  }
                }),
              ),
              center: PrimaryButton(
                label: picked == 0
                    ? context.s('Tap clips to pick')
                    : saving > 0
                    ? context.s1(
                        'Make smaller, free about {}',
                        GFormat.bytes(saving),
                      )
                    : estimated < picked
                    ? context.s('Measuring')
                    : context.s('Nothing to gain'),
                busy: picked > 0 && saving == 0 && estimated < picked,
                onTap: picked == 0 || saving == 0 ? null : _run,
              ),
            )
          : null,
      bottomExtent: showBar ? ActionBar.extent(context) : 0,
      slivers: <Widget>[
        if (_busy)
          SliverFillRemaining(
            hasScrollBody: false,
            child: CompressRunning(
              note: context.s('You can leave the app. This keeps going.'),
            ),
          )
        else if (!source.hasValue)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (usable.isEmpty && refused.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Reveal(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(GIcons.video, size: 40, color: g.faint),
                    const SizedBox(height: GDesign.space12),
                    Text(
                      context.s('Already as small as it gets'),
                      style: g.headline(),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...<Widget>[
          if (usable.isNotEmpty) ...<Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  GDesign.space8,
                  GDesign.gutter,
                  GDesign.space16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (saving == 0)
                      Text(
                        estimated < picked
                            ? context.s('Sampling your clips')
                            : context.s('Nothing to gain'),
                        style: g.largeTitle(),
                      )
                    else
                      CountUpText(
                        value: saving,
                        format: (num v) => context.s1(
                          'About {} to free',
                          GFormat.bytes(v.round()),
                        ),
                        style: g.figures(g.largeTitle()),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      estimated >= picked
                          ? (saving == 0 && _preset == 'same'
                                ? context.s('Try Smaller for a real saving')
                                : context.s(
                                    'From a 15 second sample of each clip',
                                  ))
                          : context.s1(
                              'Sampling, {} to go',
                              GFormat.count(picked - estimated),
                            ),
                      style: g.figures(g.footnote()),
                    ),
                    const SizedBox(height: GDesign.space16),
                    Segmented<String>(
                      semanticLabel: context.s('Quality'),
                      segments: <(String, String)>[
                        ('same', context.s('Same look')),
                        ('smaller', context.s('Smaller')),
                      ],
                      value: _preset,
                      onChanged: _setPreset,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: usable.length,
                itemBuilder: (BuildContext context, int i) {
                  final VideoCandidate clip = usable[i];
                  _want(clip.fileId);
                  return PhotoGridTile(
                    image: FileThumbnail(
                      fileId: clip.fileId,
                      bridge: bridge,
                      kind: 'video',
                    ),
                    selected: !_excluded.contains(clip.fileId),
                    badge: _ClipChip(
                      clip: clip,
                      estimate: _estimates[clip.fileId],
                      working: _working == clip.fileId,
                    ),
                    onTap: () => _toggle(clip.fileId),
                    onLongPress: () => _open(clip),
                  );
                },
              ),
            ),
          ],
          if (refused.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: GDesign.space32),
                child: GroupedSection(
                  header: context.s('Left alone'),
                  children: <Widget>[
                    for (final VideoCandidate clip in refused)
                      ListRow(
                        icon: GIcons.video,
                        title: clip.name,
                        subtitle: clip.reason ?? context.s('Already efficient'),
                        detail: GFormat.bytes(clip.sizeBytes),
                      ),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space24)),
        ],
      ],
    );
  }

  void _setPreset(String preset) => setState(() {
    _preset = preset;
    _estimates.clear();
    _queue.clear();
    _working = null;
  });

  void _toggle(String fileId) => setState(() {
    if (!_excluded.remove(fileId)) _excluded.add(fileId);
  });

  void _open(VideoCandidate clip) {
    final VideoEstimate? estimate = _estimates[clip.fileId];
    if (estimate == null || estimate.samplePath == null) return;
    Haptics.select();
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(VideoPreviewPage.route(clip: clip, estimate: estimate));
  }

  /// Queues a clip for a sample encode the first time its tile is built.
  void _want(String fileId) {
    if (_estimates.containsKey(fileId)) return;
    if (_queue.contains(fileId) || _working == fileId) return;
    _queue.add(fileId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  Future<void> _drain() async {
    if (_working != null || _queue.isEmpty || !mounted) return;
    final String fileId = _queue.removeAt(0);
    final String preset = _preset;
    setState(() => _working = fileId);

    final VideoEstimate? estimate = await ref
        .read(compressBridgeProvider)
        .estimateVideo(fileId, preset: preset);
    if (!mounted) return;
    // A preset change mid-encode makes this result stale.
    if (preset != _preset) {
      setState(() => _working = null);
      return _drain();
    }
    setState(() {
      _working = null;
      if (estimate != null) {
        _estimates[fileId] = estimate;
      } else {
        // The encoder could not handle it, so it is not offered.
        _excluded.add(fileId);
      }
    });
    // Native now remembers a clip that cannot shrink, so the count on the
    // Make smaller card drops to the clips that really will.
    final bool noGain =
        estimate == null ||
        (preset == 'smaller' &&
            estimate.estimatedBytes >= estimate.originalBytes * 0.8);
    if (noGain) ref.invalidate(compressSummaryProvider);
    await _drain();
  }

  Future<void> _run() async {
    final List<VideoCandidate> all =
        ref.read(videoCandidatesProvider).value ?? const <VideoCandidate>[];
    final List<String> ids = <String>[
      for (final VideoCandidate c in all)
        if (c.eligible &&
            !_excluded.contains(c.fileId) &&
            (_estimates[c.fileId]?.estimatedBytes ?? c.sizeBytes) < c.sizeBytes)
          c.fileId,
    ];
    if (ids.isEmpty) return;

    setState(() => _busy = true);
    final List<CompressOutcome> outcomes = await ref
        .read(compressBridgeProvider)
        .compressVideo(ids, preset: _preset);
    if (!mounted) return;

    final int replaced = outcomes
        .where((CompressOutcome o) => o.status == 'replaced')
        .length;
    final int saved = outcomes.fold<int>(
      0,
      (int sum, CompressOutcome o) => sum + o.savedBytes,
    );

    setState(() {
      _busy = false;
      _excluded.clear();
      _estimates.clear();
    });
    ref
      ..invalidate(videoCandidatesProvider)
      ..invalidate(compressSummaryProvider)
      ..invalidate(compressHistoryProvider)
      ..invalidate(storageOverviewProvider);

    Haptics.confirm();
    GMessenger.show(
      context,
      GMessage.success(
        '${context.s1('{} made smaller', GFormat.count(replaced))}, '
        '${context.s1('{} freed', GFormat.bytes(saved))}',
      ),
    );
  }
}

/// A tile's corner chip: the length while waiting, "Sampling" while the
/// encoder runs on it, then the estimated saving.
class _ClipChip extends StatelessWidget {
  const _ClipChip({
    required this.clip,
    required this.estimate,
    required this.working,
  });

  final VideoCandidate clip;
  final VideoEstimate? estimate;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final VideoEstimate? e = estimate;
    final int delta = e == null ? 0 : e.originalBytes - e.estimatedBytes;
    final String label = working
        ? context.s('Sampling')
        : e == null
        ? _length(clip.durationMillis)
        : delta > 0
        ? '-${GFormat.bytes(delta)}'
        : context.s('No gain');
    return AnimatedSwitcher(
      duration: GDesign.motion(context, GDesign.normal),
      child: PhotoChip(
        label,
        key: ValueKey<String>(label),
        icon: e?.samplePath != null ? GIcons.video : null,
      ),
    );
  }

  static String _length(int millis) {
    final Duration d = Duration(milliseconds: millis);
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s'
        : '${d.inMinutes}:$s';
  }
}
