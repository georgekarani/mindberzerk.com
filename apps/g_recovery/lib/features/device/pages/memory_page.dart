import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../../ui/g_detail_page.dart';
import '../device_format.dart';
import '../state/device_history.dart';
import '../state/device_providers.dart';
import '../widgets/device_detail.dart';
import '../widgets/device_visuals.dart';
import '../widgets/g_line_chart.dart';

/// Memory as one live segmented bar: lit segments are in use. It turns red
/// when Android drops below its own low memory line.
class MemoryPage extends ConsumerWidget {
  const MemoryPage({required this.hue, super.key});

  /// Kept so existing call sites compile; the page uses the one accent.
  final Color hue;

  static Route<void> route({required Color hue}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => MemoryPage(hue: hue),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final MemorySnapshot? m = ref
        .watch(deviceTickProvider)
        .value
        ?.current
        .memory;
    final List<double> freeSeries = vitalSeries(
      ref.watch(vitalHistoryProvider),
      (VitalSample s) => s.freeBytes == null ? null : s.freeBytes! / 1073741824,
    );

    final int? total = m?.totalBytes;
    final int? avail = m?.availBytes;
    final int? used = total != null && avail != null ? total - avail : null;
    final bool low = m?.lowMemory ?? false;
    final int? swapTotal = m?.swapTotalBytes;
    final int? swapFree = m?.swapFreeBytes;
    final int? swapUsed = swapTotal != null && swapFree != null
        ? swapTotal - swapFree
        : null;

    return DeviceDetail(
      title: context.s('Memory'),
      onInfo: () => showDeviceNote(context, context.s('About memory'), <String>[
        context.s(
          'Each lit block is memory in use. Android keeps recent apps in '
          'memory on purpose, so a full bar is normal.',
        ),
        if (total != null)
          context.s1(
            'Sold as {}. The kernel reserves the difference before apps see it.',
            GFormat.bytes(DeviceFormat.nominalRamBytes(total)),
          ),
        context.s(
          'Swap is compressed memory kept in RAM, so it costs processor time '
          'instead of storage wear.',
        ),
      ]),
      hero: m == null || total == null || avail == null
          ? DeviceLoading(label: context.s('Reading memory'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CountUpText(
                  value: avail,
                  format: (num v) =>
                      context.s1('{} free', GFormat.bytes(v.round())),
                  style: g.figures(g.largeTitle()),
                ),
                Text(
                  low
                      ? context.s('Low, Android is closing background apps')
                      : context.s1('of {}', GFormat.bytes(total)),
                  style: g.footnote(color: low ? g.danger : null),
                ),
                const SizedBox(height: GDesign.space16),
                SegmentBar(fraction: (used ?? 0) / total, alert: low),
                const SizedBox(height: GDesign.space16),
                HeroFigures(
                  figures: <(String?, String)>[
                    (GFormat.bytesOrNull(used), context.s('In use')),
                    (GFormat.bytesOrNull(swapUsed), context.s('Swap used')),
                  ],
                ),
              ],
            ),
      sections: <Widget>[
        if (freeSeries.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            child: GChartCard(
              caption: context.s('Free, last minute'),
              axis: const <String>['a minute ago', 'now'],
              child: GLineChart(
                values: freeSeries,
                colour: g.accent,
                height: 72,
              ),
            ),
          ),
        FactSection(
          header: context.s('Detail'),
          rows: <(String, String?)>[
            (context.s('Total'), GFormat.bytesOrNull(total)),
            (
              context.s('Android steps in below'),
              GFormat.bytesOrNull(m?.thresholdBytes),
            ),
            (context.s('Swap size'), GFormat.bytesOrNull(swapTotal)),
          ],
        ),
      ],
    );
  }
}
