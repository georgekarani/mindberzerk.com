/// The icon store's catalogue, grouped the way the store sells it.
///
/// The signed index lists packs. The store sells STYLES: every line pack is
/// the same Arcticons drawing in a different colour, so the fifteen of them are
/// one product with a colour option (and Bold, Lawnicons rebranded, is a second
/// one), and each full-colour Linux icon theme
/// (Papirus and those after it) is a product of its own.
library;

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cdn/pack_repository.dart';
import '../../engine/effective_theme.dart';
import '../../platform/pack_api.g.dart';

/// How a family of icons is drawn, which is also how the store files it.
enum IconSetKind {
  /// Monochrome outlines over the app's own shape (Arcticons and its tints).
  line,

  /// A full-colour Linux icon theme with its own art (Papirus and peers).
  linux,
}

/// One product on the icon store: a style, and the packs that carry it.
class IconFamily {
  const IconFamily({
    required this.id,
    required this.title,
    required this.kind,
    required this.variants,
  });

  /// [kLineFamilyId] for the line family, otherwise the pack id.
  final String id;
  final String title;
  final IconSetKind kind;

  /// The packs, in display order. One for a Linux theme; for a tinted family
  /// the current distro's colour first, then the rest by name.
  final List<PackInfo> variants;
}

/// The Arcticons line family's id on the store.
const kLineFamilyId = 'line';

/// The Bold family's id on the store: Lawnicons, rebranded and sold as one
/// product in every distro colour.
const kBoldFamilyId = 'bold';

/// The untinted line pack every Line colour derives from.
const kLineBasePack = 'arcticons-line';

/// The untinted pack every Bold colour derives from.
const kBoldBasePack = 'g-bold';

/// The tinted families, by the suffix their pack ids share, with their bases.
/// A base is geometry with no colour of its own, so it is never a choice.
const _brandFamilies = <String, ({String suffix, String base})>{
  kLineFamilyId: (suffix: '-line', base: kLineBasePack),
  kBoldFamilyId: (suffix: '-bold', base: kBoldBasePack),
};

/// Which tinted family a brand pack belongs to, or null. `simple-icons` is
/// also a brand pack, but it is the glyph layer under everything.
String? brandFamilyOf(String packId) {
  for (final e in _brandFamilies.entries) {
    if (packId.endsWith(e.value.suffix)) return e.key;
  }
  return null;
}

/// Whether [p] is a choosable colour of a tinted family.
bool isChoosableBrand(PackInfo p) {
  if (p.packType != 'brand') return false;
  final family = brandFamilyOf(p.packId);
  return family != null && p.packId != _brandFamilies[family]!.base;
}

/// The line pack that comes with the distro being worn, if the index has it.
///
/// The theme's own `icons.brandPack` first, then the derived id, matching the
/// rule `EffectiveTheme` resolves with, so the store and the drawer agree on
/// what "included" means.
String? distroLinePackFor(EffectiveTheme theme, Iterable<PackInfo> catalogue) {
  final ids = {for (final p in catalogue) p.packId};
  for (final id in [
    theme.spec.icons.brandPack,
    defaultLinePackFor(theme.spec.id)
  ]) {
    if (id != null && id.isNotEmpty && ids.contains(id)) return id;
  }
  return null;
}

/// A pack's tint as a colour, or null when it has none or it does not parse.
Color? tintColorOf(PackInfo p) {
  final raw = (p.tint ?? '').replaceFirst('#', '');
  if (raw.length != 6) return null;
  final v = int.tryParse(raw, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// The store's products: Linux themes, then Line, then Bold.
final iconFamiliesProvider = Provider<List<IconFamily>>((ref) {
  final catalogue = ref.watch(catalogueProvider).value ?? const <PackInfo>[];
  final theme = ref.watch(effectiveThemeProvider).value;
  final own = theme == null ? null : distroLinePackFor(theme, catalogue);

  // The distro being worn first, then by name. Its Bold colour shares the
  // distro's base id: `kali-2024-theme` wears `kali-2024-line` and
  // `kali-2024-bold`.
  final specId = theme?.spec.id ?? '';
  final distroBase = specId.endsWith('-theme')
      ? specId.substring(0, specId.length - '-theme'.length)
      : specId;
  int rank(PackInfo p) =>
      p.packId == own || p.packId == '$distroBase-bold' ? 0 : 1;

  List<PackInfo> colours(String family) => [
        for (final p in catalogue)
          if (isChoosableBrand(p) && brandFamilyOf(p.packId) == family) p,
      ]..sort((a, b) {
          final r = rank(a).compareTo(rank(b));
          return r != 0
              ? r
              : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });

  String titleOf(String packId, String fallback) {
    for (final p in catalogue) {
      if (p.packId == packId && p.title.isNotEmpty) return p.title;
    }
    return fallback;
  }

  final lines = colours(kLineFamilyId);
  final bold = colours(kBoldFamilyId);

  final linux = [
    for (final p in catalogue)
      if (p.packType == 'hero') p,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  return [
    for (final p in linux)
      IconFamily(
        id: p.packId,
        title: p.title,
        kind: IconSetKind.linux,
        variants: [p],
      ),
    if (lines.isNotEmpty)
      IconFamily(
        id: kLineFamilyId,
        title: titleOf(kLineBasePack, 'Arcticons'),
        kind: IconSetKind.line,
        variants: lines,
      ),
    if (bold.isNotEmpty)
      IconFamily(
        id: kBoldFamilyId,
        title: titleOf(kBoldBasePack, 'Bold'),
        kind: IconSetKind.line,
        variants: bold,
      ),
  ];
});
