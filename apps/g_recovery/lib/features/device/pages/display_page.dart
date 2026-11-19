import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/hardware_api.g.dart';
import '../../../bridge/hardware_bridge.dart';
import '../../../core/i18n/g_strings.dart';
import '../widgets/device_detail.dart';
import '../widgets/device_visuals.dart';
import '../widgets/live_visuals.dart';

/// The screen drawn to its true shape, a scan line sweeping at a speed set
/// by the refresh rate, then what it can do.
class DisplayPage extends ConsumerWidget {
  const DisplayPage({required this.hue, super.key});

  /// Kept so existing call sites compile; the page uses the one accent.
  final Color hue;

  static Route<void> route({required Color hue}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => DisplayPage(hue: hue),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DisplayInfo? d = ref.watch(displayProvider).value;
    final FeatureFlags? f = ref.watch(featuresProvider).value;

    return DeviceDetail(
      title: context.s('Display'),
      hero: d == null
          ? DeviceLoading(label: context.s('Reading the screen'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ScreenScale(
                  widthPx: d.widthPx,
                  heightPx: d.heightPx,
                  refreshHz: d.refreshHz,
                ),
                const SizedBox(height: GDesign.space16),
                HeroFigures(
                  figures: <(String?, String)>[
                    ('${d.widthPx}×${d.heightPx}', context.s('Pixels')),
                    (_aspect(d.widthPx, d.heightPx), context.s('Shape')),
                    (
                      d.maxLuminance == null
                          ? null
                          : '${d.maxLuminance!.round()} nits',
                      context.s('Brightest'),
                    ),
                  ],
                ),
              ],
            ),
      sections: <Widget>[
        if (d != null)
          FactSection(
            header: context.s('Screen'),
            rows: <(String, String?)>[
              (context.s('Refresh rate'), '${d.refreshHz.round()} Hz'),
              (context.s('Also runs at'), _otherRates(d)),
              (context.s('Density'), '${d.densityDpi} dpi'),
              (
                context.s('Typical brightness'),
                d.averageLuminance == null
                    ? null
                    : '${d.averageLuminance!.round()} nits',
              ),
            ],
          ),
        if (d != null)
          FlagSection(
            header: context.s('Colour'),
            flags: <(String, bool)>[
              ('HDR', d.hdr),
              (context.s('Wide colour'), d.wideColour),
              for (final String type in d.hdrTypes) (type, true),
            ],
          ),
        if (f != null)
          FlagSection(
            header: context.s('This phone has'),
            flags: <(String, bool)>[
              (context.s('Fingerprint reader'), f.fingerprint),
              ('NFC', f.nfc),
              ('GPS', f.gps),
              (context.s('Ultra wideband'), f.uwb),
              (context.s('USB host'), f.usbHost),
              ('Bluetooth LE', f.bluetoothLe),
            ],
          ),
      ],
    );
  }

  static String? _otherRates(DisplayInfo d) {
    final List<String> others = <String>[
      for (final double hz in d.supportedHz)
        if (hz.round() != d.refreshHz.round()) '${hz.round()}',
    ];
    return others.isEmpty ? null : '${others.join(', ')} Hz';
  }

  /// "20:9" style. Tall panels are expressed against 9, as phones are sold.
  static String _aspect(int w, int h) {
    final int long = w > h ? w : h;
    final int short = w > h ? h : w;
    if (short == 0) return '';
    final double ratio = long / short * 9;
    final String head = (ratio - ratio.round()).abs() < 0.05
        ? '${ratio.round()}'
        : ratio.toStringAsFixed(1);
    return '$head:9';
  }
}

/// The camera bump drawn with one ring per lens, sized by megapixels, then
/// each lens's numbers.
class CamerasPage extends ConsumerWidget {
  const CamerasPage({required this.hue, super.key});

  /// Kept so existing call sites compile; the page uses the one accent.
  final Color hue;

  static Route<void> route({required Color hue}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => CamerasPage(hue: hue),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CameraInfo>> source = ref.watch(camerasProvider);
    final List<CameraInfo> cameras = source.value ?? const <CameraInfo>[];
    final List<CameraInfo> backs =
        cameras.where((CameraInfo c) => c.facing == 'back').toList()..sort(
          (CameraInfo a, CameraInfo b) => (a.focalLengthsMm.firstOrNull ?? 0)
              .compareTo(b.focalLengthsMm.firstOrNull ?? 0),
        );
    final CameraInfo? front = cameras
        .where((CameraInfo c) => c.facing == 'front')
        .firstOrNull;

    ModuleLens lens(CameraInfo c) =>
        ModuleLens(label: _lensName(c, cameras), megapixels: c.megapixels);

    return DeviceDetail(
      title: context.s('Cameras'),
      hero: !source.hasValue
          ? DeviceLoading(label: context.s('Reading the cameras'))
          : CameraModule(
              lenses: <ModuleLens>[for (final CameraInfo c in backs) lens(c)],
              front: front == null ? null : lens(front),
            ),
      sections: <Widget>[
        for (final CameraInfo c in <CameraInfo>[...backs, ?front])
          FactSection(
            header: _lensName(c, cameras),
            rows: <(String, String?)>[
              (context.s('Photo size'), '${c.widthPx} x ${c.heightPx}'),
              (
                context.s('Lens'),
                c.focalLengthsMm.isEmpty
                    ? null
                    : '${c.focalLengthsMm.first.toStringAsFixed(1)} mm',
              ),
              (
                context.s('Aperture'),
                c.apertures.isEmpty
                    ? null
                    : 'f/${c.apertures.first.toStringAsFixed(1)}',
              ),
              (
                'ISO',
                c.isoMin == null || c.isoMax == null
                    ? null
                    : '${c.isoMin} to ${c.isoMax}',
              ),
              ('RAW', c.supportsRaw ? context.s('Yes') : null),
              (context.s('Flash'), c.hasFlash ? context.s('Yes') : null),
            ],
          ),
      ],
    );
  }

  static String _lensName(CameraInfo camera, List<CameraInfo> all) {
    if (camera.facing != 'back') return _facing(camera.facing);
    if (camera.focalLengthsMm.isEmpty) return 'Back';

    final List<CameraInfo> backs =
        all
            .where(
              (CameraInfo c) =>
                  c.facing == 'back' && c.focalLengthsMm.isNotEmpty,
            )
            .toList()
          ..sort(
            (CameraInfo a, CameraInfo b) =>
                a.focalLengthsMm.first.compareTo(b.focalLengthsMm.first),
          );

    if (backs.length < 2) return 'Back';
    if (camera.id == backs.first.id) return 'Ultra wide';
    if (camera.id == backs.last.id) return 'Telephoto';

    // A depth or macro sensor is the giveaway: tiny, and never the one with the
    // longest or shortest lens.
    if (camera.megapixels < 3) return 'Depth or macro';
    return 'Wide';
  }

  static String _facing(String facing) => switch (facing) {
    'front' => 'Front',
    'back' => 'Back',
    _ => 'External',
  };
}
