import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/theme/tokens.dart';
import '../../bridge/recovery_api.g.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/g_button.dart';
import '../device/state/identity_providers.dart';
import '../recovery/category_page.dart';
import '../recovery/state/recovery_providers.dart';
import '../search/search_page.dart';
import 'widgets/home_mosaic.dart';
import 'widgets/home_sheet.dart';

/// Home, in the immersive layout.
///
/// The user's own deleted photos fill the screen, one measured figure sits
/// over them with one action, and everything else lives in the sheet. The
/// phone still names itself in the header, because this app is about this
/// handset and what it is holding.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceIdentity? identity = ref.watch(deviceIdentityProvider).value;

    // A background scan that has just finished changes every count here, so
    // the prescan is asked again the moment it stops.
    ref.listen<AsyncValue<BackgroundScanState?>>(backgroundScanProvider, (
      AsyncValue<BackgroundScanState?>? was,
      AsyncValue<BackgroundScanState?> now,
    ) {
      final bool wasRunning = was?.value?.running ?? false;
      final bool isRunning = now.value?.running ?? false;
      if (wasRunning && !isRunning) ref.invalidate(prescanProvider);
    });

    return ImmersiveScaffold(
      background: const HomeMosaic(),
      body: const _HeroLayer(),
      primary: const _PrimaryAction(),
      sheet: ContentSheet(
        builder: (BuildContext context, ScrollController scroll) =>
            HomeSheet(scroll: scroll),
      ),
      header: FloatHeader(
        title: deviceTitle(identity),
        actions: <Widget>[
          FloatIconButton(
            icon: Icons.refresh_rounded,
            semanticLabel: context.s('Check again'),
            onTap: () => ref.invalidate(prescanProvider),
          ),
          FloatIconButton(
            icon: Icons.search_rounded,
            semanticLabel: context.s('Search files, photos, messages'),
            onTap: () => Navigator.of(context).push(SearchPage.route()),
          ),
        ],
      ),
    );
  }
}

/// What the hero and the primary action are showing.
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

/// One read of every provider the hero depends on, so the figure and the
/// button can never disagree about which state the screen is in.
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
    } else if (summary.deletedItems == 0) {
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

/// The figure, its caption and any facts that need attention, stacked just
/// above the primary action.
class _HeroLayer extends ConsumerWidget {
  const _HeroLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GTokens t = context.g;
    final GDesignTheme g = GDesignTheme.of(context);
    final _HomeView view = _HomeView.read(ref);
    final RecoverySummary? summary = view.summary;
    final BackgroundScanState? scan = view.scan;

    final String label = view.mode == _Mode.running
        ? context.s('Checking this phone')
        : context.s('Recoverable now');

    final String? value = switch (view.mode) {
      _Mode.running => GFormat.count(scan!.found),
      _Mode.loading || _Mode.blind => null,
      _Mode.empty || _Mode.clear => GFormat.count(0),
      _Mode.ready => GFormat.count(summary!.deletedItems),
    };

    final String caption = switch (view.mode) {
      _Mode.running => _progressLine(context, scan!),
      _Mode.loading => context.s('Checking your device'),
      _Mode.blind => context.s('Not checked yet. File access is off.'),
      _Mode.empty => context.s(
        'Nothing in the trash. A full scan looks further.',
      ),
      _Mode.clear => context.s('Nothing waiting. Your trash is clear.'),
      _Mode.ready => context.s1(
        '{} can come back',
        GFormat.bytes(summary!.deletedBytes),
      ),
    };

    final int expiring = summary?.expiringSoonItems ?? 0;
    final bool floor =
        summary != null && summary.partial && view.mode == _Mode.ready;

    final List<Widget> facts = <Widget>[
      if (view.mode == _Mode.ready && expiring > 0)
        FloatChip(
          label: context.s1(
            '{} expire within 48 hours',
            GFormat.count(expiring),
          ),
          tone: t.danger,
          onTap: () => Navigator.of(context).push(
            CategoryPage.route(
              title: context.s('Expiring'),
              sourceIds: kAllSourceIds,
            ),
          ),
        ),
      // Counted without file access, so the figure is the least there is,
      // not the total. Said on the figure, where the number is read.
      if (floor)
        FloatChip(label: context.s('Floor, not a total'), tone: t.warning),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // Sheet peek, then the primary action, then this block.
        final double bottom =
            box.maxHeight * GDesign.sheetPeek +
            GDesign.space16 +
            GDesign.buttonHeight +
            GDesign.space24;

        return Stack(
          children: <Widget>[
            Positioned(
              left: GDesign.gutter,
              right: GDesign.gutter,
              bottom: bottom,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  HeroFigure(
                    label: label,
                    value: value,
                    caption: caption,
                    tone: view.mode == _Mode.running ? g.accent : null,
                  ),
                  if (view.mode == _Mode.running &&
                      (scan?.total ?? 0) > 0) ...<Widget>[
                    const SizedBox(height: GDesign.space12),
                    LinearProgressIndicator(
                      value: (scan!.scanned / scan.total).clamp(0.0, 1.0),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      color: g.accent,
                      backgroundColor: g.hairline,
                    ),
                  ],
                  if (facts.isNotEmpty) ...<Widget>[
                    const SizedBox(height: GDesign.space8),
                    Wrap(spacing: GDesign.space8, children: facts),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Where the scan is and how far through it, on one line.
  static String _progressLine(BuildContext context, BackgroundScanState scan) {
    final String where = switch (scan.sourceId) {
      'media_trash' => context.s('Trash folders'),
      'app_trash' => context.s('App leftovers'),
      'thumbnails' => context.s('Thumbnail cache'),
      _ => context.s('Looking'),
    };
    if (scan.total <= 0) return where;
    return '$where  ${GFormat.count(scan.scanned)} / '
        '${GFormat.count(scan.total)}';
  }
}

/// The screen's one action. Nothing at all when there is nothing to do.
class _PrimaryAction extends ConsumerWidget {
  const _PrimaryAction();

  /// 17 + 18 + 17 makes the 52 dp button the canvas draws.
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: GSpace.lg,
    vertical: 17,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _HomeView view = _HomeView.read(ref);

    switch (view.mode) {
      case _Mode.loading:
      case _Mode.clear:
        return const SizedBox.shrink();
      case _Mode.running:
        return GButton(
          label: context.s('Stop'),
          kind: GButtonKind.ghost,
          padding: _padding,
          onPressed: () async {
            await ref.read(recoveryBridgeProvider).cancelScan();
            ref.invalidate(backgroundScanProvider);
          },
        );
      case _Mode.blind:
        return GButton(
          label: context.s('Turn on file access'),
          icon: Icons.folder_open_rounded,
          padding: _padding,
          onPressed: () async {
            await ref.read(recoveryBridgeProvider).requestAllFilesAccess();
            ref.invalidate(recoveryAccessProvider);
            ref.invalidate(prescanProvider);
          },
        );
      case _Mode.empty:
        return GButton(
          label: context.s('Scan this phone'),
          icon: Icons.search_rounded,
          padding: _padding,
          onPressed: () async {
            await ref.read(recoveryBridgeProvider).startBackgroundScan();
            ref.invalidate(backgroundScanProvider);
          },
        );
      case _Mode.ready:
        return GButton(
          label: context.s('Review and restore'),
          padding: _padding,
          onPressed: () => Navigator.of(
            context,
          ).push(CategoryPage.route(title: context.s('Everything'))),
        );
    }
  }
}
