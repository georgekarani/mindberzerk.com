import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import '../device_format.dart';
import '../state/device_providers.dart';
import '../widgets/device_detail.dart';
import '../widgets/live_visuals.dart';

/// Heat: what Android thinks of it, then each part of the phone as a column
/// rising to its temperature.
class ThermalPage extends ConsumerWidget {
  const ThermalPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const ThermalPage(),
  );

  /// How many zones fit as columns; the rest are rows below.
  static const int _columns = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final ProbeCapabilities? caps = ref.watch(deviceCapabilitiesProvider).value;
    final ThermalSample? thermal = ref
        .watch(deviceTickProvider)
        .value
        ?.current
        .thermal;
    final List<ThermalZone> zones = _ordered(
      thermal?.zones ?? const <ThermalZone>[],
    );
    final int band = DeviceFormat.thermalBand(thermal?.status);
    final String? state = DeviceFormat.thermalStatus(thermal?.status);
    final Color stateTone = switch (band) {
      0 => g.text,
      1 => g.accentText,
      _ => g.danger,
    };
    ThermalZone? hottest;
    for (final ThermalZone z in zones) {
      if (hottest == null || z.milliCelsius > hottest.milliCelsius) hottest = z;
    }

    return DeviceDetail(
      title: context.s('Thermal'),
      onInfo: () => showDeviceNote(context, context.s('About heat'), <String>[
        context.s(
          'The state is what Android itself decides from its thermal service. '
          'It is the one that slows the phone down.',
        ),
        context.s(
          'Columns are the individual sensors, on a 20 to 70 degree scale. '
          'Above 55 they turn red.',
        ),
      ]),
      hero: thermal == null
          ? DeviceLoading(label: context.s('Reading temperatures'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (state != null)
                  Text(state, style: g.largeTitle(color: stateTone)),
                if (hottest != null)
                  Text(
                    context.s1(
                      'Hottest: {}',
                      '${hottest.label}, '
                          '${DeviceFormat.celsiusFromMilli(hottest.milliCelsius)}',
                    ),
                    style: g.footnote(),
                  ),
                if (zones.isNotEmpty) ...<Widget>[
                  const SizedBox(height: GDesign.space16),
                  HeatColumns(
                    zones: <HeatZone>[
                      for (final ThermalZone z in zones.take(_columns))
                        HeatZone(
                          label: z.label,
                          celsius: z.milliCelsius / 1000,
                        ),
                    ],
                  ),
                ],
              ],
            ),
      sections: <Widget>[
        if (zones.length > _columns)
          FactSection(
            header: context.s('All sensors'),
            rows: <(String, String?)>[
              for (final ThermalZone z in zones)
                (z.label, DeviceFormat.celsiusFromMilli(z.milliCelsius)),
            ],
          ),
        if (zones.isEmpty && caps != null && !caps.thermalZones)
          MissingSection(
            title: context.s('Individual sensors'),
            reason: context.s(
              'This phone does not let apps read its temperature sensors. The '
              'state above is the only heat signal it shares, and it is the one '
              'Android acts on.',
            ),
          ),
      ],
    );
  }

  /// Battery, processor, graphics and skin first; hottest first inside each.
  static List<ThermalZone> _ordered(List<ThermalZone> zones) {
    const List<String> priority = <String>[
      'battery',
      'cpu',
      'gpu',
      'skin',
      'modem',
      'ambient',
      'other',
    ];
    return List<ThermalZone>.of(zones)..sort((ThermalZone a, ThermalZone b) {
      final int byKind = priority
          .indexOf(a.category)
          .compareTo(priority.indexOf(b.category));
      return byKind != 0 ? byKind : b.milliCelsius.compareTo(a.milliCelsius);
    });
  }
}
