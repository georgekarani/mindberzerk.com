/// The icon store: icon themes sold by style, each shown with this phone's
/// own apps.
///
/// Settings > Icons keeps what configures icons (theme, shape, size, packs
/// from Play); this screen is only for choosing and buying a style.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/billing/entitlements.dart';
import '../../data/cdn/pack_repository.dart';
import '../../design/components/components.dart';
import '../../engine/effective_theme.dart';
import '../../platform/pack_api.g.dart';
import '../themes/theme_catalog.dart' show CardStatus;
import 'icon_family_page.dart';
import 'icon_pack_actions.dart';
import 'icon_store_model.dart';
import 'icon_store_widgets.dart';
import 'icon_theme_screen.dart' show packCoverageProvider;

/// The store's filters. Local to the screen, so reopening starts at All.
enum _Tab {
  all('icons.tab.all'),
  line('icons.tab.line'),
  linux('icons.tab.linux'),
  yours('icons.tab.yours');

  const _Tab(this.key);
  final String key;
}

class IconStoreScreen extends ConsumerStatefulWidget {
  const IconStoreScreen({super.key});

  @override
  ConsumerState<IconStoreScreen> createState() => _IconStoreScreenState();
}

class _IconStoreScreenState extends ConsumerState<IconStoreScreen> {
  _Tab _tab = _Tab.all;

  @override
  Widget build(BuildContext context) {
    // The CDN check that runs once per app run, and prices from Play.
    ref.watch(catalogueRefreshProvider);
    ref.watch(ownedSkusProvider);

    final theme = ref.watch(effectiveThemeProvider).value;
    final families = ref.watch(iconFamiliesProvider);
    final d = ChromeScope.of(context);

    if (theme == null) return const ThemedScaffold(body: SizedBox.shrink());
    final actions = IconPackActions(context, ref, theme);

    bool yours(IconFamily f) => f.variants.any((p) =>
        actions.isApplied(p) ||
        switch (actions.statusOf(p)) {
          CardStatus.bundled ||
          CardStatus.installed ||
          CardStatus.updateAvailable =>
            true,
          _ => false,
        });

    bool shown(IconFamily f) => switch (_tab) {
          _Tab.all => true,
          _Tab.line => f.kind == IconSetKind.line,
          _Tab.linux => f.kind == IconSetKind.linux,
          _Tab.yours => yours(f),
        };

    final visible = [
      for (final f in families)
        if (shown(f)) f,
    ];

    return ThemedScaffold(
      body: RefreshIndicator(
        color: d.colors.accent,
        backgroundColor: d.colors.line,
        onRefresh: () => ref.read(packActionsProvider).refresh(),
        child: ListView(
          padding: EdgeInsets.only(
            top: MediaQuery.viewPaddingOf(context).top,
            bottom: 28 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            const _Back(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
              child: Text(
                context.t('icons.store.title'),
                style: d.text.display,
              ),
            ),
            _Tabs(
              current: _tab,
              onPick: (t) => setState(() => _tab = t),
            ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
                child: Text(
                  context.t('icons.store.empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: d.colors.textMuted, fontSize: 12.5),
                ),
              ),
            for (final kind in IconSetKind.values)
              if (visible.any((f) => f.kind == kind)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  child: Text(
                    context.t(switch (kind) {
                      IconSetKind.line => 'icons.tab.line',
                      IconSetKind.linux => 'icons.tab.linux',
                    }),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: d.colors.textMuted,
                    ),
                  ),
                ),
                for (final f in visible)
                  if (f.kind == kind)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _FamilyCard(family: f, actions: actions),
                    ),
              ],
          ],
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: Icon(Icons.arrow_back, color: c.text),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onPick});

  final _Tab current;
  final ValueChanged<_Tab> onPick;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (final t in _Tab.values) ...[
            if (t != _Tab.values.first) const SizedBox(width: 6),
            Material(
              color: t == current ? c.text : c.surface,
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(t),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Text(
                    context.t(t.key),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          t == current ? FontWeight.w600 : FontWeight.w400,
                      color: t == current ? c.bg : c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether native has [family]'s geometry loaded, so it can draw it live.
bool _wornGeometry(IconPackActions actions, IconFamily family) {
  final worn = actions.appliedLine;
  return worn != null && brandFamilyOf(worn) == family.id;
}

/// One style: ten of your apps drawn in it, its name, and one action.
class _FamilyCard extends ConsumerWidget {
  const _FamilyCard({required this.family, required this.actions});

  final IconFamily family;
  final IconPackActions actions;

  /// The variant the card speaks for: the one being worn, else the distro's
  /// own colour, else the first.
  PackInfo _lead() {
    for (final p in family.variants) {
      if (actions.isApplied(p)) return p;
    }
    for (final p in family.variants) {
      if (p.packId == actions.distroPack) return p;
    }
    return family.variants.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ChromeScope.of(context).colors;
    final lead = _lead();
    final status = actions.statusOf(lead);
    final applied = family.variants.any(actions.isApplied);
    final progress = ref.watch(packProgressProvider)[lead.packId];
    final coverage = ref.watch(packCoverageProvider(lead.packId)).value;

    final subtitle = family.kind == IconSetKind.line
        ? context.t('icons.colourCount', {'n': '${family.variants.length}'})
        : coverage != null && coverage.total > 0
            ? context.t('icons.coveredOfTotalApps', {
                'covered': '${coverage.covered.clamp(0, coverage.total)}',
                'total': '${coverage.total}',
              })
            : lead.summary;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => IconFamilyPage(familyId: family.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FamilyIcons(
                family: family,
                variant: lead,
                count: 10,
                columns: 5,
                size: 36,
                liveGeometry: _wornGeometry(actions, family),
              ),
              if (progress != null) ...[
                const SizedBox(height: 10),
                ThemedProgress.linear(value: progress <= 0 ? null : progress),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          family.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (applied)
                    const AppliedMark()
                  else if (packActionLabel(context, ref, lead, status)
                      case final label?)
                    StorePill(label, filled: status == CardStatus.locked),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
