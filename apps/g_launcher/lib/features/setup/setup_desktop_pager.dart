import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../design/device_preview.dart';
import '../../design/distro_preview.dart';
import '../../engine/effective_theme.dart';
import '../../engine/theme_spec.dart';
import '../../i18n/i18n.dart';
import '../../system/wallpaper_source.dart';
import '../themes/theme_catalog.dart';
import '../themes/theme_peek.dart';
import '../themes/themes_screen.dart' show ThemePreview;
import 'setup_sheet.dart';

/// The paid distros the signed index offers, for the "more desktops" page.
///
/// Read from the cached catalogue only: names and colour summaries, no
/// downloads. Empty when there is no index yet, and the page then speaks in
/// general terms instead of naming anything.
final setupMoreDistrosProvider = FutureProvider<List<ThemeCard>>((ref) async {
  try {
    final cards = await ref.watch(themeCatalogProvider.future);
    return [
      for (final c in cards)
        if (c.sku != null && !c.bundled) c,
    ];
  } catch (_) {
    return const [];
  }
});

/// One page of the pager: a free distro to choose, or the "more" page.
sealed class _DeskPage {
  const _DeskPage();
}

final class _FreePage extends _DeskPage {
  const _FreePage(this.spec);
  final ThemeSpec spec;
}

final class _MorePage extends _DeskPage {
  const _MorePage(this.cards);
  final List<ThemeCard> cards;
}

/// Board 2, Choose your desktop.
///
/// Three free desktops, each the real distro, then one last page saying more
/// exist. Setup is not a shop, so that page names them and nothing else: no
/// prices, no previews to fetch, no way to pick one. Its button still uses the
/// free desktop chosen last, so swiping to the end never strands anybody.
class SetupDesktopPager extends ConsumerStatefulWidget {
  const SetupDesktopPager({
    super.key,
    required this.free,
    required this.activeId,
    required this.describe,
    required this.onSelected,
    required this.onBack,
    this.onUse,
  });

  /// The bundled free distros, in display order.
  final List<ThemeSpec> free;

  /// The distro selected when the pager opens; used once, for the first page.
  final String activeId;

  /// The one line under a free distro's name.
  final String Function(ThemeSpec spec) describe;

  /// A free page settled. The screen starts that distro's pack sweep.
  final ValueChanged<String> onSelected;

  /// The primary button. Null holds it disabled, which the screen does while
  /// the chosen distro's theme pack is still arriving.
  final VoidCallback? onUse;

  /// Back to Hello.
  final VoidCallback onBack;

  @override
  ConsumerState<SetupDesktopPager> createState() => _SetupDesktopPagerState();
}

class _SetupDesktopPagerState extends ConsumerState<SetupDesktopPager> {
  late final PageController _controller;
  late int _index;

  /// The free distro last settled on. The more page borrows its palette and
  /// its button, so the panel never changes colour for a desktop not chosen.
  late ThemeSpec _chosen;

