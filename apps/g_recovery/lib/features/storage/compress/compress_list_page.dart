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
import 'compress_viewer_page.dart';

/// Screenshots or photos that can be re-saved smaller, as a photo grid.
///
/// Everything starts picked. Each tile carries its measured saving once the
/// encoder has really run on it; a tap leaves a file out, a long press opens
/// the before and after viewer. Photos get three quality stops instead of a
/// slider, because the difference between 82 and 84 is not a choice anyone
/// can see.
class CompressListPage extends ConsumerStatefulWidget {
  const CompressListPage({required this.kind, super.key});

  /// 'screenshot' (lossless) or 'photo' (lossy).
  final String kind;

  static Route<void> route(String kind) => MaterialPageRoute<void>(
    builder: (BuildContext context) => CompressListPage(kind: kind),
  );

  @override
  ConsumerState<CompressListPage> createState() => _CompressListPageState();
}

enum _Sort { largest, newest, oldest }

class _CompressListPageState extends ConsumerState<CompressListPage> {
  /// Files the user left out. Everything else is picked.
  final Set<String> _excluded = <String>{};

  /// Real encoder results, keyed by file, at the current quality.
  final Map<String, CompressPreview> _measured = <String, CompressPreview>{};

  /// Files queued for measuring, so a scroll does not ask twice.
  final Set<String> _inFlight = <String>{};

  bool _busy = false;
  _Sort _sort = _Sort.largest;

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

  /// Quality stops offered for photos.
  static const List<int> _stops = <int>[90, 85, 70];

  bool get _lossless => widget.kind == 'screenshot';

  int get _quality => _lossless ? 100 : ref.read(compressQualityProvider);

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    final AsyncValue<List<CompressCandidate>> source = ref.watch(
      compressScopeProvider(widget.kind),
    );
    final List<CompressCandidate> items = _sorted(
      source.value ?? const <CompressCandidate>[],
    );

    int saving = 0;
    int measured = 0;
    for (final CompressCandidate item in items) {
      if (_excluded.contains(item.fileId)) continue;
      final CompressPreview? p = _measured[item.fileId];
      if (p == null) continue;
      measured++;
      final int delta = p.originalBytes - p.newBytes;
      if (delta > 0) saving += delta;
    }
    final int picked = items.length - _excluded.length;
    final bool all = _excluded.isEmpty;
    final bool showBar = items.isNotEmpty && !_busy;

