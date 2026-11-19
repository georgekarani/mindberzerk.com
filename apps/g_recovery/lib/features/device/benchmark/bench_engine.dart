import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/prefs_store.dart';
import 'bench_result.dart';

/// The part of the phone a test step is exercising.
enum BenchStage { idle, single, multi, memory, storage, gpu, done }

/// A moment of a running test, streamed from the native engine.
@immutable
class BenchProgress {
  const BenchProgress({
    required this.stage,
    required this.progress,
    required this.live,
    this.cores = 0,
  });

  static const BenchProgress idle = BenchProgress(
    stage: BenchStage.idle,
    progress: 0,
    live: 0,
  );

  final BenchStage stage;

  /// The whole run, 0 to 1.
  final double progress;

  /// The running score for the current step.
  final double live;

  /// How many cores the step is using.
  final int cores;
}

/// Talks to the native benchmark in `bench/Benchmark.kt`.
class BenchEngine {
  static const MethodChannel _methods = MethodChannel('g_recovery/benchmark');
  static const EventChannel _events = EventChannel(
    'g_recovery/benchmark/progress',
  );

  /// Progress events while a run is going.
  Stream<BenchProgress> progress() =>
      _events.receiveBroadcastStream().map((Object? e) {
        final Map<Object?, Object?> m = e! as Map<Object?, Object?>;
        return BenchProgress(
          stage: BenchStage.values.firstWhere(
            (BenchStage s) => s.name == m['stage'],
            orElse: () => BenchStage.idle,
          ),
          progress: (m['progress']! as num).toDouble(),
          live: (m['live']! as num).toDouble(),
          cores: (m['cores'] as num?)?.toInt() ?? 0,
        );
      });

  /// Runs every test. Null when the user stopped it.
  Future<Map<Object?, Object?>?> run() async {
    try {
      return await _methods.invokeMethod<Map<Object?, Object?>>('run');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') return null;
      rethrow;
    }
  }

  Future<void> cancel() => _methods.invokeMethod<void>('cancel');
}

final Provider<BenchEngine> benchEngineProvider = Provider<BenchEngine>(
  (Ref ref) => BenchEngine(),
);

/// Saved runs, newest first, kept on the phone only.
class BenchHistory extends Notifier<List<BenchResult>> {
  static const String _key = 'bench.runs';

  /// Enough to see a phone slow down over a year of monthly runs.
  static const int _keep = 30;

  @override
  List<BenchResult> build() =>
      BenchResult.decodeAll(ref.read(prefsStoreProvider).readString(_key));

  Future<void> add(BenchResult run) async {
    state = <BenchResult>[run, ...state].take(_keep).toList();
    await ref
        .read(prefsStoreProvider)
        .writeString(_key, BenchResult.encodeAll(state));
  }

  Future<void> remove(BenchResult run) async {
    state = <BenchResult>[
      for (final BenchResult r in state)
        if (r.at != run.at) r,
    ];
    await ref
        .read(prefsStoreProvider)
        .writeString(_key, BenchResult.encodeAll(state));
  }
}

final NotifierProvider<BenchHistory, List<BenchResult>> benchHistoryProvider =
    NotifierProvider<BenchHistory, List<BenchResult>>(BenchHistory.new);
