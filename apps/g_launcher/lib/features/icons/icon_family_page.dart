/// One icon style on the store: your apps drawn in it, its colours, how much
/// of your phone it covers, and one button.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/billing/entitlements.dart';
import '../../data/cdn/pack_repository.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../design/components/components.dart';
import '../../engine/effective_theme.dart';
import '../../platform/pack_api.g.dart';
import '../themes/theme_catalog.dart' show CardStatus;
import 'icon_pack_actions.dart';
import 'icon_store_model.dart';
import 'icon_store_widgets.dart';
import 'icon_theme_screen.dart' show packCoverageProvider;

class IconFamilyPage extends ConsumerStatefulWidget {
  const IconFamilyPage({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<IconFamilyPage> createState() => _IconFamilyPageState();
}

class _IconFamilyPageState extends ConsumerState<IconFamilyPage> {
  /// The colour being looked at, by pack id. Null until the user picks one,
  /// which means "the one the card spoke for".
  String? _picked;

  @override
  Widget build(BuildContext context) {
    ref.watch(ownedSkusProvider);
    final theme = ref.watch(effectiveThemeProvider).value;
    final families = ref.watch(iconFamiliesProvider);
    final d = ChromeScope.of(context);
    final c = d.colors;

    IconFamily? family;
    for (final f in families) {
      if (f.id == widget.familyId) family = f;
    }
    if (theme == null || family == null) {
      return const ThemedScaffold(body: SizedBox.shrink());
    }
    final fam = family;
    final actions = IconPackActions(context, ref, theme);

    PackInfo? pick(bool Function(PackInfo) test) {
      for (final p in fam.variants) {
        if (test(p)) return p;
      }
      return null;
    }

    final variant = pick((p) => p.packId == _picked) ??
        pick(actions.isApplied) ??
        pick((p) => p.packId == actions.distroPack) ??
        fam.variants.first;

    final original = fam.kind == IconSetKind.line &&
        _picked == null &&
        theme.prefs.iconBrandPackId == kNoIconPack;
    final coverage = ref.watch(packCoverageProvider(variant.packId)).value;
    final progress = ref.watch(packProgressProvider)[variant.packId];

    return ThemedScaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                top: MediaQuery.viewPaddingOf(context).top,
                bottom: 16,
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: c.text),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                  child: Text(fam.title, style: d.text.display),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
                  child: Text(
                    context.t('icons.yourAppsIn', {'name': fam.title}),
                    style: TextStyle(fontSize: 12.5, color: c.textMuted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FamilyIcons(
                    family: fam,
                    variant: variant,
                    count: 16,
                    columns: 4,
                    size: 50,
                    labels: true,
                    liveGeometry: actions.appliedLine != null &&
                        brandFamilyOf(actions.appliedLine!) == fam.id,
                  ),
                ),
                if (fam.kind == IconSetKind.line && fam.variants.length > 1)
                  _Colours(
                    variants: fam.variants,
                    selected: original ? null : variant.packId,
                    actions: actions,
                    onPick: (id) => setState(() => _picked = id),
                  ),
                if (coverage != null && coverage.total > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Text(
                            context.t('icons.covers'),
                            style: TextStyle(fontSize: 14, color: c.text),
                          ),
                          const Spacer(),
                          Text(
                            context.t('icons.coveredOfTotalApps', {
                              'covered':
                                  '${coverage.covered.clamp(0, coverage.total)}',
                              'total': '${coverage.total}',
                            }),
                            style:
                                TextStyle(fontSize: 13.5, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ThemedProgress.linear(
                value: progress <= 0 ? null : progress,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              16 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: _Action(
              variant: variant,
              actions: actions,
              original: original,
            ),
          ),
        ],
      ),
    );
  }
}

/// The colour choices for the line family.
class _Colours extends ConsumerWidget {
  const _Colours({
    required this.variants,
    required this.selected,
    required this.actions,
    required this.onPick,
  });

  final List<PackInfo> variants;

  /// The pack id being looked at; null while the apps' own icons are worn.
  final String? selected;
  final IconPackActions actions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ChromeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Text(
              context.t('icons.colour'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textMuted,
              ),
            ),
          ),
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: variants.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final p = variants[i];
                final status = actions.statusOf(p);
                final owned = status != CardStatus.locked &&
                    status != CardStatus.requiresAppUpdate;
                return _Swatch(
                  color: tintColorOf(p) ?? c.text,
                  label: p.packId == actions.distroPack
                      ? context.t('icons.included')
                      : _shortName(p.title),
                  selected: p.packId == selected,
                  owned: owned,
                  onTap: () => onPick(p.packId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// "Kali Linux Icons" and "Kali Linux Bold" read as "Kali Linux" under a
  /// dot: the family is already the page's title.
  static String _shortName(String title) {
    for (final suffix in const [' Icons', ' Bold']) {
      if (title.endsWith(suffix)) {
        return title.substring(0, title.length - suffix.length);
      }
    }
    return title;
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.owned,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 60,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? c.text : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child:
                      owned ? Icon(Icons.check, size: 16, color: c.bg) : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? c.text : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page's single button, worded by the selected pack's state.
class _Action extends ConsumerWidget {
  const _Action({
    required this.variant,
    required this.actions,
    required this.original,
  });

  final PackInfo variant;
  final IconPackActions actions;

  /// The apps' own icons are being worn instead of any line colour.
  final bool original;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applied = !original && actions.isApplied(variant);
    final status = actions.statusOf(variant);

    // A Linux theme in use can be taken off; a line colour in use cannot,
    // because something has to be drawn under everything.
    if (applied && variant.packType == 'hero') {
      return ThemedButton(
        label: context.t('icons.remove'),
        kind: ThemedButtonKind.secondary,
        expand: true,
        onPressed: () => unawaited(actions.removeLinuxTheme()),
      );
    }
    if (applied) {
      return ThemedButton(
        label: context.t('icons.inUse'),
        kind: ThemedButtonKind.secondary,
        expand: true,
        onPressed: null,
      );
    }

    final label = switch (status) {
      CardStatus.locked => context.t('icons.buyFor', {
          'price': ref.watch(productPriceProvider(variant.sku)) ??
              context.t('themes.buy'),
        }),
      _ => packActionLabel(context, ref, variant, status) ??
          context.t('themes.apply'),
    };

    return ThemedButton(
      label: label,
      expand: true,
      onPressed: status == CardStatus.requiresAppUpdate
          ? null
          : () => unawaited(actions.choose(variant)),
    );
  }
}