    return LargeTitlePage(
      onBack: () => Navigator.of(context).pop(),
      title: _lossless ? context.s('Screenshots') : context.s('Photos'),
      backLabel: context.s('Make smaller'),
      actions: <Widget>[
        if (items.isNotEmpty && !_busy)
          NavAction.icon(
            icon: GIcons.sort,
            semanticLabel: context.s('Sort'),
            onTap: _chooseSort,
          ),
      ],
      bottom: showBar
          ? ActionBar(
              leading: BarIconButton(
                icon: GIcons.checkCircle,
                semanticLabel: all
                    ? context.s('Select none')
                    : context.s('Select all'),
                onTap: () => setState(() {
                  if (all) {
                    _excluded.addAll(
                      items.map((CompressCandidate c) => c.fileId),
                    );
                  } else {
                    _excluded.clear();
                  }
                }),
              ),
              center: _Action(
                picked: picked,
                measured: measured,
                saving: saving,
                onTap: _run,
              ),
            )
          : null,
      bottomExtent: showBar ? ActionBar.extent(context) : 0,
      slivers: <Widget>[
        if (_busy)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: CompressRunning(),
          )
        else if (!source.hasValue)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (items.isEmpty)
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
                      context.s('Already as small as it gets'),
                      style: g.headline(),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...<Widget>[
          SliverToBoxAdapter(
            child: _Summary(
              saving: saving,
              measured: measured,
              picked: picked,
              lossless: _lossless,
            ),
          ),
          if (!_lossless)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  0,
                  GDesign.gutter,
                  GDesign.space16,
                ),
                child: Segmented<int>(
                  semanticLabel: context.s('Quality'),
                  segments: <(int, String)>[
                    (_stops[0], context.s('Best look')),
                    (_stops[1], context.s('Balanced')),
                    (_stops[2], context.s('Smallest')),
                  ],
                  value: _nearestStop(ref.watch(compressQualityProvider)),
                  onChanged: (int q) => _setQuality(q, items),
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
              itemCount: items.length,
              itemBuilder: (BuildContext context, int i) {
                _measureFrom(items, i);
                final CompressCandidate item = items[i];
                return PhotoGridTile(
                  image: FileThumbnail(fileId: item.fileId, bridge: bridge),
                  selected: !_excluded.contains(item.fileId),
                  badge: _SavingChip(preview: _measured[item.fileId]),
                  onTap: () => _toggle(item.fileId),
                  onLongPress: () => _open(items, i),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space24)),
        ],
      ],
    );
  }

  /// Snaps a stored quality to the closest offered stop.
  static int _nearestStop(int q) =>
      _stops.reduce((int a, int b) => (q - a).abs() <= (q - b).abs() ? a : b);

  void _setQuality(int q, List<CompressCandidate> items) {
    ref.read(compressQualityProvider.notifier).select(q);
    setState(() {
      _measured.clear();
      _inFlight.clear();
    });
    // "No gain" verdicts were reached at the old quality.
    ref.read(compressBridgeProvider).clearNoGain().then((_) {
      if (mounted) ref.invalidate(compressScopeProvider(widget.kind));
    });
    _measureFrom(items, 0);
  }

  void _toggle(String fileId) => setState(() {
    if (!_excluded.remove(fileId)) _excluded.add(fileId);
  });

  void _open(List<CompressCandidate> items, int index) {
    Haptics.select();
    Navigator.of(context, rootNavigator: true).push(
      CompressViewerPage.route(
        fileIds: items.map((CompressCandidate c) => c.fileId).toList(),
        index: index,
        quality: _quality,
        lossless: _lossless,
        excluded: _excluded,
        onExclude: _toggle,
      ),
    );
  }

  Future<void> _chooseSort() async {
    final _Sort? picked = await presentSheet<_Sort>(
      context: context,
      builder: (BuildContext sheet) => Padding(
        padding: const EdgeInsets.only(
          top: GDesign.space8,
          bottom: GDesign.space24,
        ),
        child: GroupedSection(
          header: sheet.s('Sort by'),
          children: <Widget>[
            for (final (_Sort, String) o in <(_Sort, String)>[
              (_Sort.largest, sheet.s('Largest first')),
              (_Sort.newest, sheet.s('Newest first')),
              (_Sort.oldest, sheet.s('Oldest first')),
            ])
              ListRow(
                title: o.$2,
                trailing: o.$1 == _sort
                    ? Icon(
                        GIcons.check,
                        size: 20,
                        color: GDesignTheme.of(sheet).accentText,
                      )
                    : const SizedBox.shrink(),
                onTap: () => Navigator.of(sheet).pop(o.$1),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  /// Queues the next dozen unmeasured files from [index] on.
  void _measureFrom(List<CompressCandidate> items, int index) {
    final List<String> wanted = <String>[];
    for (int i = index; i < items.length && wanted.length < 12; i++) {
      final String id = items[i].fileId;
      if (_excluded.contains(id)) continue;
      if (_measured.containsKey(id) || _inFlight.contains(id)) continue;
      wanted.add(id);
    }
    if (wanted.isEmpty) return;
    _inFlight.addAll(wanted);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure(wanted));
  }

  Future<void> _measure(List<String> ids) async {
    final int quality = _quality;
    final List<CompressPreview> results = await ref
        .read(compressBridgeProvider)
        .preview(ids, quality: quality);
    // Drop results that arrived after the quality changed.
    if (!mounted || quality != _quality) return;
    setState(() {
      _inFlight.removeAll(ids);
      for (final CompressPreview p in results) {
        _measured[p.fileId] = p;
      }
    });
  }

  Future<void> _run() async {
    final List<CompressCandidate> all =
        ref.read(compressScopeProvider(widget.kind)).value ??
        const <CompressCandidate>[];
    final List<String> worth = <String>[];
    final List<String> pointless = <String>[];
    for (final CompressCandidate c in all) {
      if (_excluded.contains(c.fileId)) continue;
      final CompressPreview? p = _measured[c.fileId];
      if (p == null) continue;
      (p.newBytes < p.originalBytes ? worth : pointless).add(c.fileId);
    }

    final CompressBridge compress = ref.read(compressBridgeProvider);
    // Remember files that would not shrink, so they stop being offered.
    if (pointless.isNotEmpty) await compress.markNoGain(pointless);
    if (worth.isEmpty) {
      if (mounted) {
        ref.invalidate(compressScopeProvider(widget.kind));
        ref.invalidate(compressSummaryProvider);
      }
      return;
    }

    setState(() => _busy = true);
    final List<CompressOutcome> outcomes = await compress.compress(
      worth,
      quality: _quality,
    );
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
      _measured.clear();
    });
    ref
      ..invalidate(compressScopeProvider(widget.kind))
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

  List<CompressCandidate> _sorted(List<CompressCandidate> items) {
    final List<CompressCandidate> out = List<CompressCandidate>.of(items);
    out.sort(
      (CompressCandidate a, CompressCandidate b) => switch (_sort) {
        _Sort.largest => b.sizeBytes.compareTo(a.sizeBytes),
        _Sort.newest => (b.dateMillis ?? 0).compareTo(a.dateMillis ?? 0),
        _Sort.oldest => (a.dateMillis ?? 0).compareTo(b.dateMillis ?? 0),
      },
    );
    return out;
  }
}

/// The running total of what the picked files would free.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.saving,
    required this.measured,
    required this.picked,
    required this.lossless,
  });

  final int saving;
  final int measured;
  final int picked;
  final bool lossless;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool done = measured >= picked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        GDesign.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (saving == 0)
            Text(
              done ? context.s('Nothing to gain') : context.s('Measuring'),
              style: g.largeTitle(),
            )
          else
            CountUpText(
              value: saving,
              format: (num v) =>
                  context.s1('{} to free', GFormat.bytes(v.round())),
              style: g.figures(g.largeTitle()),
            ),
          const SizedBox(height: 2),
          Text(
            done
                ? (lossless
                      ? context.s('Every pixel kept')
                      : context.s('Measured on your files'))
                : context.s1(
                    'Measuring, {} to go',
                    GFormat.count(picked - measured),
                  ),
            style: g.figures(g.footnote()),
          ),
        ],
      ),
    );
  }
}

