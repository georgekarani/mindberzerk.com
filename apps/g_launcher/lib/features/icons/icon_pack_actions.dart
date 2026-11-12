/// What choosing an icon pack does, in one place, so the store card, the pack
/// page and Settings cannot disagree about it.
///
/// Two prefs, and they LAYER rather than compete:
///   iconBrandPackId  the line pack (null means the distro's own)
///   iconPackId       a full-colour Linux theme drawn above it
/// A Linux theme covers the apps it has art for and the line pack fills the
/// rest, so choosing one never clears the other.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/billing/entitlements.dart';
import '../../data/cdn/pack_repository.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../design/branded_message.dart';
import '../../engine/effective_theme.dart';
import '../../platform/pack_api.g.dart';
import '../themes/theme_catalog.dart' show CardStatus;
import 'icon_store_model.dart';

class IconPackActions {
  IconPackActions(this.context, this.ref, this.theme);

  final BuildContext context;
  final WidgetRef ref;
  final EffectiveTheme theme;

  List<PackInfo> get _catalogue =>
      ref.read(catalogueProvider).value ?? const <PackInfo>[];

  /// The line pack that comes with the distro being worn.
  String? get distroPack => distroLinePackFor(theme, _catalogue);

  /// The line pack in use: the user's choice, else the distro's own. Null when
  /// the user chose the apps' original icons.
  String? get appliedLine {
    final chosen = theme.prefs.iconBrandPackId;
    if (chosen == kNoIconPack) return null;
    return chosen ?? distroPack;
  }

  bool isApplied(PackInfo p) => p.packType == 'brand'
      ? appliedLine == p.packId
      : theme.prefs.iconPackId == p.packId;

  /// The pack's state, with the distro's own line pack counted as owned: it
  /// comes with the distro and resolves without a purchase.
  CardStatus statusOf(PackInfo p) {
    final included = p.packId == distroPack;
    final status = CardStatus.parse(
      p.state,
      unlocked: p.unlocked || included,
      free: p.sku == null,
    );
    return included && status == CardStatus.locked
        ? CardStatus.installed
        : status;
  }

  void _say(String key, PackInfo p) =>
      context.showMessage(context.t(key, {'name': p.title}));

  /// Wear [p]. The distro's own line pack is the default, so choosing it
  /// clears the override instead of pinning it.
  Future<void> apply(PackInfo p) {
    final prefs = ref.read(prefsProvider(theme.spec.id).notifier);
    if (p.packType == 'brand') {
      if (p.packId == distroPack) {
        return prefs.edit((prev) => prev.clearing(iconBrandPackId: true));
      }
      return prefs.edit((prev) => prev.copyWith(iconBrandPackId: p.packId));
    }
    return prefs.edit((prev) => prev.copyWith(iconPackId: p.packId));
  }

  /// Draw every app with its own icon, no line pack.
  Future<void> useOriginalIcons() => ref
      .read(prefsProvider(theme.spec.id).notifier)
      .edit((prev) => prev.copyWith(iconBrandPackId: kNoIconPack));

  /// Stop drawing a Linux theme over the line pack.
  Future<void> removeLinuxTheme() => ref
      .read(prefsProvider(theme.spec.id).notifier)
      .edit((prev) => prev.clearing(iconPackId: true));

  /// Use an icon pack installed from Play, or none.
  Future<void> chooseSystemPack(String? packageName) =>
      ref.read(prefsProvider(theme.spec.id).notifier).edit(
            (prev) => packageName == null
                ? prev.clearing(systemIconPack: true)
                : prev.copyWith(systemIconPack: packageName),
          );

  Future<void> download(PackInfo p, {required bool thenApply}) async {
    final result = await ref.read(packActionsProvider).install(p.packId);
    if (!context.mounted) return;

    switch (result.status) {
      case 'installed':
        if (thenApply) {
          await apply(p);
          if (context.mounted) _say('themes.msg.applied', p);
        } else {
          _say('themes.msg.updated', p);
        }
      case 'upToDate' || 'cancelled':
        break;
      case 'notEntitled':
        _say('icons.needsPurchaseFirst', p);
      case 'appTooOld':
        _say('themes.msg.needsAppUpdate', p);
      case 'noSpace':
        _say('icons.notEnoughFreeSpace', p);
      case 'rejected':
        _say('icons.failedVerification', p);
      default:
        _say('icons.couldNotDownload', p);
    }
  }

  /// The one action a pack's button performs, by its state.
  Future<void> choose(PackInfo p) async {
    if (isApplied(p)) {
      _say('icons.alreadyYourIconTheme', p);
      return;
    }
    switch (statusOf(p)) {
      case CardStatus.bundled || CardStatus.installed:
        await apply(p);
        if (context.mounted) _say('themes.msg.applied', p);
      case CardStatus.updateAvailable:
        await apply(p);
        await download(p, thenApply: false);
      case CardStatus.available:
        await download(p, thenApply: true);
      case CardStatus.locked:
        final started = await ref.read(buyProvider)(p.sku!);
        if (!started && context.mounted) _say('icons.notAvailableToBuy', p);
      case CardStatus.requiresAppUpdate:
        _say('themes.msg.needsAppUpdate', p);
    }
  }
}
