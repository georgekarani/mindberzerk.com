import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/hardware_api.g.dart';
import '../../../bridge/hardware_bridge.dart';
import '../../../core/i18n/g_strings.dart';
import '../state/device_providers.dart';
import '../widgets/device_detail.dart';
import '../widgets/live_visuals.dart';

/// Sensors: a spirit level driven by the accelerometer as proof they work,
/// the other live readings, then every sensor grouped by what it senses.
///
/// The live readings only run while this page is open; the provider stops
/// the listeners when it is disposed.
class SensorsPage extends ConsumerWidget {
  const SensorsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const SensorsPage(),
  );

  static const List<String> _order = <String>[
    'motion',
    'position',
    'environment',
    'body',
    'other',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final AsyncValue<List<SensorInfo>> list = ref.watch(sensorListProvider);
    final List<SensorReading> live =
        ref.watch(sensorValuesProvider).value ?? const <SensorReading>[];
    final SensorReading? accel = live
        .where((SensorReading r) => r.type == 'accelerometer')
        .firstOrNull;

    final Map<String, List<SensorInfo>> grouped = <String, List<SensorInfo>>{};
    for (final SensorInfo s in list.value ?? const <SensorInfo>[]) {
      grouped.putIfAbsent(s.category, () => <SensorInfo>[]).add(s);
    }

    return DeviceDetail(
      title: context.s('Sensors'),
      hero: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (accel != null && accel.values.length >= 2)
            BubbleLevel(x: accel.values[0], y: accel.values[1])
          else
            DeviceLoading(label: context.s('Waiting for the first reading')),
          const SizedBox(height: GDesign.space12),
          Text(
            context.s('Tilt the phone'),
            textAlign: TextAlign.center,
            style: g.footnote(),
          ),
        ],
      ),
      sections: <Widget>[
        if (live.isNotEmpty)
          GroupedSection(
            header: context.s('Live'),
            children: <Widget>[
              for (final SensorReading r in live)
                ListRow(
                  title: _label(context, r.type),
                  // Three axes fill the line on their own; the unit is
                  // kept for single readings, where it says what they are.
                  detail: r.values.length == 1
                      ? '${_short(r.values.first)} ${r.unit}'
                      : r.values.map(_short).join('  '),
                ),
            ],
          ),
        for (final String category in _order)
          if (grouped[category] != null)
            GroupedSection(
              header: _title(context, category),
              children: <Widget>[
                for (final SensorInfo s in grouped[category]!)
                  ListRow(
                    title: s.name,
                    subtitle: s.vendor,
                    trailing: s.readable
                        ? const SizedBox.shrink()
                        : Text(context.s('Blocked'), style: g.footnote()),
                  ),
              ],
            ),
      ],
    );
  }

  /// One decimal: enough to see it move, not so much that it jitters.
  static String _short(double v) => v.toStringAsFixed(1);

  static String _label(BuildContext context, String type) => switch (type) {
    'accelerometer' => context.s('Accelerometer'),
    'gyroscope' => context.s('Gyroscope'),
    'magnetometer' => context.s('Compass'),
    'light' => context.s('Light'),
    'proximity' => context.s('Proximity'),
    'pressure' => context.s('Air pressure'),
    _ => type,
  };

  static String _title(BuildContext context, String category) =>
      switch (category) {
        'motion' => context.s('Motion'),
        'position' => context.s('Position'),
        'environment' => context.s('Surroundings'),
        'body' => context.s('Body'),
        _ => context.s('Other'),
      };
}