/// A tile's measured saving, as a glass chip in the corner.
class _SavingChip extends StatelessWidget {
  const _SavingChip({required this.preview});

  final CompressPreview? preview;

  @override
  Widget build(BuildContext context) {
    final CompressPreview? p = preview;
    final int delta = p == null ? 0 : p.originalBytes - p.newBytes;
    return AnimatedSwitcher(
      duration: GDesign.motion(context, GDesign.normal),
      child: p == null
          ? const SizedBox.shrink()
          : PhotoChip(
              key: ValueKey<int>(delta),
              delta > 0 ? '-${GFormat.bytes(delta)}' : context.s('No gain'),
            ),
    );
  }
}

/// The main action, counting up as measurements arrive.
class _Action extends StatefulWidget {
  const _Action({
    required this.picked,
    required this.measured,
    required this.saving,
    required this.onTap,
  });

  final int picked;

  /// Picked files measured so far.
  final int measured;
  final int saving;
  final VoidCallback onTap;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> {
  /// The value the label last settled on, so it counts from there.
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.picked == 0) {
      _shown = 0;
      return PrimaryButton(label: context.s('Tap photos to pick'), onTap: null);
    }
    if (widget.saving == 0) {
      final bool measuring = widget.measured < widget.picked;
      return PrimaryButton(
        label: measuring
            ? context.s('Measuring')
            : context.s('Nothing to gain'),
        busy: measuring,
        onTap: null,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: _shown.toDouble(),
        end: widget.saving.toDouble(),
      ),
      duration: GDesign.motion(context, GDesign.slow),
      curve: GDesign.enter,
      onEnd: () => _shown = widget.saving,
      builder: (BuildContext context, double v, Widget? _) => PrimaryButton(
        label: context.s1('Make smaller, free {}', GFormat.bytes(v.round())),
        onTap: widget.onTap,
      ),
    );
  }
}
