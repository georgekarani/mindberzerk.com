import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/content/content_store.dart';
import 'bench_result.dart';

/// A phone on the ladder, from public results: Geekbench 7 for the
/// processor, 3DMark Wild Life Extreme for graphics. Geekbench's own graphics
/// test measures compute and ranks phones against how they play games, so
/// it is not used.
@immutable
class LadderPhone {
  const LadderPhone({
    required this.name,
    required this.chip,
    required this.lenses,
    required this.gbSingle,
    required this.gbMulti,
    required this.wildLifeExtreme,
  });

  /// Null when a field is missing or out of range, so one bad row is dropped
  /// rather than the whole list.
  static LadderPhone? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final Object? name = raw['name'];
    final Object? chip = raw['chip'];
    final Object? lenses = raw['lenses'];
    final Object? single = raw['gbSingle'];
    final Object? multi = raw['gbMulti'];
    final Object? wle = raw['wildLifeExtreme'];
    if (name is! String || name.isEmpty || chip is! String) return null;
    if (lenses is! num || single is! num || multi is! num || wle is! num) {
      return null;
    }
    if (single <= 0 || multi <= 0 || wle <= 0) return null;
    return LadderPhone(
      name: name,
      chip: chip,
      lenses: lenses.toInt().clamp(1, 4),
      gbSingle: single.toInt(),
      gbMulti: multi.toInt(),
      wildLifeExtreme: wle.toInt(),
    );
  }

  final String name;
  final String chip;

  /// Rear camera count, for the phone's drawing.
  final int lenses;

  final int gbSingle;
  final int gbMulti;
  final int wildLifeExtreme;
}

/// The pyramid, from the top. The cut-offs live on [Ladder] so the admin
/// can move them; these are only names and letters.
enum BenchTier {
  s('S', 'Flagship'),
  a('A', 'Upper class'),
  b('B', 'Mid range'),
  c('C', 'Entry level'),
  d('D', 'Basic');

  const BenchTier(this.letter, this.label);

  final String letter;
  final String label;
}

/// Everything the ranking needs: the phones, the anchor that converts their
/// public scores to this app's scale, and the tier cut-offs. Published from
/// the admin as the `bench-ladder` pack; [fallback] is the copy built in.
@immutable
class Ladder {
  const Ladder({
    required this.reference,
    required this.phones,
    this.cuts = const <double>[2300, 1500, 950, 600],
  });

  /// From the pack. Falls back to the built-in copy when the document is
  /// missing, malformed or would leave nothing to show.
  factory Ladder.fromJson(Map<String, Object?> json) {
    final LadderPhone? reference = LadderPhone.fromJson(json['reference']);
    final Object? rawPhones = json['phones'];
    final List<LadderPhone> phones = <LadderPhone>[
      if (rawPhones is List<Object?>)
        for (final Object? p in rawPhones)
          if (LadderPhone.fromJson(p) case final LadderPhone phone) phone,
    ];
    if (reference == null || phones.isEmpty) return fallback;

    final Object? tiers = json['tiers'];
    List<double> cuts = fallback.cuts;
    if (tiers is Map<String, Object?>) {
      final List<Object?> raw = <Object?>[
        tiers['s'],
        tiers['a'],
        tiers['b'],
        tiers['c'],
      ];
      if (raw.every((Object? v) => v is num)) {
        final List<double> next = <double>[
          for (final Object? v in raw) (v! as num).toDouble(),
        ];
        // Strictly falling, or the pyramid cannot be drawn.
        bool falling = next.last > 0;
        for (int i = 1; i < next.length; i++) {
          falling = falling && next[i] < next[i - 1];
        }
        if (falling) cuts = next;
      }
    }
    return Ladder(reference: reference, phones: phones, cuts: cuts);
  }

  /// The phone that scores 1000 in this app, measured on the same public
  /// tests. Shown in the list beside the others.
  final LadderPhone reference;

  final List<LadderPhone> phones;

  /// Lowest index for S, A, B and C; anything below is D.
  final List<double> cuts;

  /// Every phone to list, the reference included.
  List<LadderPhone> get all => <LadderPhone>[reference, ...phones];

  double processorOf(LadderPhone p) =>
      math.sqrt(
        p.gbSingle / reference.gbSingle * (p.gbMulti / reference.gbMulti),
      ) *
      1000;

  double graphicsOf(LadderPhone p) =>
      p.wildLifeExtreme / reference.wildLifeExtreme * 1000;

  /// A phone's place on this app's scale.
  double indexOf(LadderPhone p) =>
      benchIndex(processor: processorOf(p), graphics: graphicsOf(p));

  BenchTier tierOf(double index) {
    for (int i = 0; i < cuts.length; i++) {
      if (index >= cuts[i]) return BenchTier.values[i];
    }
    return BenchTier.d;
  }

