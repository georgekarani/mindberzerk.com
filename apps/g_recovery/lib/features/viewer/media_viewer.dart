import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/recovery_api.g.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../core/messenger/g_message.dart';
import '../../core/messenger/g_messenger.dart';
import '../../ui/g_thumbnail.dart';
import '../recovery/state/recovery_actions.dart';
import '../recovery/state/recovery_providers.dart';
import 'recovered_frame.dart';

/// The viewer: the photo is the screen. Material chrome floats over it, a tap
/// hides the chrome and turns the ground black, and the one primary action
/// is Restore (Save for a status).
///
/// Opened from a grid with a [heroPrefix], the photo zooms out of its tile
/// and back into it on close. Restore flies the photo home; Delete for good
/// turns it to dust; either way the next photo takes its place.
class MediaViewer extends ConsumerStatefulWidget {
  const MediaViewer({
    required this.items,
    required this.index,
    super.key,
    this.heroPrefix,
    this.viewOnly = false,
  });

  final List<RecoverableItem> items;
  final int index;

  /// Matches the tiles' hero tags (`<prefix>-<itemId>`). Null opens without
  /// the zoom, for lists that have no tile to fly from.
  final String? heroPrefix;

  /// Looking only: media still inside a chat app.
  final bool viewOnly;

  static Route<void> route({
    required List<RecoverableItem> items,
    required int index,
    String? heroPrefix,
    bool viewOnly = false,
  }) => PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder:
        (BuildContext context, Animation<double> a, Animation<double> b) =>
            MediaViewer(
              items: items,
              index: index,
              heroPrefix: heroPrefix,
              viewOnly: viewOnly,
            ),
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondary,
          Widget child,
        ) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
  );

  @override
  ConsumerState<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<MediaViewer> {
  late final List<RecoverableItem> _items = List<RecoverableItem>.of(
    widget.items,
  );
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _current = widget.index;
  late final GShellNav _nav;
  bool _chrome = true;
  bool _busy = false;

  /// While a photo is zoomed in, a sideways drag pans it instead of turning
  /// the page.
  bool _zoomed = false;

  /// Snapshot targets for the flight and the dust, one per page.
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  RecoverableItem get _item => _items[_current];

  @override
  void initState() {
    super.initState();
    _nav = ref.read(gShellNavHiddenProvider.notifier)..hide();
  }

  @override
  void dispose() {
    _nav.show();
    _pages.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String itemId) =>
      _keys.putIfAbsent(itemId, () => GlobalKey(debugLabel: itemId));

  bool get _canAct => !widget.viewOnly && _item.role != kRoleMedia && !_busy;

  /// Takes the acted-on item out and shows its neighbour, or closes the
  /// viewer when it was the last one.
  void _drop(String itemId) {
    final int at = _items.indexWhere((RecoverableItem i) => i.itemId == itemId);
    if (at < 0) return;
    if (_items.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _items.removeAt(at);
      _current = _current.clamp(0, _items.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pages.hasClients) _pages.jumpToPage(_current);
    });
  }

  Future<void> _restore() async {
    final RecoverableItem item = _item;
    setState(() => _busy = true);
    final RecoveryActionResult result = await runRecoveryAction(ref, <String>[
      item.itemId,
    ], purge: false);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.done.contains(item.itemId)) {
      await Flight.home(context, _keyFor(item.itemId));
      if (!mounted) return;
      _drop(item.itemId);
      refreshRecovery(ref);
    } else {
      reportRecoveryProblem(context, result);
    }
  }

  Future<void> _delete() async {
    final RecoverableItem item = _item;
    final bool go = await showConfirmSheet(
      context: context,
      title: context.s('Delete 1 item for good'),
      message: context.s(
        'These leave the trash for good. This app cannot bring them back '
        'afterwards, and neither can anything else.',
      ),
      confirmLabel: context.s('Delete'),
      cancelLabel: context.s('Keep'),
    );
    if (!go || !mounted) return;
    setState(() => _busy = true);
    final RecoveryActionResult result = await runRecoveryAction(ref, <String>[
      item.itemId,
    ], purge: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.done.contains(item.itemId)) {
      await Dust.scatter(context, _keyFor(item.itemId));
      if (!mounted) return;
      _drop(item.itemId);
      refreshRecovery(ref);
    } else {
      reportRecoveryProblem(context, result);
    }
  }

  Future<void> _openElsewhere() async {
    final bool opened = await ref
        .read(recoveryBridgeProvider)
        .openItemExternally(_item.itemId);
    if (!opened && mounted) {
      GMessenger.show(
        context,
        GMessage.warning(context.s('No app on this phone can open it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    final Duration fade = GDesign.motion(context, GDesign.fast);
    final RecoverableItem item = _item;
    final bool status = item.role == kRoleStatus;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedContainer(
        duration: fade,
        color: _chrome ? g.ground : const Color(0xFF000000),
        child: Stack(
          children: <Widget>[
            PageView.builder(
              controller: _pages,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: (int i) => setState(() {
                _current = i;
                _zoomed = false;
              }),
              itemBuilder: (BuildContext context, int i) {
                final RecoverableItem page = _items[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _chrome = !_chrome),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: inset.top + 72,
                      bottom: inset.bottom + 152,
                    ),
                    child: _Page(
                      item: page,
                      boundary: _keyFor(page.itemId),
                      heroTag: widget.heroPrefix == null
                          ? null
                          : '${widget.heroPrefix}-${page.itemId}',
                      chip: _chrome ? _leavesChip(context, page) : null,
                      onZoom: (bool zoomed) {
                        if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                      },
                    ),
                  ),
                );
              },
            ),
            // Chrome: back, where and when, details.
            Positioned(
              left: GDesign.space12,
              right: GDesign.space12,
              top: inset.top + GDesign.space8,
              child: _Fade(
                visible: _chrome,
                child: Row(
                  children: <Widget>[
                    FloatIconButton(
                      icon: GIcons.back,
                      semanticLabel: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    Expanded(child: _Caption(item: item)),
                    FloatIconButton(
                      icon: GIcons.info,
                      semanticLabel: context.s('Details'),
                      onTap: () => _details(context, item),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Fade(
                visible: _chrome,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_items.length > 1)
                      _Filmstrip(
                        items: _items,
                        current: _current,
                        onPick: (int i) => _pages.animateToPage(
                          i,
                          duration: GDesign.motion(context, GDesign.normal),
                          curve: GDesign.enter,
                        ),
                      ),
                    ActionBar(
                      floating: true,
                      leading: FloatIconButton(
                        icon: GIcons.share,
                        semanticLabel: context.s('Open in another app'),
                        onTap: _openElsewhere,
                      ),
                      center: _canAct || _busy
                          ? PrimaryButton(
                              pill: true,
                              busy: _busy,
                              label: status
                                  ? context.s('Save')
                                  : context.s('Restore'),
                              onTap: _canAct ? _restore : null,
                            )
                          : null,
                      trailing: _canAct
                          ? FloatIconButton(
                              icon: GIcons.trash,
                              semanticLabel: context.s('Delete for good'),
                              onTap: _delete,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Leaves in 6 days" over the photo, while there is an expiry to tell.
  static String? _leavesChip(BuildContext context, RecoverableItem item) {
    final int? days = item.expiresInDays;
    if (days == null) return null;
    if (days <= 0) return context.s('Leaves today');
    if (days == 1) return context.s('Leaves tomorrow');
    return context.s1('Leaves in {} days', days);
  }

  /// Everything known about the item, on a sheet rather than on the photo.
  void _details(BuildContext context, RecoverableItem item) {
    final String quality = switch (item.role) {
      kRoleMedia => context.s('In the app'),
      kRoleStatus => context.s('Status'),
      _ =>
        item.fidelity == 'preview'
            ? context.s('Preview only')
            : context.s('Full quality'),
    };
    final int? deleted = item.dateDeletedMillis;
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GDesign.space16),
        children: <Widget>[
          GroupedSection(
            children: <Widget>[
              ListRow(title: item.name),
              ListRow(
                title: context.s('Size'),
                detail: GFormat.bytes(item.sizeBytes),
              ),
              if (item.width != null && item.height != null)
                ListRow(
                  title: context.s('Dimensions'),
                  detail: '${item.width} x ${item.height}',
                ),
              if (item.durationMillis != null)
                ListRow(
                  title: context.s('Length'),
                  detail: GFormat.duration(
                    Duration(milliseconds: item.durationMillis!),
                  ),
                ),
              ListRow(title: context.s('Quality'), detail: quality),
              if (item.origin != null)
                ListRow(title: context.s('From'), detail: item.origin),
              if (deleted != null)
                ListRow(
                  title: context.s('Deleted'),
                  detail: MaterialLocalizations.of(context).formatMediumDate(
                    DateTime.fromMillisecondsSinceEpoch(deleted),
                  ),
                ),
              if (item.relativePath != null)
                ListRow(
                  title: context.s('Folder'),
                  subtitle: item.relativePath,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One page: a photo sized to its own shape so the zoom lands exactly, or
/// the right frame for video, audio, text and documents.
///
/// Pinch zooms up to 6x and a double tap toggles 2.5x at the tapped point.
class _Page extends ConsumerStatefulWidget {
  const _Page({
    required this.item,
    required this.boundary,
    required this.heroTag,
    required this.chip,
    required this.onZoom,
  });

  final RecoverableItem item;
  final GlobalKey boundary;
  final String? heroTag;
  final String? chip;
  final ValueChanged<bool> onZoom;

  @override
  ConsumerState<_Page> createState() => _PageState();
}

class _PageState extends ConsumerState<_Page>
    with SingleTickerProviderStateMixin {
  final TransformationController _zoom = TransformationController();
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: GDesign.normal,
  );
  Animation<Matrix4>? _to;
  Offset _tapAt = Offset.zero;

  /// The photo's shape read from the decoded picture, for the files that
  /// carry no width and height of their own (loose files from app folders).
  double? _ratio;
  ImageStream? _shape;
  late final ImageStreamListener _onShape = ImageStreamListener((
    ImageInfo info,
    bool _,
  ) {
    final double r = info.image.width / info.image.height;
    if (mounted && r != _ratio) setState(() => _ratio = r);
  });

  @override
  void initState() {
    super.initState();
    final RecoverableItem item = widget.item;
    if (item.kind == 'image' && (item.width == null || item.height == null)) {
      _shape = ItemThumbnail(
        itemId: widget.item.itemId,
        bridge: ref.read(recoveryBridgeProvider),
        maxPixels: 360,
      ).resolve(ImageConfiguration.empty)..addListener(_onShape);
    }
    _zoom.addListener(_report);
    _settle.addListener(() {
      final Animation<Matrix4>? to = _to;
      if (to != null) _zoom.value = to.value;
    });
  }

  @override
  void dispose() {
    _shape?.removeListener(_onShape);
    _zoom.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _report() => widget.onZoom(_zoom.value.getMaxScaleOnAxis() > 1.01);

  /// In to 2.5x around the tapped point, or back out to fit.
  void _toggleZoom() {
    final bool zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    const double scale = 2.5;
    final Matrix4 target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(
              -_tapAt.dx * (scale - 1),
              -_tapAt.dy * (scale - 1),
              0,
              1,
            )
            ..scaleByDouble(scale, scale, 1, 1));
    _to = Matrix4Tween(
      begin: _zoom.value,
      end: target,
    ).animate(CurvedAnimation(parent: _settle, curve: Springs.standardCurve));
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final RecoverableItem item = widget.item;
    if (item.kind != 'image') {
      return RepaintBoundary(
        key: widget.boundary,
        child: RecoveredFrame(item: item),
      );
    }

    final int? w = item.width;
    final int? h = item.height;
    final double ratio =
        _ratio ?? ((w != null && h != null && w > 0 && h > 0) ? w / h : 3 / 4);
    final Widget photo = Image(
      image: ItemThumbnail(
        itemId: item.itemId,
        bridge: ref.watch(recoveryBridgeProvider),
        maxPixels: 2048,
      ),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      semanticLabel: item.name,
    );

    return GestureDetector(
      onDoubleTapDown: (TapDownDetails d) => _tapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _zoom,
        maxScale: 6,
        child: Center(
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                RepaintBoundary(
                  key: widget.boundary,
                  child: widget.heroTag == null
                      ? photo
                      : PhotoHero(tag: widget.heroTag!, child: photo),
                ),
                if (widget.chip != null)
                  PositionedDirectional(
                    start: GDesign.space12,
                    top: GDesign.space12,
                    child: PhotoChip(widget.chip!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The day it was deleted, and the time and source under it.
class _Caption extends StatelessWidget {
  const _Caption({required this.item});

  final RecoverableItem item;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int? millis = item.dateDeletedMillis ?? item.dateAddedMillis;
    final DateTime? when = millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis);
    final String title = when == null
        ? item.name
        : GFormat.relativeDay(when, DateTime.now());
    final String joined = <String>[
      if (when != null)
        MaterialLocalizations.of(
          context,
        ).formatTimeOfDay(TimeOfDay.fromDateTime(when)),
      ?item.origin,
    ].join(', ');
    final String? detail = joined.isEmpty ? null : joined;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: g.headline(),
        ),
        if (detail != null)
          Text(
            detail,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: g.footnote(),
          ),
      ],
    );
  }
}

/// Thumbnails along the bottom, the current one wider, the way Photos does.
/// The strip keeps the current thumbnail centred as the pages turn.
class _Filmstrip extends ConsumerStatefulWidget {
  const _Filmstrip({
    required this.items,
    required this.current,
    required this.onPick,
  });

  final List<RecoverableItem> items;
  final int current;
  final ValueChanged<int> onPick;

  static const double thin = 28;
  static const double wide = 40;

  /// A thin thumbnail plus its 1 dp margin each side.
  static const double step = thin + 2;

  @override
  ConsumerState<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends ConsumerState<_Filmstrip> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.current * _Filmstrip.step,
  );

  @override
  void didUpdateWidget(_Filmstrip old) {
    super.didUpdateWidget(old);
    if (old.current == widget.current || !_scroll.hasClients) return;
    final double target = widget.current * _Filmstrip.step;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: GDesign.normal, curve: GDesign.enter);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    // Half a screen of padding each side lets the first and last thumbnails
    // reach the centre too.
    final double side = (width - _Filmstrip.wide) / 2 - 4;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: side),
        itemCount: widget.items.length,
        itemBuilder: (BuildContext context, int i) {
          final bool on = i == widget.current;
          return GestureDetector(
            onTap: () => widget.onPick(i),
            child: AnimatedContainer(
              duration: GDesign.motion(context, GDesign.fast),
              width: on ? _Filmstrip.wide : _Filmstrip.thin,
              margin: EdgeInsets.symmetric(horizontal: on ? 4 : 1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(on ? 4 : 0),
                child: GThumbnail(
                  itemId: widget.items[i].itemId,
                  bridge: ref.watch(recoveryBridgeProvider),
                  kind: widget.items[i].kind,
                  maxPixels: 120,
                  radius: 0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Chrome that fades away on a tap and stops taking touches while hidden.
class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: GDesign.motion(context, GDesign.fast),
      child: child,
    ),
  );
}
