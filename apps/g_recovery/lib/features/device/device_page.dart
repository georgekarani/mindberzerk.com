import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import 'benchmark/benchmark_page.dart';
import 'device_format.dart';
import 'pages/battery_page.dart';
import 'pages/cpu_page.dart';
import 'pages/display_page.dart';
import 'pages/memory_page.dart';
import 'pages/network_page.dart';
import 'pages/sensors_page.dart';
import 'pages/sim_page.dart';
import 'pages/system_page.dart';
import 'pages/thermal_page.dart';
import 'state/device_history.dart';
import 'state/device_providers.dart';
import 'state/identity_providers.dart';
import 'tools/screen_test_page.dart';
import 'tools/sound_test_page.dart';

const int kDeviceTabIndex = 2;

/// The phone itself: four live readings, then every detail, then the tests.
///
/// Readings are sampled only while this tab is showing, quickly in the
/// foreground and slowly behind it, and the history clears on leaving so a
/// return never draws a line across the gap.
class DevicePage extends ConsumerStatefulWidget {
  const DevicePage({super.key});

  @override
  ConsumerState<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends ConsumerState<DevicePage>
    with WidgetsBindingObserver {
  bool _foreground = true;
  bool _wasOnTab = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool next = state == AppLifecycleState.resumed;
    if (next == _foreground) return;
    setState(() => _foreground = next);
  }

  void _applyCadence({required bool onTab}) {
    final DeviceSampler sampler = ref.read(deviceSamplerProvider);
    sampler.setPaused(value: !onTab);
    sampler.setInterval(
      _foreground ? kDeviceForegroundInterval : kDeviceBackgroundInterval,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool onTab = ref.watch(gShellTabProvider) == kDeviceTabIndex;
    _applyCadence(onTab: onTab);
    if (onTab != _wasOnTab) {
      _wasOnTab = onTab;
      if (!onTab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(vitalHistoryProvider.notifier).clear();
        });
      }
    }

    final GDesignTheme g = GDesignTheme.of(context);
    final DeviceIdentity? identity = ref.watch(deviceIdentityProvider).value;
    final DeviceSnapshot? now = ref.watch(deviceTickProvider).value?.current;
    final String? caption = deviceCaption(identity);

