import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One benchmark run. Every score is relative to a Galaxy S22 at 1000, so
/// 1500 means half as fast again and 500 means half the speed.
@immutable
class BenchResult {
  const BenchResult({
    required this.at,
    required this.device,
    required this.single,
    required this.multi,
    required this.gpu,
    required this.memory,
    required this.storage,
    required this.memoryGbs,
    required this.writeMbs,
    required this.cores,
    this.gpuFps,
    this.readMbs,
    this.tempStart,
    this.tempEnd,
    this.refreshRate,
  });

  /// From the native engine's map and the graphics test run in Flutter.
  factory BenchResult.fromEngine(
    Map<Object?, Object?> raw, {
    required String device,
    required double gpu,
    double? gpuFps,
    double? refreshRate,
  }) => BenchResult(
    at: DateTime.fromMillisecondsSinceEpoch((raw['at']! as num).toInt()),
    device: device,
    single: (raw['single']! as num).toDouble(),
    multi: (raw['multi']! as num).toDouble(),
    gpu: gpu,
    gpuFps: gpuFps,
    memory: (raw['memory']! as num).toDouble(),
    storage: (raw['storage']! as num).toDouble(),
    memoryGbs: (raw['memoryGbs']! as num).toDouble(),
    writeMbs: (raw['writeMbs']! as num).toDouble(),
    readMbs: (raw['readMbs'] as num?)?.toDouble(),
    cores: (raw['cores']! as num).toInt(),
    tempStart: (raw['tempStart'] as num?)?.toDouble(),
    tempEnd: (raw['tempEnd'] as num?)?.toDouble(),
    refreshRate: refreshRate,
  );

  factory BenchResult.fromJson(Map<String, Object?> j) => BenchResult(
    at: DateTime.fromMillisecondsSinceEpoch((j['at']! as num).toInt()),
    device: j['device']! as String,
    single: (j['single']! as num).toDouble(),
    multi: (j['multi']! as num).toDouble(),
    gpu: (j['gpu']! as num).toDouble(),
    gpuFps: (j['gpuFps'] as num?)?.toDouble(),
    memory: (j['memory']! as num).toDouble(),
    storage: (j['storage']! as num).toDouble(),
    memoryGbs: (j['memoryGbs']! as num).toDouble(),
    writeMbs: (j['writeMbs']! as num).toDouble(),
    readMbs: (j['readMbs'] as num?)?.toDouble(),
    cores: (j['cores']! as num).toInt(),
    tempStart: (j['tempStart'] as num?)?.toDouble(),
    tempEnd: (j['tempEnd'] as num?)?.toDouble(),
    refreshRate: (j['refreshRate'] as num?)?.toDouble(),
  );

  final DateTime at;
  final String device;
  final double single;
  final double multi;
  final double gpu;
  final double? gpuFps;
  final double memory;
  final double storage;
  final double memoryGbs;
  final double writeMbs;
  final double? readMbs;
  final int cores;
  final double? tempStart;
  final double? tempEnd;
  final double? refreshRate;

  /// Processor on one core and on all of them together.
  double get processor => math.sqrt(single * multi);

  /// The headline: processor and graphics, the same mix the public ladder
  /// uses, so this phone lands on it fairly. Memory and storage are shown
  /// on their own.
  double get total => benchIndex(processor: processor, graphics: gpu);

  /// Degrees the battery rose during the run, when both ends were read.
  double? get heatRise =>
      tempStart == null || tempEnd == null ? null : tempEnd! - tempStart!;

  /// Bumped whenever the reference phone's numbers or the tests change, so
  /// runs on an old scale are never compared with new ones.
  static const int scale = 4;

  Map<String, Object?> toJson() => <String, Object?>{
    'scale': scale,
    'at': at.millisecondsSinceEpoch,
    'device': device,
    'single': single,
    'multi': multi,
    'gpu': gpu,
    'gpuFps': gpuFps,
    'memory': memory,
    'storage': storage,
    'memoryGbs': memoryGbs,
    'writeMbs': writeMbs,
    'readMbs': readMbs,
    'cores': cores,
    'tempStart': tempStart,
    'tempEnd': tempEnd,
    'refreshRate': refreshRate,
  };

  static String encodeAll(List<BenchResult> runs) =>
      jsonEncode(<Object?>[for (final BenchResult r in runs) r.toJson()]);

  static List<BenchResult> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const <BenchResult>[];
    try {
      return <BenchResult>[
        for (final Object? e in jsonDecode(raw) as List<Object?>)
          if (e is Map<Object?, Object?> && e['scale'] == scale)
            BenchResult.fromJson(e.cast<String, Object?>()),
      ];
    } on Object {
      return const <BenchResult>[];
    }
  }
}

