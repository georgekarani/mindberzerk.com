import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/pack_api.g.dart';
import '../cdn/pack_repository.dart';
import 'entitlements.dart';

/// The one bundle the storefront sells: every paid distro and icon pack.
///
/// Named here, not discovered, because it is the only bundle with a paywall of
/// its own. The per-distro bundles in the index (`distro_kali` granting the
/// theme and its icons) are how a single purchase covers two packs; they are
/// not offers and must never be shown as one.
const kAllDistrosSku = 'bundle_all_distros';

/// What the paywall needs to show the all-distros bundle.
///
/// Every figure on it is read, never estimated: counts come from the signed
/// grants, prices from Play, and [worth] is null whenever a single price is
/// missing rather than a total that quietly leaves something out.
class BundleOffer {
  const BundleOffer({
    required this.sku,
    required this.title,
    required this.grantsAll,
    required this.grants,
    required this.distroCount,
    required this.iconPackCount,
    required this.owned,
    this.price,
    this.worth,
  });

  final String sku;
  final String title;
  final bool grantsAll;
  final Set<String> grants;

  /// Paid distro themes the bundle unlocks.
  final int distroCount;

  /// Icon packs the bundle unlocks, including those sold on their own.
  final int iconPackCount;

  final bool owned;

  /// Play's localised price. Null until Play answers.
  final String? price;

  /// The sum of every granted distro's own price, in the same currency and
  /// format as [price]. Null unless every price is loaded and the total is
  /// higher than the bundle's.
  final String? worth;

  /// Whether buying this unlocks [packId].
  bool covers(String packId) => grantsAll || grants.contains(packId);
}

/// The all-distros offer, or null when the signed index does not carry it.
///
/// Ownership is read from the live Play set as well as from the index, because
/// [bundlesProvider] is a snapshot of native's answer and does not re-run when
/// a purchase lands; the banner must disappear the moment the bundle is owned.
final allDistrosOfferProvider = Provider<BundleOffer?>((ref) {
  final bundles = ref.watch(bundlesProvider).value;
  if (bundles == null) return null;

  BundleInfo? found;
  for (final b in bundles) {
    if (b.sku == kAllDistrosSku) found = b;
  }
  if (found == null) return null;
  final bundle = found;

  final packs = ref.watch(catalogueProvider).value ?? const <PackInfo>[];
  final ownedSkus = ref.watch(ownedSkusProvider).value ?? const <String>{};
  final products = ref.watch(entitlementServiceProvider).products;

  final grants = bundle.grantedPackIds.toSet();
  bool covered(PackInfo p) => bundle.grantsAll || grants.contains(p.packId);

  var distros = 0;
  var icons = 0;
  final distroSkus = <String>{};
  for (final p in packs) {
    if (!covered(p) || p.sku == null || p.sku!.isEmpty) continue;
    if (p.packType == 'theme') {
      distros++;
      distroSkus.add(p.sku!);
    } else {
      icons++;
    }
  }

  final own = products[kAllDistrosSku];
  String? worth;
  if (own != null && distroSkus.isNotEmpty) {
    var total = 0.0;
    var complete = true;
    for (final sku in distroSkus) {
      final p = products[sku];
      if (p == null) {
        complete = false;
        break;
      }
      total += p.rawPrice;
    }
    if (complete && total > own.rawPrice) {
      worth = formatLikePrice(own.price, own.rawPrice, total);
    }
  }

  return BundleOffer(
    sku: bundle.sku,
    title: bundle.title,
    grantsAll: bundle.grantsAll,
    grants: grants,
    distroCount: distros,
    iconPackCount: icons,
    owned: bundle.owned || ownedSkus.contains(kAllDistrosSku),
    price: own?.price,
    worth: worth,
  );
});

/// Formats [amount] the way Play formatted [template] for [templateRaw].
///
/// Play hands back a finished string per product ("MX$279.00", "R$ 71,99",
/// "COP 42.500") and no formatter. A sum has no such string, so this reads the
/// separators and the number of decimals off the bundle's own price and reuses
/// them, keeping symbol and placement exactly as Play wrote them. Returns null
/// when the template cannot be read unambiguously; the caller then shows no
/// total rather than a wrongly formatted one.
String? formatLikePrice(String template, double templateRaw, double amount) {
  final match = RegExp(r'\d(?:[\d.,\s  ]*\d)?').firstMatch(template);
  if (match == null) return null;
  final run = match.group(0)!;
  final digits = int.tryParse(run.replaceAll(RegExp(r'\D'), ''));
  if (digits == null) return null;

  // The decimals are whatever count makes the digit string equal the raw
  // price: 1299 for 12.99 is two, 42500 for 42500.0 is none.
  int? decimals;
  var scale = 1;
  for (var d = 0; d <= 3; d++) {
    if ((templateRaw * scale).round() == digits) {
      decimals = d;
      break;
    }
    scale *= 10;
  }
  if (decimals == null) return null;

  final decimalSep = decimals > 0 ? run[run.length - decimals - 1] : '';
  final wholeRun =
      decimals > 0 ? run.substring(0, run.length - decimals - 1) : run;
  final groupMatch = RegExp(r'\D').firstMatch(wholeRun);
  final groupSep = groupMatch?.group(0) ?? (decimalSep == ',' ? '.' : ',');

  final fixed = amount.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0];
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(groupSep);
    grouped.write(whole[i]);
  }
  final number = decimals > 0 ? '$grouped$decimalSep${parts[1]}' : '$grouped';
  return template.replaceRange(match.start, match.end, number);
}
