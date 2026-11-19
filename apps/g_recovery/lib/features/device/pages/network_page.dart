import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/hardware_api.g.dart';
import '../../../bridge/hardware_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../device_format.dart';
import '../state/device_providers.dart';
import '../widgets/device_detail.dart';
import '../widgets/live_visuals.dart';

/// The connection: Wi-Fi arcs lit to the signal, live down and up speeds
/// over the last minute, then the link and the addresses.
class NetworkPage extends ConsumerWidget {
  const NetworkPage({required this.hue, super.key});

  /// Kept so existing call sites compile; the page uses the one accent.
  final Color hue;

  static Route<void> route({required Color hue}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => NetworkPage(hue: hue),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final NetworkInfo? net = ref.watch(networkProvider).value;
    final WifiInfo? wifi = ref.watch(wifiProvider).value;
    ref.watch(throughputProvider);
    final List<ThroughputSample> history = ref.watch(throughputHistoryProvider);
    final ThroughputSample? now = history.isEmpty ? null : history.last;
    final String? sinceBoot = DeviceFormat.uptime(
      ref.watch(deviceTickProvider).value?.current.elapsedRealtimeMillis,
    );
    final bool onWifi = wifi != null && wifi.connected;

    return DeviceDetail(
      title: context.s('Network'),
      hero: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              WifiArcs(
                // The measured signal when Android shares it; otherwise full
                // arcs simply mean "on Wi-Fi", and grey means not.
                signal: onWifi && wifi.signalPercent != null
                    ? wifi.signalPercent! / 100
                    : (net?.type == 'wifi' ? 1 : null),
              ),
              const SizedBox(width: GDesign.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      onWifi
                          ? (wifi.ssid ?? 'Wi-Fi')
                          : _typeName(context, net?.type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: g.headline(),
                    ),
                    Text(
                      <String>[
                        if (onWifi && wifi.standard != null) wifi.standard!,
                        if (onWifi && wifi.signalPercent != null)
                          context.s1('{}% signal', wifi.signalPercent!),
                      ].join(', '),
                      style: g.footnote(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: GDesign.space16),
          HeroFigures(
            figures: <(String?, String)>[
              (
                '${GFormat.bytes(now?.rxBytesPerSecond ?? 0)}/s',
                context.s('Down'),
              ),
              (
                '${GFormat.bytes(now?.txBytesPerSecond ?? 0)}/s',
                context.s('Up'),
              ),
            ],
          ),
          const SizedBox(height: GDesign.space12),
          SizedBox(
            height: 96,
            child: history.length < 2
                ? Center(
                    child: Text(context.s('Measuring'), style: g.footnote()),
                  )
                : LineChart(
                    _chart(history, g),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                  ),
          ),
        ],
      ),
      sections: <Widget>[
        if (wifi != null && !wifi.hasLocationPermission)
          GroupedSection(
            children: <Widget>[
              ListRow(
                icon: GIcons.lock,
                title: context.s('Show the network name'),
                subtitle: context.s('Needs location access'),
                onTap: () async {
                  await ref.read(hardwareBridgeProvider).requestLocation();
                  ref.invalidate(wifiProvider);
                },
              ),
            ],
          ),
        if (onWifi)
          FactSection(
            header: context.s('Link'),
            rows: <(String, String?)>[
              (context.s('Security'), wifi.security),
              (
                context.s('Link speed'),
                wifi.linkSpeedMbps == null
                    ? null
                    : '${wifi.linkSpeedMbps} Mbps',
              ),
              (
                context.s('Band'),
                wifi.frequencyMhz == null ? null : _band(wifi.frequencyMhz!),
              ),
              (context.s('MAC address'), wifi.macAddress),
            ],
          ),
        if (net != null)
          FactSection(
            header: context.s('Connection'),
            rows: <(String, String?)>[
              (
                context.s('Internet'),
                net.connected ? context.s('Yes') : context.s('No'),
              ),
              (
                context.s('Metered'),
                net.metered ? context.s('Yes') : context.s('No'),
              ),
              (context.s('Local address'), net.ipv4),
              ('IPv6', net.ipv6),
            ],
          ),
        if (now != null && now.rxBytesTotal + now.txBytesTotal > 0)
          FactSection(
            header: sinceBoot == null
                ? context.s('Since start up')
                : context.s1('Since start up, {}', sinceBoot),
            rows: <(String, String?)>[
              (context.s('Received'), GFormat.bytes(now.rxBytesTotal)),
              (context.s('Sent'), GFormat.bytes(now.txBytesTotal)),
            ],
          ),
        if (wifi != null)
          FlagSection(
            header: context.s('Wi-Fi bands'),
            flags: <(String, bool)>[
              ('2.4 GHz', true),
              ('5 GHz', wifi.supports5Ghz),
              ('6 GHz', wifi.supports6Ghz),
            ],
          ),
      ],
    );
  }

  static String _typeName(BuildContext context, String? type) => switch (type) {
    'wifi' => 'Wi-Fi',
    'cellular' => context.s('Mobile data'),
    'ethernet' => 'Ethernet',
    'vpn' => 'VPN',
    _ => context.s('Not connected'),
  };

  static String _band(int mhz) => mhz >= 5925
      ? '6 GHz'
      : mhz >= 5000
      ? '5 GHz'
      : '2.4 GHz';

  /// Down as a filled accent line, up as a thin muted one, sharing a scale.
  static LineChartData _chart(List<ThroughputSample> h, GDesignTheme g) {
    double peak = 1;
    for (final ThroughputSample s in h) {
      final double kb =
          (s.rxBytesPerSecond > s.txBytesPerSecond
              ? s.rxBytesPerSecond
              : s.txBytesPerSecond) /
          1024;
      if (kb > peak) peak = kb;
    }
    LineChartBarData line(
      double Function(ThroughputSample) pick,
      Color colour, {
      required bool fill,
    }) => LineChartBarData(
      spots: <FlSpot>[
        for (int i = 0; i < h.length; i++) FlSpot(i.toDouble(), pick(h[i])),
      ],
      isCurved: true,
      curveSmoothness: 0.24,
      color: colour,
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: fill,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            colour.withValues(alpha: 0.32),
            colour.withValues(alpha: 0),
          ],
        ),
      ),
    );

    return LineChartData(
      minY: 0,
      maxY: peak * 1.15,
      minX: 0,
      maxX: (h.length - 1).toDouble(),
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: <LineChartBarData>[
        line(
          (ThroughputSample s) => s.rxBytesPerSecond / 1024,
          g.accent,
          fill: true,
        ),
        line(
          (ThroughputSample s) => s.txBytesPerSecond / 1024,
          g.muted,
          fill: false,
        ),
      ],
    );
  }
}
