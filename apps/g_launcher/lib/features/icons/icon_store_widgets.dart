/// Pieces the icon store and the pack page share.
library;

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/billing/entitlements.dart';
import '../../data/cdn/pack_preview_url.dart';
import '../../data/repositories/app_repository.dart';
import '../../design/components/components.dart';
import '../../platform/launcher_api.g.dart';
import '../../platform/pack_api.g.dart';
import '../themes/theme_catalog.dart' show CardStatus;
import 'icon_preview.dart';
import 'icon_store_model.dart';

/// A rounded word or price: accent-filled for the one state that costs money,
/// surface for Get, Apply and Update.
class StorePill extends StatelessWidget {
  const StorePill(this.text, {super.key, this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? c.accent : c.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: filled ? c.onAccent : c.text,
        ),
      ),
    );
  }
}

/// The small "this is what you are wearing" mark.
class AppliedMark extends StatelessWidget {
  const AppliedMark({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(Icons.check, size: 14, color: c.onAccent),
    );
  }
}

/// The label for a pack's single action, or null when there is nothing to do.
String? packActionLabel(
  BuildContext context,
  WidgetRef ref,
  PackInfo p,
  CardStatus status,
) =>
    switch (status) {
      CardStatus.locked => ref.watch(productPriceProvider(p.sku)) ??
          context.t('themes.buy'),
      CardStatus.available => context.t('themes.get'),
      CardStatus.updateAvailable => context.t('themes.update'),
      CardStatus.bundled || CardStatus.installed => context.t('themes.apply'),
      CardStatus.requiresAppUpdate => context.t('themes.updateApp'),
    };

/// A family drawn with this phone's own apps.
///
/// A tinted family is one geometry plus a colour, so native renders the user's
/// first [count] apps in the chosen tint before anything is bought. Native can
/// only draw the geometry it has LOADED, which is the family being worn, so
/// any other family ([liveGeometry] false) and every Linux theme shows its
/// published preview.png instead, falling back to the live render when a pack
/// was published without one.
class FamilyIcons extends ConsumerWidget {
  const FamilyIcons({
    super.key,
    required this.family,
    required this.variant,
    required this.count,
    required this.columns,
    required this.size,
    this.labels = false,
    this.liveGeometry = true,
  });

  final IconFamily family;
  final PackInfo? variant;
  final int count;
  final int columns;
  final double size;

  /// Show each app's name under its icon (the pack page does, cards do not).
  final bool labels;

  /// Whether this family's geometry is the one native has loaded.
  final bool liveGeometry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ChromeScope.of(context).colors;
    final v = variant ?? family.variants.first;

    if (family.kind == IconSetKind.linux) {
      return _PreviewImage(packId: v.packId, height: size * 2.6);
    }
    if (!liveGeometry) {
      return _PreviewImage(
        packId: v.packId,
        height: size * 2.6,
        fallback: FamilyIcons(
          family: family,
          variant: v,
          count: count,
          columns: columns,
          size: size,
          labels: labels,
        ),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final tint = v.tint ?? previewHexOf(c.text);
    final bytes = ref
            .watch(
              iconPreviewProvider(
                (tint: tint, sizePx: (size * dpr).round(), count: count),
              ),
            )
            .value ??
        const <Uint8List?>[];
    final apps = (ref.watch(appListProvider).value ?? const <AppEntry>[])
        .take(count)
        .toList();

    Widget cell(int i) {
      final b = i < bytes.length ? bytes[i] : null;
      final icon = SizedBox(
        width: size,
        height: size,
        child: b == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(size * 0.3),
                ),
              )
            : Image.memory(b, fit: BoxFit.contain, gaplessPlayback: true),
      );
      if (!labels) return icon;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 6),
          Text(
            i < apps.length ? apps[i].label : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.textMuted),
          ),
        ],
      );
    }

    final shown = apps.isEmpty ? count : apps.length;
    final rows = (shown / columns).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows; r++)
          Padding(
            padding: EdgeInsets.only(top: r == 0 ? 0 : (labels ? 16 : 12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var col = 0; col < columns; col++)
                  SizedBox(
                    width: labels ? size + 20 : size,
                    child: r * columns + col < shown
                        ? Center(child: cell(r * columns + col))
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A pack's published preview.png, installed copy first, CDN otherwise.
class _PreviewImage extends ConsumerWidget {
  const _PreviewImage({
    required this.packId,
    required this.height,
    this.fallback,
  });

  final String packId;
  final double height;

  /// Drawn instead when the pack has no preview.png.
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(packPreviewUrlProvider(packId)).value;
    final ImageProvider? image = url == null
        ? null
        : url.startsWith('file://')
            ? FileImage(File(url.substring('file://'.length)))
            : NetworkImage(url);
    if (image == null && fallback != null) return fallback!;
    return SizedBox(
      height: height,
      child: image == null
          ? null
          : Image(
              image: image,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  fallback ?? const SizedBox.shrink(),
            ),
    );
  }
}
