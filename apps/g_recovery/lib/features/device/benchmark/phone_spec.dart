import 'dart:ui' as ui;

import 'package:device_probe/device_probe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_providers.dart';

/// The front camera opening, in screen fractions (0 to 1 across and down).
@immutable
class FrontCutout {
  const FrontCutout({required this.center, required this.width});

  /// Centre of the opening.
  final Offset center;

  /// Width as a fraction of the screen width; wide ones are notches.
  final double width;

  bool get isNotch => width > 0.2;
}

/// What this phone is built from, read from the phone itself, so the x-ray
/// draws this phone and not a generic one. A field the phone does not report
/// stays null and its part is drawn without a label.
@immutable
class PhoneSpec {
  const PhoneSpec({
    required this.aspect,
    required this.clusters,
    this.cutout,
    this.rearCameras = const <double>[],
    this.ramBytes,
    this.storageBytes,
    this.batteryMah,
    this.maxRefreshHz,
  });

  /// Before anything is read: a common phone shape with eight cores.
  static const PhoneSpec fallback = PhoneSpec(
    aspect: 2.1,
    clusters: <int>[8],
  );

  /// Body height over width.
  final double aspect;

  /// Cores per cluster, fastest cluster first. An S22 reads [1, 3, 4].
  final List<int> clusters;

  final FrontCutout? cutout;

  /// Rear lens focal lengths in millimetres, shortest first.
  final List<double> rearCameras;

  final int? ramBytes;
  final int? storageBytes;
  final double? batteryMah;

  /// The fastest refresh rate the screen supports.
  final double? maxRefreshHz;

  int get cores => clusters.fold(0, (int a, int b) => a + b);

  /// Cores in the fastest cluster, the ones a single thread runs on.
  int get fastCores => clusters.isEmpty ? 1 : clusters.first;

  /// The same spec with the screen shape read from the live view.
  PhoneSpec withScreen(ui.FlutterView view, List<ui.DisplayFeature> features) {
    // Display features are in logical pixels, so compare in those too.
    final Size px = view.physicalSize / view.devicePixelRatio;
    final double shortSide = px.shortestSide;
    final double longSide = px.longestSide;
    FrontCutout? hole;
    for (final ui.DisplayFeature f in features) {
      if (f.type != ui.DisplayFeatureType.cutout) continue;
      final Rect r = f.bounds;
      // Cutouts are given in physical pixels for the current rotation.
      final bool portrait = px.height >= px.width;
      final Offset c = r.center;
      hole = FrontCutout(
        center: portrait
            ? Offset(c.dx / px.width, c.dy / px.height)
            : Offset(c.dy / px.height, 1 - c.dx / px.width),
        width: (portrait ? r.width : r.height) / shortSide,
      );
      break;
    }
    return PhoneSpec(
      aspect: shortSide == 0 ? aspect : (longSide / shortSide).clamp(1.6, 2.5),
      clusters: clusters,
      cutout: hole,
      rearCameras: rearCameras,
      ramBytes: ramBytes,
      storageBytes: storageBytes,
      batteryMah: batteryMah,
      maxRefreshHz: maxRefreshHz,
    );
  }
}

/// Cluster sizes from the probe, fastest first. Clusters that share a top
/// speed are merged, since they are the same kind of core.
List<int> clustersFrom(CpuInfo? cpu) {
  if (cpu == null || cpu.clusters.isEmpty) {
    return <int>[if (cpu != null && cpu.coreCount > 0) cpu.coreCount else 8];
  }
  final Map<int, int> bySpeed = <int, int>{};
  for (final CpuCluster c in cpu.clusters) {
    final int speed = c.maxKhz ?? 0;
    bySpeed[speed] = (bySpeed[speed] ?? 0) + c.coreIds.length;
  }
  final List<int> speeds = bySpeed.keys.toList()..sort((int a, int b) => b - a);
  return <int>[for (final int s in speeds) bySpeed[s]!];
}

/// Everything except the screen shape, which the page adds from its view.
final FutureProvider<PhoneSpec> phoneSpecProvider = FutureProvider<PhoneSpec>((
  Ref ref,
) async {
  const MethodChannel channel = MethodChannel('g_recovery/benchmark');
  final CpuInfo? cpu = await ref.watch(cpuInfoProvider.future);
  Map<Object?, Object?> hw = const <Object?, Object?>{};
  try {
    hw = await channel.invokeMethod<Map<Object?, Object?>>('hardware') ??
        const <Object?, Object?>{};
  } on PlatformException {
    // Left empty: parts are drawn without labels.
  }
  return PhoneSpec(
    aspect: PhoneSpec.fallback.aspect,
    clusters: clustersFrom(cpu),
    rearCameras: <double>[
      for (final Object? f in (hw['rearCameras'] as List<Object?>?) ?? <Object?>[])
        (f! as num).toDouble(),
    ],
    ramBytes: (hw['ramBytes'] as num?)?.toInt(),
    storageBytes: (hw['storageBytes'] as num?)?.toInt(),
    batteryMah: (hw['batteryMah'] as num?)?.toDouble(),
    maxRefreshHz: (hw['maxRefreshHz'] as num?)?.toDouble(),
  );
});
