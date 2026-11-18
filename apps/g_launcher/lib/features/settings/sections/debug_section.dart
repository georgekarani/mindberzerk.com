/// Debug builds only: unlock paid distros to test them.
///
/// Reached from a group on the Settings landing that exists only under
/// [kDebugMode], so a release build has no way in. The unlocks themselves
/// are inert outside debug too; see `debug_unlocks.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../../data/billing/bundle_offer.dart' show kAllDistrosSku;
import '../../../data/billing/debug_unlocks.dart';
import '../../../data/cdn/pack_repository.dart';
import '../../../engine/effective_theme.dart';
import '../../../design/components/components.dart';
import '../../terminal/terminal_entitlement.dart' show kTerminalProSku;
import '../../themes/theme_actions.dart' show runThemeCardAction;
import '../../themes/theme_catalog.dart';
import '../settings_rows.dart';

List<Widget> debugSection(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
  int workspaces,
  String q,
) {
  if (!kDebugMode) return const <Widget>[];

  final unlocked = ref.watch(debugUnlocksProvider);
  final notifier = ref.read(debugUnlocksProvider.notifier);
  final all = unlocked.contains(kAllDistrosSku);

  // Every paid DISTRO in the signed catalogue, by its own SKU. Icon packs ride
  // along with "all", which is the bundle SKU and grants them natively.
  final packs = ref.watch(catalogueProvider).asData?.value ?? const [];
  final paid = [
    for (final p in packs)
      if (p.packType == 'theme' && (p.sku ?? '').isNotEmpty) p,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  // Every distro, for the quick-apply grid below.
  final cards =
      ref.watch(themeCatalogProvider).asData?.value ?? const <ThemeCard>[];

  return [
    // ─── APPLY ANY DISTRO FROM ONE SCREEN ─────────────────────────────────
    //
    // A wrap of small buttons rather than the store's tall cards, so all of
    // them fit on one screen and a test pass is one tap per distro. Each goes
    // through the store's own action: download, install and apply exactly as
    // the Apply button does, so nothing here is a shortcut around that path.
    if (cards.isNotEmpty)
      Padding(
        key: const ValueKey('debug.apply'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cards)
              ThemedButton(
                label: c.name,
                kind: ThemedButtonKind.secondary,
                onPressed: () => runThemeCardAction(context, ref, c),
              ),
          ],
        ),
      ),
    SettingsGroup(
      key: const ValueKey('debug.unlock'),
      label: context.t('debug.unlock'),
      rows: [
        FilterRow(
          const ['unlock', 'all', 'distros', 'icons'],
          SettingsToggleRow(
            icon: Icons.lock_open_outlined,
            accent: true,
            title: context.t('debug.unlockAll'),
            value: all,
            onChanged: (on) => notifier.set(kAllDistrosSku, on),
          ),
        ),
        FilterRow(
          const ['terminal', 'pro', 'ssh'],
          SettingsToggleRow(
            icon: Icons.terminal,
            title: context.t('debug.terminalPro'),
            value: unlocked.contains(kTerminalProSku),
            onChanged: (on) => notifier.set(kTerminalProSku, on),
          ),
        ),
      ],
    ),
    if (paid.isNotEmpty)
      SettingsGroup(
        key: const ValueKey('debug.distros'),
        label: context.t('debug.distros'),
        rows: [
          for (final p in paid)
            FilterRow(
              [p.title],
              SettingsToggleRow(
                icon: Icons.desktop_windows_outlined,
                title: p.title,
                // Shown on, and inert, while "all" already covers it.
                value: all || unlocked.contains(p.sku),
                enabled: !all,
                onChanged: (on) => notifier.set(p.sku!, on),
              ),
            ),
        ],
      ),
  ];
}
