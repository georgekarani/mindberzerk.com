import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/hardware_api.g.dart';
import '../../bridge/hardware_bridge.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/recovery_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/g_thumbnail.dart';
import '../recovery/state/recovery_actions.dart';
import '../recovery/state/recovery_providers.dart';
import '../viewer/media_viewer.dart';
import 'state/review_providers.dart';

/// Opens the one-by-one review for [items]. Also the way a lone photo opens:
/// one picture on its own string rather than a grid of one.
void openHangingReview(
  BuildContext context,
  WidgetRef ref,
  List<RecoverableItem> items,
) {
  ref.read(reviewProvider.notifier).start(items);
  Navigator.of(context).push(ReviewPage.route());
}

/// Review, one photo at a time, hanging from a string.
///
/// The photo swings as the phone tilts. Restore lifts it away on its string;
/// Delete snaps the string and lets it fall. Nothing is changed on the phone
/// until Apply on the last screen: restores fly home and deletes turn to dust
/// only then, so Undo is always honest.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const ReviewPage(),
  );

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late final GShellNav _nav;
  late final HardwareBridge _hardware;
  final TiltSignal _tilt = TiltSignal();
  Timer? _poll;
  bool _moving = false;
  bool _applying = false;

  /// One key per photo, so each arrival is a fresh drop and the page can ask
  /// the photo on screen to lift or fall.
  final Map<String, GlobalKey<HangingPhotoState>> _photos =
      <String, GlobalKey<HangingPhotoState>>{};

  final GlobalKey _keepStrip = GlobalKey(debugLabel: 'keep');
  final GlobalKey _binStrip = GlobalKey(debugLabel: 'bin');

  @override
  void initState() {
    super.initState();
    _nav = ref.read(gShellNavHiddenProvider.notifier)..hide();
    _hardware = ref.read(hardwareBridgeProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenToTilt());
  }

  /// Reads the accelerometer about 30 times a second, on this screen only.
  Future<void> _listenToTilt() async {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    await _hardware.startSensors(const <String>['accelerometer']);
    if (!mounted) return;
    _poll = Timer.periodic(const Duration(milliseconds: 33), (_) async {
      final List<SensorReading> readings = await _hardware.sensorValues();
      if (!mounted) return;
      for (final SensorReading r in readings) {
        if (r.type == 'accelerometer' && r.values.length >= 2) {
          _tilt.add(r.values[0], r.values[1]);
        }
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _hardware.stopSensors();
    _tilt.dispose();
    _nav.show();
    super.dispose();
  }

  GlobalKey<HangingPhotoState> _keyFor(String itemId) =>
      _photos.putIfAbsent(itemId, GlobalKey<HangingPhotoState>.new);

  Future<void> _decide(ReviewSession session, ReviewVerdict verdict) async {
    final RecoverableItem? item = session.current;
    if (item == null || _moving) return;
    _moving = true;
    Haptics.select();
    final HangingPhotoState? photo = _photos[item.itemId]?.currentState;
    if (photo != null) {
      await (verdict == ReviewVerdict.keep ? photo.lift() : photo.release());
    }
    // A photo that comes back through Undo must drop in again, not appear
    // already gone.
    _photos.remove(item.itemId);
    if (!mounted) return;
    ref.read(reviewProvider.notifier).decide(verdict);
    _moving = false;
  }

  void _undo() {
    if (_moving) return;
    Haptics.select();
    ref.read(reviewProvider.notifier).undo();
  }

  /// Applies every verdict, then plays what happened: restores fly home,
  /// deletes turn to dust. Only confirmed items count.
  Future<void> _apply(ReviewSession session) async {
    setState(() => _applying = true);
    final List<String> keep = <String>[
      for (final RecoverableItem i in session.kept) i.itemId,
    ];
    final List<String> bin = <String>[
      for (final RecoverableItem i in session.binned) i.itemId,
    ];
    final RecoveryActionResult kept = keep.isEmpty
        ? const RecoveryActionResult(done: <String>{})
        : await runRecoveryAction(ref, keep, purge: false);
    final RecoveryActionResult gone = bin.isEmpty
        ? const RecoveryActionResult(done: <String>{})
        : await runRecoveryAction(ref, bin, purge: true);
    if (!mounted) return;

    if (kept.done.isNotEmpty) await Flight.home(context, _keepStrip);
    if (!mounted) return;
    if (gone.done.isNotEmpty) await Dust.scatter(context, _binStrip);
    if (!mounted) return;
    reportRecoveryProblem(context, kept.problem != null ? kept : gone);

    refreshRecovery(ref);
    ref.read(reviewProvider.notifier).end();
    Navigator.of(context).pop();
  }

  /// Leaving with verdicts staged asks first; nothing has been applied.
  Future<void> _leave(ReviewSession? session) async {
    if (session == null || session.reviewed == 0) {
      ref.read(reviewProvider.notifier).end();
      Navigator.of(context).pop();
      return;
    }
    final bool go = await showConfirmSheet(
      context: context,
      title: context.s('Leave without applying?'),
      message: context.s(
        'Nothing has been restored or deleted yet. Your choices here are '
        'dropped.',
      ),
      confirmLabel: context.s('Leave'),
      cancelLabel: context.s('Keep reviewing'),
      destructive: false,
    );
    if (!go || !mounted) return;
    ref.read(reviewProvider.notifier).end();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final ReviewSession? session = ref.watch(reviewProvider);
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    final RecoverableItem? item = session?.current;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _leave(session);
      },
      child: Material(
        color: g.ground,
        child: Padding(
          padding: EdgeInsets.only(
            top: inset.top,
            bottom: inset.bottom + GDesign.space16,
          ),
          child: Column(
            children: <Widget>[
              _TopBar(
                session: session,
                onBack: () => _leave(session),
                onUndo: (session?.index ?? 0) > 0 && !_applying ? _undo : null,
              ),
              Expanded(
                child: session == null
                    ? const SizedBox.shrink()
                    : session.isDone
                    ? _Finished(
                        session: session,
                        keepStrip: _keepStrip,
                        binStrip: _binStrip,
                        busy: _applying,
                        onApply: () => _apply(session),
                        onUndo: _undo,
                      )
                    : _Stage(
                        item: item!,
                        photoKey: _keyFor(item.itemId),
                        tilt: _tilt,
                      ),
              ),
              if (session != null && !session.isDone) ...<Widget>[
                _Counts(session: session),
                const SizedBox(height: GDesign.space16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GDesign.gutter,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: SecondaryButton(
                          label: context.s('Delete'),
                          icon: GIcons.trash,
                          onTap: () => _decide(session, ReviewVerdict.bin),
                        ),
                      ),
                      const SizedBox(width: GDesign.space12),
                      Expanded(
                        child: PrimaryButton(
                          label: item?.role == kRoleStatus
                              ? context.s('Save')
                              : context.s('Restore'),
                          onTap: () => _decide(session, ReviewVerdict.keep),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Back, the screen's name with how far through it is, and Undo.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.session,
    required this.onBack,
    required this.onUndo,
  });

  final ReviewSession? session;
  final VoidCallback onBack;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final ReviewSession? s = session;
    final String? where = s == null || s.isDone
        ? null
        : '${GFormat.count(s.index + 1)} / ${GFormat.count(s.queue.length)}';
    return SizedBox(
      height: 56,
      child: Row(
        children: <Widget>[
          const SizedBox(width: GDesign.space4),
          BarIconButton(
            icon: GIcons.back,
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: onBack,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(context.s('Review'), style: g.headline()),
                if (where != null) Text(where, style: g.figures(g.footnote())),
              ],
            ),
          ),
          BarIconButton(
            icon: GIcons.undo,
            semanticLabel: context.s('Undo'),
            onTap: onUndo,
          ),
          const SizedBox(width: GDesign.space4),
        ],
      ),
    );
  }
}

/// The current photo on its string.
class _Stage extends ConsumerWidget {
  const _Stage({
    required this.item,
    required this.photoKey,
    required this.tilt,
  });

  final RecoverableItem item;
  final GlobalKey<HangingPhotoState> photoKey;
  final TiltSignal tilt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    final int? w = item.width;
    final int? h = item.height;
    final double ratio = (w != null && h != null && w > 0 && h > 0)
        ? w / h
        : 3 / 4;
    return ClipRect(
      child: HangingPhoto(
        key: photoKey,
        aspectRatio: ratio,
        tilt: tilt,
        semanticLabel: item.name,
        onTap: () => Navigator.of(
          context,
        ).push(MediaViewer.route(items: <RecoverableItem>[item], index: 0)),
        child: Image(
          image: ItemThumbnail(
            itemId: item.itemId,
            bridge: bridge,
            maxPixels: 1440,
          ),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

/// Left, to restore, to delete: three measured figures.
class _Counts extends StatelessWidget {
  const _Counts({required this.session});

  final ReviewSession session;

  @override
  Widget build(BuildContext context) {
    final int left = session.queue.length - session.index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: Row(
        children: <Widget>[
          _Figure(value: left, label: context.s('Left')),
          _Figure(value: session.kept.length, label: context.s('To restore')),
          _Figure(value: session.binned.length, label: context.s('To delete')),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(GFormat.count(value), style: g.figures(g.headline())),
          Text(label, style: g.footnote()),
        ],
      ),
    );
  }
}

/// The end of the queue: what will be restored, what will go for good, and
/// Apply. Each set sits in its own strip so it can fly home or turn to dust.
class _Finished extends ConsumerWidget {
  const _Finished({
    required this.session,
    required this.keepStrip,
    required this.binStrip,
    required this.busy,
    required this.onApply,
    required this.onUndo,
  });

  final ReviewSession session;
  final GlobalKey keepStrip;
  final GlobalKey binStrip;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<RecoverableItem> keep = session.kept.toList();
    final List<RecoverableItem> bin = session.binned.toList();
    final bool any = keep.isNotEmpty || bin.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        0,
      ),
      children: <Widget>[
        Text(context.s('All reviewed'), style: g.title2()),
        const SizedBox(height: GDesign.space4),
        Text(
          any
              ? context.s('Nothing changes until you apply.')
              : context.s('You set nothing aside.'),
          style: g.footnote(),
        ),
        if (keep.isNotEmpty) ...<Widget>[
          const SizedBox(height: GDesign.space24),
          Text(
            keep.length == 1
                ? context.s('1 to restore')
                : context.s1('{} to restore', GFormat.count(keep.length)),
            style: g.headline(),
          ),
          const SizedBox(height: GDesign.space8),
          _Strip(boundary: keepStrip, items: keep),
        ],
        if (bin.isNotEmpty) ...<Widget>[
          const SizedBox(height: GDesign.space24),
          Text(
            bin.length == 1
                ? context.s('1 to delete for good')
                : context.s1(
                    '{} to delete for good',
                    GFormat.count(bin.length),
                  ),
            style: g.headline(),
          ),
          Text(GFormat.bytes(session.binnedBytes), style: g.footnote()),
          const SizedBox(height: GDesign.space8),
          _Strip(boundary: binStrip, items: bin),
        ],
        const SizedBox(height: GDesign.space32),
        if (any)
          PrimaryButton(label: context.s('Apply'), busy: busy, onTap: onApply),
        const SizedBox(height: GDesign.space8),
        SecondaryButton(
          label: context.s('Go back one'),
          onTap: busy ? null : onUndo,
        ),
      ],
    );
  }
}

/// A row of small thumbnails standing for a set, inside one boundary so the
/// whole set can be snapshotted for the flight or the dust.
class _Strip extends ConsumerWidget {
  const _Strip({required this.boundary, required this.items});

  final GlobalKey boundary;
  final List<RecoverableItem> items;

  static const int _shown = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final RecoveryBridge bridge = ref.watch(recoveryBridgeProvider);
    final int extra = items.length - _shown;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: RepaintBoundary(
        key: boundary,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final RecoverableItem item in items.take(_shown))
              Padding(
                padding: const EdgeInsetsDirectional.only(end: GDesign.space4),
                child: SizedBox.square(
                  dimension: 48,
                  child: GThumbnail(
                    itemId: item.itemId,
                    bridge: bridge,
                    kind: item.kind,
                    maxPixels: 144,
                    radius: 8,
                  ),
                ),
              ),
            if (extra > 0)
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: g.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+${GFormat.count(extra)}',
                  style: g.figures(g.footnote(color: g.text)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
