import 'dart:async';

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';
import 'package:g_family/g_family.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/g_strings.dart';

/// G VPN's state on this network, as one row in a grouped section with the
/// one action that fits the state. When G VPN is not installed the row can
/// be put away for 30 days.
class VpnRow extends StatefulWidget {
  const VpnRow({super.key});

  @override
  State<VpnRow> createState() => _VpnRowState();
}

class _VpnRowState extends State<VpnRow> {
  static const String _dismissKey = 'gvpn.card.dismissedUntil';
  static const Duration _quiet = Duration(days: 30);

  GVpnStatus? _status;
  bool _dismissed = false;
  StreamSubscription<GVpnStatus>? _sub;

  /// Redraws the paused countdown.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((SharedPreferences prefs) {
      final int until = prefs.getInt(_dismissKey) ?? 0;
      if (mounted) {
        setState(
          () => _dismissed = DateTime.now().millisecondsSinceEpoch < until,
        );
      }
    });
    GVpn.status()
        .then((GVpnStatus s) {
          if (mounted) setState(() => _status = s);
        })
        .catchError((Object _) {});
    _sub = GVpn.watch().listen((GVpnStatus s) {
      if (mounted) setState(() => _status = s);
    }, onError: (Object _) {});
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _status?.state == GVpnState.paused) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _notNow() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _dismissKey,
      DateTime.now().add(_quiet).millisecondsSinceEpoch,
    );
    if (mounted) setState(() => _dismissed = true);
  }

  void _open() => GVpn.open(referrer: 'g_recovery');

  @override
  Widget build(BuildContext context) {
    final GVpnStatus? s = _status;
    if (s == null) return const SizedBox.shrink();
    if (s.state == GVpnState.notInstalled && _dismissed) {
      return const SizedBox.shrink();
    }

    final String? server = s.label;
    final int minutesLeft = s.pausedUntil == null
        ? 0
        : s.pausedUntil!.difference(DateTime.now()).inMinutes.clamp(0, 9999) +
              1;

    final (
      IconData icon,
      String title,
      String? detail,
      String action,
      VoidCallback onAction,
    ) = switch (s.state) {
      GVpnState.on || GVpnState.reconnecting => (
        GIcons.shieldCheck,
        s.state == GVpnState.on
            ? context.s('Protected')
            : context.s('Reconnecting'),
        server ?? context.s('Your connection is encrypted'),
        context.s('Disconnect'),
        () => GVpn.disconnect(),
      ),
      GVpnState.connecting => (
        GIcons.refresh,
        context.s('Connecting'),
        server,
        context.s('Open'),
        _open,
      ),
      GVpnState.paused => (
        GIcons.shield,
        context.s('Paused'),
        <String>[
          ?server,
          context.s1('resumes in {} min', minutesLeft),
        ].join(', '),
        context.s('Resume'),
        () => GVpn.connect(),
      ),
      GVpnState.off => (
        GIcons.shield,
        context.s('Not protected'),
        null,
        context.s('Connect'),
        () => GVpn.connect(),
      ),
      GVpnState.unavailable => (
        GIcons.shield,
        'G VPN',
        null,
        context.s('Open'),
        _open,
      ),
      GVpnState.notInstalled => (
        GIcons.shield,
        context.s('Protect public Wi-Fi'),
        context.s('Free'),
        context.s('Get'),
        _open,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: GDesign.space24),
      child: GroupedSection(
        header: context.s('On this network'),
        children: <Widget>[
          ListRow(
            icon: icon,
            title: title,
            subtitle: detail == null || detail.isEmpty ? null : detail,
            onTap: _open,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                NavAction.text(label: action, onTap: onAction),
                if (s.state == GVpnState.notInstalled)
                  NavAction.icon(
                    icon: GIcons.close,
                    semanticLabel: context.s('Not now'),
                    onTap: _notNow,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
