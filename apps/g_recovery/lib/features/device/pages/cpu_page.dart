import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import '../../../ui/g_detail_page.dart';
import '../device_format.dart';
import '../state/device_history.dart';
import '../state/device_providers.dart';
import '../widgets/device_detail.dart';
import '../widgets/device_visuals.dart';
import '../widgets/g_line_chart.dart';

/// The processor, drawn as a chip whose cores light up with their live
/// speed, then load over the last minute, then the facts.
class CpuPage extends ConsumerWidget {
  const CpuPage({required this.hue, super.key});

  /// Kept so existing call sites compile; the page uses the one accent.
  final Color hue;

  static Route<void> route({required Color hue}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => CpuPage(hue: hue),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final ProbeCapabilities? caps = ref.watch(deviceCapabilitiesProvider).value;
    final CpuInfo? info = ref.watch(cpuInfoProvider).value;
    final ProbeTick? tick = ref.watch(deviceTickProvider).value;
    final List<double> busySeries = vitalSeries(
      ref.watch(vitalHistoryProvider),
      (VitalSample s) => s.busy == null ? null : s.busy! * 100,
    );
    final double? busy = tick == null ? null : CpuLoad.busyFraction(tick);
    final bool perCore = caps?.coreFrequencies ?? true;

    return DeviceDetail(
      title: info?.socModel ?? info?.hardware ?? context.s('Processor'),
      onInfo: () => showDeviceNote(
        context,
        context.s('About the processor'),
        <String>[
          context.s(
            'Each square is one core. The brighter it is, the closer it is '
            'running to its top speed. Readings arrive twice a second.',
          ),
          if (!(caps?.cpuClusters ?? true))
            context.s(
              'This kernel does not publish its clusters, so they are grouped '
              'by top speed.',
            ),
          if (!(caps?.cpuJiffies ?? true))
            context.s(
              'Android does not let apps read total processor load on this '
              'phone. An app showing one is showing its own use or a guess.',
            ),
        ],
      ),
      hero: info == null
          ? DeviceLoading(label: context.s('Reading the processor'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                HeroFigures(
                  figures: <(String?, String)>[
                    ('${info.coreCount}', context.s('Cores')),
                    (
                      busy == null ? null : '${(busy * 100).round()}%',
                      context.s('Busy now'),
                    ),
                    (_peak(info), context.s('Fastest')),
                  ],
                ),
                const SizedBox(height: GDesign.space16),
                if (perCore)
                  CpuDie(clusters: _clusters(info, tick))
                else
                  Text(
                    context.s('This phone hides each core\'s speed'),
                    style: g.footnote(),
                  ),
              ],
            ),
      sections: <Widget>[
        if (info != null && (caps?.cpuJiffies ?? false))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            child: GChartCard(
              caption: context.s('Load, last minute'),
              axis: const <String>['0%', '100%'],
              child: GLineChart(
                values: busySeries,
                colour: g.accent,
                height: 88,
                // Fixed scale: a quiet phone must not look as busy as a hot one.
                minY: 0,
                maxY: 100,
              ),
            ),
          ),
        if (info != null && info.clusters.isNotEmpty)
          FactSection(
            header: context.s('Clusters'),
            rows: <(String, String?)>[
              for (final CpuCluster c in info.clusters)
                (_clusterName(c), _range(c)),
            ],
          ),
        if (info != null)
          FactSection(
            header: context.s('Chip'),
            rows: <(String, String?)>[
              (context.s('Model'), info.socModel),
              (context.s('Hardware'), info.hardware),
              (context.s('Architecture'), info.abi),
              (context.s('Governor'), _governor(info)),
            ],
          ),
      ],
    );
  }

  /// Clusters in die order (fastest first), each core as a fraction of its
  /// cluster's top speed.
  static List<DieCluster> _clusters(CpuInfo info, ProbeTick? tick) {
    final List<int?>? khz = tick?.current.cpu?.coreKhz;
    final List<bool?>? online = tick?.current.cpu?.coreOnline;

    double? fraction(int core, int? ceiling) {
      if (khz == null || core >= khz.length) return null;
      if (online != null && core < online.length && online[core] == false) {
        return null;
      }
      return DeviceFormat.frequencyFraction(khz[core], ceiling);
    }

    if (info.clusters.isEmpty) {
      return <DieCluster>[
        DieCluster(
          label: 'CPU',
          cores: <double?>[
            for (int i = 0; i < info.coreCount; i++) fraction(i, null),
          ],
        ),
      ];
    }
    return <DieCluster>[
      for (final CpuCluster c in info.clusters)
        DieCluster(
          label: c.label,
          peak: DeviceFormat.frequency(c.maxKhz),
          cores: <double?>[
            for (final int id in c.coreIds) fraction(id, c.maxKhz),
          ],
        ),
    ];
  }

  static String? _peak(CpuInfo info) {
    int top = 0;
    for (final CpuCluster c in info.clusters) {
      if ((c.maxKhz ?? 0) > top) top = c.maxKhz!;
    }
    return top == 0 ? null : DeviceFormat.frequency(top);
  }

  static String _clusterName(CpuCluster c) {
    final int n = c.coreIds.length;
    return '${c.label}, $n ${n == 1 ? 'core' : 'cores'}';
  }

  /// The cluster's top speed. The floor is the same few hundred MHz on
  /// every phone and only made the row wrap.
  static String? _range(CpuCluster c) => DeviceFormat.frequency(c.maxKhz);

  static String? _governor(CpuInfo info) {
    for (final CpuCluster c in info.clusters) {
      if (c.governor != null) return c.governor;
    }
    return null;
  }
}
