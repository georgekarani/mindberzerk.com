import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../bridge/apps_api.g.dart';
import '../../bridge/apps_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/g_card.dart';
import '../device/widgets/device_detail.dart';

/// What apps take up: the total split into the apps themselves, their data,
/// and cache that rebuilds itself, then every app largest first.
///
/// Android has not let one app clear another's cache since 2015, so a row
/// opens that app's own storage screen, where Clear cache is one tap.
class AppsPage extends ConsumerWidget {
  const AppsPage({super.key, this.backLabel});

  final String? backLabel;

  static Route<void> route({String? backLabel}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => AppsPage(backLabel: backLabel),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final AppsState? state = ref.watch(appsStateProvider).value;
    final AppSort sort = ref.watch(appSortProvider);
    final List<AppEntry> apps = ref.watch(sortedAppsProvider);
    final bool blocked = state != null && !state.usageAccess;

    return GGroundScope(
      grouped: true,
      child: LargeTitlePage(
        title: context.s('Apps'),
        grouped: true,
        backLabel: backLabel ?? context.s('Clean up'),
        onBack: () => Navigator.of(context).maybePop(),
        actions: <Widget>[
          NavAction.icon(
            icon: GIcons.info,
            semanticLabel: context.s('Clearing app caches'),
            onTap: () => _explain(context),
          ),
        ],
        slivers: <Widget>[
          if (blocked)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _NeedsAccess(
                onGrant: () =>
                    ref.read(appsBridgeProvider).requestUsageAccess(),
              ),
            )
          else if (apps.isEmpty || state == null)
            const SliverFillRemaining(hasScrollBody: false, child: _Reading())
          else ...<Widget>[
            SliverToBoxAdapter(
              child: Reveal(child: _Split(state: state)),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter,
                  GDesign.space24,
                  GDesign.gutter,
                  GDesign.space12,
                ),
                child: Segmented<AppSort>(
                  semanticLabel: context.s('Sort'),
                  segments: <(AppSort, String)>[
                    (AppSort.total, context.s('Size')),
                    (AppSort.cache, context.s('Cache')),
                    (AppSort.data, context.s('Data')),
                    (AppSort.unused, context.s('Unused')),
                  ],
                  value: sort,
                  onChanged: ref.read(appSortProvider.notifier).select,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
              sliver: SliverList.builder(
                itemCount: apps.length,
                itemBuilder: (BuildContext context, int i) => Reveal(
                  index: i,
                  rise: 8,
                  child: _AppRow(
                    entry: apps[i],
                    sort: sort,
                    first: i == 0,
                    last: i == apps.length - 1,
                    onTap: () => ref
                        .read(appsBridgeProvider)
                        .openAppSettings(apps[i].packageName),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GDesign.gutter + GDesign.space16,
                  GDesign.space8,
                  GDesign.gutter,
                  GDesign.space48,
                ),
                child: Text(
                  context.s('Tap an app to clear its cache'),
                  style: g.footnote(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _explain(BuildContext context) =>
      showDeviceNote(context, context.s('Clearing app caches'), <String>[
        context.s(
          'Android has not let one app clear another app\'s cache since '
          '2015. Apps that claim to are driving your screen or making the '
          'number up.',
        ),
        context.s(
          'Tap an app to open its own storage screen. Clear cache there is '
          'safe: the app rebuilds it. Clear data signs you out and deletes '
          'what the app kept.',
        ),
      ]);
}

/// The total, then one bar split into apps, data and cache.
class _Split extends StatelessWidget {
  const _Split({required this.state});

  final AppsState state;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int cache = state.cacheBytes;
    final int rest = state.totalBytes - cache;
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
          CountUpText(
            value: state.totalBytes,
            format: (num v) => GFormat.bytes(v.round()),
            style: g.figures(g.largeTitle()),
          ),
          Text(
            context.s1('in {} apps', GFormat.count(state.count)),
            style: g.footnote(),
          ),
          const SizedBox(height: GDesign.space16),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: GDesign.motion(context, GDesign.slow),
                curve: GDesign.enter,
                builder: (BuildContext context, double v, Widget? _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: (rest * 1000 ~/ (state.totalBytes + 1)).clamp(
                        1,
                        1000,
                      ),
                      child: ColoredBox(color: g.text.withValues(alpha: 0.5)),
                    ),
                    Expanded(
                      flex: (cache * 1000 * v ~/ (state.totalBytes + 1)).clamp(
                        1,
                        1000,
                      ),
                      child: ColoredBox(color: g.accent),
                    ),
                    Expanded(
                      flex: (cache * 1000 * (1 - v) ~/ (state.totalBytes + 1))
                          .clamp(1, 1000),
                      child: const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: GDesign.space12),
          HeroFigures(
            figures: <(String?, String)>[
              (GFormat.bytes(rest), context.s('Apps and data')),
              (GFormat.bytes(cache), context.s('Cache, rebuilds')),
            ],
          ),
        ],
      ),
    );
  }
}

/// One app: a letter tile, its name, the figure the sort is about, and when
/// it was last used.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.entry,
    required this.sort,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final AppEntry entry;
  final AppSort sort;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int total = entry.appBytes + entry.dataBytes + entry.cacheBytes;
    const Radius r = Radius.circular(GDesign.cardRadius);
    final String figure = switch (sort) {
      AppSort.cache => GFormat.bytes(entry.cacheBytes),
      AppSort.data => GFormat.bytes(entry.dataBytes),
      _ => GFormat.bytes(total),
    };

    return Material(
      color: g.card,
      borderRadius: BorderRadius.vertical(
        top: first ? r : Radius.zero,
        bottom: last ? r : Radius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: GDesign.space12),
          child: Row(
            children: <Widget>[
              _Monogram(label: entry.label),
              const SizedBox(width: GDesign.space12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: last
                        ? null
                        : Border(
                            bottom: BorderSide(color: g.hairline, width: 0.5),
                          ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      0,
                      GDesign.space12,
                      GDesign.space16,
                      GDesign.space12,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                entry.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: g.body(),
                              ),
                              Text(
                                _used(context, entry.lastUsedMillis),
                                style: g.footnote(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: GDesign.space8),
                        Text(figure, style: g.figures(g.body(color: g.muted))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _used(BuildContext context, int? millis) {
    if (millis == null) return context.s('Never opened');
    final int days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(millis))
        .inDays;
    if (days <= 0) return context.s('Used today');
    if (days == 1) return context.s('Used yesterday');
    if (days < 30) return context.s1('Used {} days ago', days);
    if (days < 365) {
      return context.s1('Used {} months ago', (days / 30).round());
    }
    return context.s('Unused for over a year');
  }
}

/// The app's first letter on a rounded tile, standing in for its icon.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final String letter = label.isEmpty ? '?' : label.characters.first;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: g.fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(letter.toUpperCase(), style: g.headline(color: g.muted)),
    );
  }
}

/// Reading sizes: a count and a bar that fills as apps are measured.
class _Reading extends ConsumerWidget {
  const _Reading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final AppsProgress? p = ref.watch(appsProgressProvider).value;
    final int total = p?.total ?? 0;
    final int done = p?.done ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GDesign.space48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(context.s('Measuring apps'), style: g.headline()),
            const SizedBox(height: GDesign.space12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total <= 0 ? null : (done / total).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: g.fill,
                color: g.accent,
              ),
            ),
            if (total > 0) ...<Widget>[
              const SizedBox(height: GDesign.space8),
              Text(
                context.s1(
                  '{} of ${GFormat.count(total)}',
                  GFormat.count(done),
                ),
                style: g.figures(g.footnote()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Usage access is off: one line and one button.
class _NeedsAccess extends StatelessWidget {
  const _NeedsAccess({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GDesign.space32),
        child: Reveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(GIcons.grid, size: 48, color: g.faint),
              const SizedBox(height: GDesign.space16),
              Text(
                context.s('App sizes need usage access'),
                textAlign: TextAlign.center,
                style: g.headline(),
              ),
              Text(
                context.s('It reads sizes, not what you do in them'),
                textAlign: TextAlign.center,
                style: g.footnote(),
              ),
              const SizedBox(height: GDesign.space24),
              PrimaryButton(label: context.s('Allow'), onTap: onGrant),
            ],
          ),
        ),
      ),
    );
  }
}
