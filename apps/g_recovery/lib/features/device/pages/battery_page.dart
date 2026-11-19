import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import '../device_format.dart';
import '../state/device_providers.dart';
import '../widgets/device_detail.dart';
import '../widgets/device_visuals.dart';

/// The battery as two rings: charge outside, health inside. A spark runs
/// round the charge ring while it charges.
class BatteryPage extends ConsumerWidget {
  const BatteryPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const BatteryPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final ProbeCapabilities? caps = ref.watch(deviceCapabilitiesProvider).value;
    final BatterySnapshot? b = ref
        .watch(deviceTickProvider)
        .value
        ?.current
        .battery;
    final bool charging = b?.charging ?? false;

    return DeviceDetail(
      title: context.s('Battery'),
      onInfo: () => showDeviceNote(
        context,
        context.s('About the battery'),
        <String>[
          context.s(
            'The outer ring is the charge. The inner ring is health: how much '
            'the battery holds now compared with when it was new.',
          ),
          context.s(
            'Some phones do not report health. The inner ring is left out '
            'rather than guessed.',
          ),
        ],
      ),
      hero: caps != null && !caps.battery
          ? Text(context.s('This device has no battery'), style: g.headline())
          : b == null
          ? DeviceLoading(label: context.s('Reading the battery'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ChargeRing(
                  percent: b.percent,
                  health: b.stateOfHealthPercent,
                  charging: charging,
                  caption: charging
                      ? context.s('Charging')
                      : context.s('On battery'),
                ),
                const SizedBox(height: GDesign.space16),
                HeroFigures(
                  figures: <(String?, String)>[
                    (
                      b.stateOfHealthPercent == null
                          ? null
                          : '${b.stateOfHealthPercent}%',
                      context.s('Health'),
                    ),
                    (
                      DeviceFormat.celsiusFromDeci(b.tempDeciC),
                      context.s('Temperature'),
                    ),
                    (b.cycleCount?.toString(), context.s('Cycles')),
                  ],
                ),
              ],
            ),
      sections: <Widget>[
        if (b != null)
          FactSection(
            header: context.s('Wear'),
            rows: <(String, String?)>[
              (
                context.s('Charge left'),
                DeviceFormat.microAmpHours(b.chargeCounterMicroAh),
              ),
              (
                context.s('When new'),
                DeviceFormat.microAmpHours(b.designCapacityMicroAh),
              ),
              (context.s('Reported state'), DeviceFormat.humanise(b.health)),
            ],
          ),
        if (b != null)
          FactSection(
            header: context.s('Right now'),
            rows: <(String, String?)>[
              (context.s('Status'), DeviceFormat.humanise(b.status)),
              (context.s('Voltage'), DeviceFormat.volts(b.voltageMilliV)),
              (context.s('Current'), DeviceFormat.milliAmps(b.currentMicroA)),
              (context.s('Chemistry'), b.technology),
            ],
          ),
      ],
    );
  }
}