/// One number for a phone from its processor and graphics, both relative
/// to a Galaxy S22 at 1000. Used for this phone and for the ladder alike.
double benchIndex({required double processor, required double graphics}) =>
    processor * 0.6 + graphics * 0.4;

/// How good a category is, in words and in a level the UI colours by.
enum BenchLevel { great, good, fair, weak }

/// One line of what a figure means for using the phone.
@immutable
class BenchMeaning {
  const BenchMeaning(this.level, this.line);

  final BenchLevel level;
  final String line;
}

/// Turns scores into plain sentences. Every threshold lives here, so tuning
/// what "fast" means is one edit.
abstract final class BenchMeanings {
  static BenchLevel _level(double score) => score >= 1800
      ? BenchLevel.great
      : score >= 900
      ? BenchLevel.good
      : score >= 450
      ? BenchLevel.fair
      : BenchLevel.weak;

  static BenchMeaning single(double s) =>
      BenchMeaning(_level(s), switch (_level(s)) {
        BenchLevel.great => 'Apps open instantly',
        BenchLevel.good => 'Apps open quickly',
        BenchLevel.fair => 'Apps take a moment to open',
        BenchLevel.weak => 'Apps open slowly',
      });

  static BenchMeaning multi(double s) =>
      BenchMeaning(_level(s), switch (_level(s)) {
        BenchLevel.great => 'Video editing and many apps at once run smoothly',
        BenchLevel.good => 'Handles many open apps well',
        BenchLevel.fair => 'Slows down with many apps open',
        BenchLevel.weak => 'Struggles with more than a few apps open',
      });

  /// Graphics decides games, so this line is about games.
  static BenchMeaning gpu(double s) =>
      BenchMeaning(_level(s), switch (_level(s)) {
        BenchLevel.great => 'Plays the newest games on high settings',
        BenchLevel.good => 'Plays most games smoothly',
        BenchLevel.fair => 'Heavy games need low settings',
        BenchLevel.weak => 'Only light games run smoothly',
      });

  static BenchMeaning memory(double gbs) {
    final BenchLevel level = gbs >= 22
        ? BenchLevel.great
        : gbs >= 12
        ? BenchLevel.good
        : gbs >= 6
        ? BenchLevel.fair
        : BenchLevel.weak;
    return BenchMeaning(level, switch (level) {
      BenchLevel.great => 'Big photos and games load at once',
      BenchLevel.good => 'Photos and games load at a normal pace',
      BenchLevel.fair => 'Large photos and games load slowly',
      BenchLevel.weak => 'Memory slows down everything heavy',
    });
  }

  /// Storage write speed decides how long installs, saves and backups take.
  static BenchMeaning storage(double writeMbs) {
    final BenchLevel level = writeMbs >= 500
        ? BenchLevel.great
        : writeMbs >= 180
        ? BenchLevel.good
        : writeMbs >= 70
        ? BenchLevel.fair
        : BenchLevel.weak;
    return BenchMeaning(level, switch (level) {
      BenchLevel.great => 'Saves photos and installs apps instantly',
      BenchLevel.good => 'Saves and installs quickly',
      BenchLevel.fair => 'Installs and copies take a while',
      BenchLevel.weak => 'Slow storage: installs and backups crawl',
    });
  }

  static BenchMeaning screen(double? hz) {
    if (hz == null) {
      return const BenchMeaning(BenchLevel.fair, 'Refresh rate unknown');
    }
    final int rate = hz.round();
    return rate >= 110
        ? BenchMeaning(BenchLevel.great, 'Very smooth scrolling, up to $rate Hz')
        : rate >= 85
        ? BenchMeaning(BenchLevel.good, 'Smooth scrolling, up to $rate Hz')
        : BenchMeaning(BenchLevel.fair, 'Standard scrolling, up to $rate Hz');
  }

  /// Null when the battery temperature could not be read at both ends.
  static BenchMeaning? heat(double? rise) {
    if (rise == null) return null;
    return rise >= 6
        ? BenchMeaning(
            BenchLevel.weak,
            'Gets hot under load, up ${rise.toStringAsFixed(0)} °C',
          )
        : rise >= 3
        ? BenchMeaning(
            BenchLevel.fair,
            'Warms up under load, up ${rise.toStringAsFixed(0)} °C',
          )
        : const BenchMeaning(BenchLevel.great, 'Stays cool under load');
  }

  /// The headline for the whole phone.
  static String verdict(double total) => switch (_level(total)) {
    BenchLevel.great => 'Fast at everything',
    BenchLevel.good => 'Quick for everyday use',
    BenchLevel.fair => 'Fine for the basics',
    BenchLevel.weak => 'Slow for today’s apps',
  };
}