  @override
  void initState() {
    super.initState();
    final start = widget.free.indexWhere((s) => s.id == widget.activeId);
    _index = start < 0 ? 0 : start;
    _chosen = widget.free[_index];
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settled(List<_DeskPage> pages, int i) {
    setState(() => _index = i);
    final page = pages[i];
    if (page is! _FreePage) return;
    _chosen = page.spec;
    Analytics.themeSelected(page.spec.id);
    ref.read(selectedThemeIdProvider.notifier).select(page.spec.id);
    // After the select, so the sweep resolves toward this distro.
    widget.onSelected(page.spec.id);
  }

  void _go(int i, int count) => _controller.animateToPage(
        (i + count) % count,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );

  @override
  Widget build(BuildContext context) {
    final more = ref.watch(setupMoreDistrosProvider).asData?.value ??
        const <ThemeCard>[];
    final pages = <_DeskPage>[
      for (final s in widget.free) _FreePage(s),
      _MorePage(more),
    ];
    final index = _index.clamp(0, pages.length - 1);
    final page = pages[index];
    final ink = SetupInk.forSpec(page is _FreePage ? page.spec : _chosen);
    final top = MediaQuery.paddingOf(context).top;

    final (title, meta) = switch (page) {
      _FreePage(:final spec) => (spec.name, widget.describe(spec)),
      _MorePage(:final cards) => (
          cards.isEmpty
              ? ref.t('setup.desktop.moreTitle')
              : ref.t('setup.desktop.moreCount', {'n': '${cards.length}'}),
          ref.t('setup.desktop.moreBody'),
        ),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: pages.length,
          onPageChanged: (i) => _settled(pages, i),
          itemBuilder: (context, i) => switch (pages[i]) {
            _FreePage(:final spec) => _FreeDesktop(spec: spec),
            _MorePage(:final cards) =>
              _MoreDesktops(cards: cards, palette: _chosen.palette),
          },
        ),
        Positioned(
          top: top + 12,
          left: 12,
          child: IconButton(
            onPressed: widget.onBack,
            tooltip: ref.t('common.back'),
            icon: const Icon(Icons.arrow_back_rounded),
            color: ink.text,
            style: IconButton.styleFrom(
              backgroundColor: ink.scrim.withValues(alpha: 0.55),
            ),
          ),
        ),
        if (page is _FreePage)
          Positioned(
            top: top + 18,
            right: 16,
            child: SetupPill(ink: ink, label: ref.t('setup.desktop.free')),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SetupBottomPanel(
            ink: ink,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.1,
                              letterSpacing: -0.3,
                              fontWeight: FontWeight.w700,
                              color: ink.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: ink.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // No "1 of 4" here: the dots below already say where
                    // this page sits, and the same fact twice is clutter.
                  ],
                ),
                const SizedBox(height: 14),
                _Dots(
                  count: pages.length,
                  index: index,
                  ink: ink,
                  labels: [for (final p in pages) _labelOf(p)],
                  onTap: (i) => _go(i, pages.length),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SetupIconButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: ref.t('setup.desktop.previous'),
                      ink: ink,
                      onPressed: () => _go(index - 1, pages.length),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SetupPrimaryButton(
                        ink: ink,
                        label:
                            ref.t('setup.desktop.use', {'name': _chosen.name}),
                        onPressed: widget.onUse,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SetupIconButton(
                      icon: Icons.chevron_right_rounded,
                      tooltip: ref.t('setup.desktop.next'),
                      ink: ink,
                      onPressed: () => _go(index + 1, pages.length),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _labelOf(_DeskPage p) => switch (p) {
        _FreePage(:final spec) => spec.name,
        _MorePage() => ref.t('setup.desktop.moreTitle'),
      };
}

/// A free distro's desktop, drawn from its real spec and wallpaper.
///
/// Through [DistroPreview], the adapter the store uses, so setup shows the same
/// desktop the store and the shell do: Ubuntu's top bar and left dock, Plasma's
/// bottom panel. Drawing [DevicePreview] straight from the spec passed the
/// dock and nothing else, so Ubuntu showed a sliver of dock and no bar and
/// Plasma showed wallpaper with no panel at all.
class _FreeDesktop extends ConsumerWidget {
  const _FreeDesktop({required this.spec});

  final ThemeSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walls = spec.wallpapers;
    final wall = walls.isNotEmpty && isThemeAssetRef(walls.first)
        ? spec.asset(walls.first).image
        : null;

    // Neutral prefs, as the store's peek resolves: the distro as it ships,
    // not as anyone has edited it. Bundled, so its files are on the device.
    final peeked = PeekedTheme(
      packId: spec.id,
      spec: spec,
      effective: EffectiveTheme.resolve(
        spec,
        const LauncherPrefs(),
        systemDark: ref.watch(systemDarkProvider),
      ),
      assetsOnDisk: true,
    );

    return SizedBox.expand(
      child: DistroPreview(peeked: peeked, background: wall),
    );
  }
}

/// The last page: a mosaic of every other desktop, by name.
///
/// Tiles are the index's own colour summaries, already on the device with the
/// catalogue, so the page costs no download. With no index yet it shows the
/// chosen palette alone and lets the panel text do the talking.
class _MoreDesktops extends StatelessWidget {
  const _MoreDesktops({required this.cards, required this.palette});

  final List<ThemeCard> cards;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      children: [
        SetupWallpaper(palette: palette),
        if (cards.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(2, top + 64, 2, 0),
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 0.72,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (final c in cards.take(12))
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      ThemePreview(c.preview),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            c.name,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFF7F2F5),
                              shadows: [
                                Shadow(color: Color(0x99000000), blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Page dots, tappable, with each page's name for screen readers.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.ink,
    required this.labels,
    required this.onTap,
  });

  final int count;
  final int index;
  final SetupInk ink;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var k = 0; k < count; k++)
            Semantics(
              button: true,
              selected: k == index,
              label: labels[k],
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(k),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: k == index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: k == index ? ink.text : const Color(0x59FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