    return LargeTitlePage(
      title: deviceTitle(identity),
      slivers: <Widget>[
        if (identity != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                GDesign.gutter,
                0,
                GDesign.gutter,
                GDesign.space16,
              ),
              child: Text(
                <String>[
                  ?caption,
                  'Android ${identity.androidRelease}',
                ].join(', '),
                style: g.footnote(),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: _Live()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space32),
            child: GroupedSection(
              header: context.s('Details'),
              children: <Widget>[
                for (final _Entry e in _entries(context, now))
                  ListRow(
                    icon: e.icon,
                    title: e.label,
                    detail: e.value,
                    onTap: () => e.open(context),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: GDesign.space24,
              bottom: GDesign.space24,
            ),
            child: GroupedSection(
              header: context.s('Tests'),
              children: <Widget>[
                ListRow(
                  icon: GIcons.gauge,
                  title: context.s('Benchmark'),
                  subtitle: context.s('How fast this phone is'),
                  onTap: () =>
                      Navigator.of(context).push(BenchmarkPage.route()),
                ),
                ListRow(
                  icon: GIcons.grid,
                  title: context.s('Screen test'),
                  subtitle: context.s('Dead pixels and backlight'),
                  // Full screen tests go above the tab bar.
                  onTap: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(ScreenTestPage.route()),
                ),
                ListRow(
                  icon: GIcons.volume,
                  title: context.s('Speakers and vibration'),
                  onTap: () =>
                      Navigator.of(context).push(SoundTestPage.route()),
                ),
                ListRow(
                  icon: GIcons.touch,
                  title: context.s('Touch'),
                  onTap: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(TouchTestPage.route()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Live ─────────────────────────────────────────────────────────────────

/// Four readings as cards in a two by two grid, each with its last minute
/// drawn underneath. Tapping one opens its full page.
class _Live extends ConsumerWidget {
  const _Live();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final List<VitalSample> history = ref.watch(vitalHistoryProvider);
    final VitalSample? now = history.isEmpty ? null : history.last;
    final BatterySnapshot? battery = ref
        .watch(deviceTickProvider)
        .value
        ?.current
        .battery;

    List<double> series(double? Function(VitalSample) pick) =>
        vitalSeries(history, pick);

    final List<Widget> tiles = <Widget>[
      _Reading(
        icon: GIcons.cpu,
        label: 'CPU',
        value: now?.busy == null ? null : '${(now!.busy! * 100).round()}%',
        values: series(
          (VitalSample s) => s.busy == null ? null : s.busy! * 100,
        ),
        minY: 0,
        maxY: 100,
        onTap: () => Navigator.of(context).push(CpuPage.route(hue: g.accent)),
      ),
      _Reading(
        icon: GIcons.battery,
        label: context.s('Battery'),
        value: now?.batteryPercent == null ? null : '${now!.batteryPercent}%',
        note: battery?.stateOfHealthPercent == null
            ? null
            : context.s1('{}% health', '${battery!.stateOfHealthPercent}'),
        values: series((VitalSample s) => s.batteryPercent?.toDouble()),
        minY: 0,
        maxY: 100,
        onTap: () => Navigator.of(context).push(BatteryPage.route()),
      ),
      _Reading(
        icon: GIcons.memory,
        label: context.s('Free memory'),
        value: GFormat.bytesOrNull(now?.freeBytes),
        values: series(
          (VitalSample s) =>
              s.freeBytes == null ? null : s.freeBytes! / 1073741824,
        ),
        onTap: () =>
            Navigator.of(context).push(MemoryPage.route(hue: g.accent)),
      ),
      _Reading(
        icon: GIcons.thermometer,
        label: context.s('Temperature'),
        value: DeviceFormat.celsiusFromDeci(now?.tempDeciC),
        values: series(
          (VitalSample s) => s.tempDeciC == null ? null : s.tempDeciC! / 10,
        ),
        onTap: () => Navigator.of(context).push(ThermalPage.route()),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: Column(
        children: <Widget>[
          for (int row = 0; row < 2; row++) ...<Widget>[
            if (row > 0) const SizedBox(height: GDesign.space12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Reveal(index: row * 2, child: tiles[row * 2]),
                  ),
                  const SizedBox(width: GDesign.space12),
                  Expanded(
                    child: Reveal(
                      index: row * 2 + 1,
                      child: tiles[row * 2 + 1],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One live reading: what, how much now, and a sparkline of the last minute.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.onTap,
    this.note,
    this.minY,
    this.maxY,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// A second fact under the figure, such as battery health.
  final String? note;
  final List<double> values;
  final double? minY;
  final double? maxY;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: value == null ? label : '$label, $value',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: g.isDark ? g.card : g.grouped,
          borderRadius: BorderRadius.circular(GDesign.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GDesign.space16,
            GDesign.space12,
            GDesign.space16,
            GDesign.space12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 16, color: g.accentText),
                  const SizedBox(width: GDesign.space8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: g.footnote(color: g.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GDesign.space8),
              AnimatedSwitcher(
                duration: GDesign.motion(context, GDesign.fast),
                child: Text(
                  value ?? '-',
                  key: ValueKey<String?>(value),
                  style: g.figures(g.title2()),
                ),
              ),
              Text(note ?? '', maxLines: 1, style: g.figures(g.footnote())),
              const Spacer(),
              const SizedBox(height: GDesign.space8),
              SizedBox(
                height: 36,
                width: double.infinity,
                child: values.length < 2
                    ? Align(
                        alignment: AlignmentDirectional.bottomStart,
                        child: Text(
                          context.s('Collecting'),
                          style: g.footnote(color: g.faint),
                        ),
                      )
                    : CustomPaint(
                        painter: _Spark(
                          values: values,
                          minY: minY,
                          maxY: maxY,
                          line: g.accentText,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A smoothed line over the samples with a fading fill beneath, and a dot
/// on the newest value.
class _Spark extends CustomPainter {
  const _Spark({
    required this.values,
    required this.line,
    this.minY,
    this.maxY,
  });

  final List<double> values;
  final Color line;
  final double? minY;
  final double? maxY;

  @override
  void paint(Canvas canvas, Size size) {
    double low = values.first;
    double high = values.first;
    for (final double v in values) {
      if (v < low) low = v;
      if (v > high) high = v;
    }
    if (high - low < 0.0001) high = low + 1;
    final double bottom = minY ?? low - (high - low) * 0.2;
    final double top = maxY ?? high + (high - low) * 0.2;

    Offset at(int i) => Offset(
      size.width * i / (values.length - 1),
      size.height * (1 - ((values[i] - bottom) / (top - bottom)).clamp(0, 1)),
    );

    // Midpoint quadratic smoothing: passes near every sample and never
    // overshoots into a value the phone did not report.
    final Path path = Path()..moveTo(at(0).dx, at(0).dy);
    for (int i = 1; i < values.length; i++) {
      final Offset a = at(i - 1);
      final Offset b = at(i);
      final Offset mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
    }
    final Offset last = at(values.length - 1);
    path.lineTo(last.dx, last.dy);

    final Path fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            line.withValues(alpha: 0.28),
            line.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(last, 3, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_Spark old) =>
      !identical(old.values, values) || old.line != line;
}

// ── Details ──────────────────────────────────────────────────────────────

/// One row in Details.
@immutable
class _Entry {
  const _Entry({
    required this.label,
    required this.icon,
    required this.open,
    this.value,
  });

  final String label;
  final IconData icon;
  final String? value;
  final void Function(BuildContext context) open;
}

List<_Entry> _entries(BuildContext context, DeviceSnapshot? now) {
  final Color hue = GDesignTheme.of(context).accent;
  final BatterySnapshot? battery = now?.battery;
  return <_Entry>[
    _Entry(
      label: 'CPU',
      icon: GIcons.cpu,
      value: now?.cpu?.coreKhz == null
          ? null
          : context.s1('{} cores', '${now!.cpu!.coreKhz.length}'),
      open: (BuildContext c) => Navigator.of(c).push(CpuPage.route(hue: hue)),
    ),
    _Entry(
      label: context.s('Battery'),
      icon: GIcons.battery,
      value: battery?.stateOfHealthPercent != null
          ? context.s1('{}% health', '${battery!.stateOfHealthPercent}')
          : battery?.percent == null
          ? null
          : '${battery!.percent}%',
      open: (BuildContext c) => Navigator.of(c).push(BatteryPage.route()),
    ),
    _Entry(
      label: context.s('Memory'),
      icon: GIcons.memory,
      value: GFormat.bytesOrNull(now?.memory?.totalBytes),
      open: (BuildContext c) =>
          Navigator.of(c).push(MemoryPage.route(hue: hue)),
    ),
    _Entry(
      label: context.s('Thermal'),
      icon: GIcons.thermometer,
      value: DeviceFormat.celsiusFromDeci(battery?.tempDeciC),
      open: (BuildContext c) => Navigator.of(c).push(ThermalPage.route()),
    ),
    _Entry(
      label: context.s('Display'),
      icon: GIcons.monitor,
      open: (BuildContext c) =>
          Navigator.of(c).push(DisplayPage.route(hue: hue)),
    ),
    _Entry(
      label: context.s('Cameras'),
      icon: GIcons.camera,
      open: (BuildContext c) =>
          Navigator.of(c).push(CamerasPage.route(hue: hue)),
    ),
    _Entry(
      label: context.s('Network'),
      icon: GIcons.wifi,
      open: (BuildContext c) =>
          Navigator.of(c).push(NetworkPage.route(hue: hue)),
    ),
    _Entry(
      label: 'SIM',
      icon: GIcons.signal,
      open: (BuildContext c) => Navigator.of(c).push(SimPage.route(hue: hue)),
    ),
    _Entry(
      label: context.s('Bluetooth'),
      icon: GIcons.bluetooth,
      open: (BuildContext c) =>
          Navigator.of(c).push(BluetoothPage.route(hue: hue)),
    ),
    _Entry(
      label: context.s('Sensors'),
      icon: GIcons.radar,
      open: (BuildContext c) => Navigator.of(c).push(SensorsPage.route()),
    ),
    _Entry(
      label: context.s('System'),
      icon: GIcons.settings,
      open: (BuildContext c) => Navigator.of(c).push(SystemPage.route()),
    ),
    _Entry(
      label: context.s('Access'),
      icon: GIcons.folderOpen,
      open: (BuildContext c) => Navigator.of(c).push(AccessPage.route()),
    ),
  ];
}
