import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/hardware_api.g.dart';
import '../../../bridge/hardware_bridge.dart';
import '../../../core/i18n/g_strings.dart';
import '../widgets/device_detail.dart';
import '../widgets/device_visuals.dart';

/// Each SIM drawn as a card side by side, then one section per slot.
class SimPage extends ConsumerWidget {
  const SimPage({required this.hue, super.key});

  /// Kept so existing call sites compile; the page uses the one accent.
  final Color hue;

  static Route<void> route({required Color hue}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => SimPage(hue: hue),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final AsyncValue<List<SimInfo>> source = ref.watch(simsProvider);
    final List<SimInfo> sims = source.value ?? const <SimInfo>[];

    Future<void> ask() async {
      await ref.read(hardwareBridgeProvider).requestPhoneState();
      ref.invalidate(simsProvider);
    }

    return DeviceDetail(
      title: 'SIM',
      hero: !source.hasValue
          ? DeviceLoading(label: context.s('Reading SIM cards'))
          : sims.isEmpty
          ? Column(
              children: <Widget>[
                Icon(GIcons.signal, size: 40, color: g.faint),
                const SizedBox(height: GDesign.space12),
                Text(
                  context.s('Phone access names the carrier'),
                  style: g.headline(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: GDesign.space16),
                PrimaryButton(label: context.s('Allow'), onTap: ask),
              ],
            )
          : SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < sims.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: GDesign.space16),
                    Reveal(
                      index: i,
                      child: Transform.rotate(
                        // A slight fan, so two cards read as a pair.
                        angle: sims.length < 2 ? 0 : (i == 0 ? -0.06 : 0.06),
                        child: SimCardArt(
                          carrier: sims[i].carrier ?? context.s('No carrier'),
                          slot: sims[i].embedded
                              ? 'eSIM'
                              : context.s1('Slot {}', sims[i].slot + 1),
                          embedded: sims[i].embedded,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
      sections: <Widget>[
        for (final SimInfo sim in sims)
          FactSection(
            header: context.s1('Slot {}', sim.slot + 1),
            rows: <(String, String?)>[
              (context.s('Carrier'), sim.carrier),
              (
                context.s('Mobile data'),
                sim.dataDefault ? context.s('Yes') : null,
              ),
              (context.s('Roaming'), sim.roaming ? context.s('Yes') : null),
              (
                context.s('Type'),
                sim.embedded ? context.s('Built in') : context.s('Card'),
              ),
              ('MCC', sim.mcc),
              ('MNC', sim.mnc),
            ],
          ),
      ],
    );
  }
}

/// The radio, what it supports, and what is paired with it.
class BluetoothPage extends ConsumerWidget {
  const BluetoothPage({required this.hue, super.key});

  /// Kept so existing call sites compile; the page uses the one accent.
  final Color hue;

  static Route<void> route({required Color hue}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => BluetoothPage(hue: hue),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final BluetoothInfo? bt = ref.watch(bluetoothProvider).value;

    return DeviceDetail(
      title: context.s('Bluetooth'),
      hero: bt == null
          ? DeviceLoading(label: context.s('Reading Bluetooth'))
          : Row(
              children: <Widget>[
                Icon(
                  GIcons.bluetooth,
                  size: 40,
                  color: bt.enabled ? g.accent : g.faint,
                ),
                const SizedBox(width: GDesign.space16),
                Expanded(
                  child: HeroFigures(
                    figures: <(String?, String)>[
                      (
                        !bt.available
                            ? context.s('None')
                            : bt.enabled
                            ? context.s('On')
                            : context.s('Off'),
                        context.s('Radio'),
                      ),
                      ('${bt.paired.length}', context.s('Paired')),
                    ],
                  ),
                ),
              ],
            ),
      sections: <Widget>[
        if (bt != null && !bt.hasPermission)
          GroupedSection(
            children: <Widget>[
              ListRow(
                icon: GIcons.lock,
                title: context.s('Show paired devices'),
                onTap: () async {
                  await ref.read(hardwareBridgeProvider).requestBluetooth();
                  ref.invalidate(bluetoothProvider);
                },
              ),
            ],
          ),
        if (bt != null && bt.paired.isNotEmpty)
          GroupedSection(
            header: context.s('Paired'),
            children: <Widget>[
              for (final PairedDevice d in bt.paired)
                ListRow(icon: _icon(d.type), title: d.name, detail: d.address),
            ],
          ),
        if (bt != null)
          FlagSection(
            header: context.s('Low energy'),
            flags: <(String, bool)>[
              ('Bluetooth LE', bt.leSupported),
              ('2M PHY', bt.le2mSupported),
              ('Coded PHY', bt.leCodedSupported),
              ('LE Audio', bt.leAudioSupported),
            ],
          ),
        if (bt != null)
          FactSection(
            rows: <(String, String?)>[(context.s('This phone'), bt.name)],
          ),
      ],
    );
  }

  static IconData _icon(String type) => switch (type) {
    'audio' => GIcons.audio,
    'phone' => GIcons.device,
    'computer' => GIcons.monitor,
    'input' => GIcons.touch,
    _ => GIcons.bluetooth,
  };
}