  /// The list built into the app. Geekbench 7 chart averages from
  /// browser.geekbench.com/android-benchmarks and 3DMark Wild Life Extreme
  /// from benchmarks.ul.com, both read 20 Nov 2026. The reference is a
  /// Galaxy S22+ run the same day, the chip this app scores as 1000.
  static const Ladder fallback = Ladder(
    reference: LadderPhone(
      name: 'Galaxy S22+',
      chip: 'Snapdragon 8 Gen 1',
      lenses: 3,
      gbSingle: 913,
      gbMulti: 2951,
      wildLifeExtreme: 2416,
    ),
    phones: <LadderPhone>[
      LadderPhone(
        name: 'vivo iQOO 15',
        chip: 'Snapdragon 8 Elite Gen 5',
        lenses: 3,
        gbSingle: 2487,
        gbMulti: 8846,
        wildLifeExtreme: 6752,
      ),
      LadderPhone(
        name: 'Honor Magic8 Pro',
        chip: 'Snapdragon 8 Elite Gen 5',
        lenses: 3,
        gbSingle: 2036,
        gbMulti: 7746,
        wildLifeExtreme: 7466,
      ),
      LadderPhone(
        name: 'Galaxy S25 Ultra',
        chip: 'Snapdragon 8 Elite',
        lenses: 4,
        gbSingle: 2474,
        gbMulti: 8890,
        wildLifeExtreme: 5827,
      ),
      LadderPhone(
        name: 'vivo X300 Pro',
        chip: 'Dimensity 9500',
        lenses: 3,
        gbSingle: 2121,
        gbMulti: 7912,
        wildLifeExtreme: 6708,
      ),
      LadderPhone(
        name: 'Galaxy Z Fold7',
        chip: 'Snapdragon 8 Elite',
        lenses: 3,
        gbSingle: 2408,
        gbMulti: 8455,
        wildLifeExtreme: 4885,
      ),
      LadderPhone(
        name: 'OnePlus 15',
        chip: 'Snapdragon 8 Elite Gen 5',
        lenses: 3,
        gbSingle: 1849,
        gbMulti: 7800,
        wildLifeExtreme: 6374,
      ),
      LadderPhone(
        name: 'Xiaomi 15',
        chip: 'Snapdragon 8 Elite',
        lenses: 3,
        gbSingle: 1823,
        gbMulti: 7589,
        wildLifeExtreme: 5782,
      ),
      LadderPhone(
        name: 'OnePlus 13',
        chip: 'Snapdragon 8 Elite',
        lenses: 3,
        gbSingle: 1259,
        gbMulti: 5904,
        wildLifeExtreme: 6241,
      ),
      LadderPhone(
        name: 'Galaxy S24 Ultra',
        chip: 'Snapdragon 8 Gen 3',
        lenses: 4,
        gbSingle: 1789,
        gbMulti: 6188,
        wildLifeExtreme: 4531,
      ),
      LadderPhone(
        name: 'Pixel 10',
        chip: 'Tensor G5',
        lenses: 3,
        gbSingle: 1900,
        gbMulti: 5383,
        wildLifeExtreme: 3118,
      ),
      LadderPhone(
        name: 'Poco F7',
        chip: 'Snapdragon 8s Gen 4',
        lenses: 2,
        gbSingle: 1237,
        gbMulti: 4721,
        wildLifeExtreme: 4204,
      ),
      LadderPhone(
        name: 'Galaxy S23',
        chip: 'Snapdragon 8 Gen 2',
        lenses: 3,
        gbSingle: 1568,
        gbMulti: 4572,
        wildLifeExtreme: 3566,
      ),
      LadderPhone(
        name: 'Nothing Phone (2)',
        chip: 'Snapdragon 8+ Gen 1',
        lenses: 2,
        gbSingle: 1400,
        gbMulti: 4137,
        wildLifeExtreme: 2649,
      ),
      LadderPhone(
        name: 'Pixel 9',
        chip: 'Tensor G4',
        lenses: 2,
        gbSingle: 1390,
        gbMulti: 3794,
        wildLifeExtreme: 2598,
      ),
      LadderPhone(
        name: 'Pixel 9a',
        chip: 'Tensor G4',
        lenses: 2,
        gbSingle: 1385,
        gbMulti: 3719,
        wildLifeExtreme: 2625,
      ),
      LadderPhone(
        name: 'Pixel 8',
        chip: 'Tensor G3',
        lenses: 2,
        gbSingle: 1311,
        gbMulti: 3488,
        wildLifeExtreme: 2417,
      ),
      LadderPhone(
        name: 'Galaxy A56',
        chip: 'Exynos 1580',
        lenses: 3,
        gbSingle: 1158,
        gbMulti: 3695,
        wildLifeExtreme: 1322,
      ),
      LadderPhone(
        name: 'Galaxy A55',
        chip: 'Exynos 1480',
        lenses: 3,
        gbSingle: 949,
        gbMulti: 3239,
        wildLifeExtreme: 982,
      ),
      LadderPhone(
        name: 'Galaxy A36',
        chip: 'Snapdragon 6 Gen 3',
        lenses: 3,
        gbSingle: 849,
        gbMulti: 2809,
        wildLifeExtreme: 904,
      ),
      LadderPhone(
        name: 'Galaxy A15',
        chip: 'Helio G99',
        lenses: 3,
        gbSingle: 634,
        gbMulti: 1891,
        wildLifeExtreme: 337,
      ),
      LadderPhone(
        name: 'Redmi Note 13',
        chip: 'Dimensity 6080',
        lenses: 3,
        gbSingle: 598,
        gbMulti: 1803,
        wildLifeExtreme: 369,
      ),
    ],
  );
}

/// The ranking: the published pack when one is installed, the built-in
/// copy otherwise. Never empty and never waits on the network.
final FutureProvider<Ladder> benchLadderProvider = FutureProvider<Ladder>((
  Ref ref,
) async {
  final Map<String, Object?> json = await ref
      .watch(contentStoreProvider)
      .readJson(ContentStore.benchLadder);
  return json.isEmpty ? Ladder.fallback : Ladder.fromJson(json);
});

/// The ladder to draw right now, never null.
Ladder ladderOf(WidgetRef ref) =>
    ref.watch(benchLadderProvider).value ?? Ladder.fallback;
