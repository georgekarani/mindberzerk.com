import 'dart:async';

import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';
import 'package:g_family/g_family.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/i18n/g_strings.dart';

/// G VPN's live state as one row on the Home sheet.
///
/// Reads the state through g_family, so it is the same truth G VPN itself
/// shows. One action per state, sized for a thumb; tapping the row opens
/// G VPN. While G VPN is not installed the row can be dismissed for 30 days,
/// and then the whole group, label included, disappears.
class VpnRow extends StatefulWidget {
  const VpnRow({super.key});

  @override
  State<VpnRow> createState() => _VpnRowState();
}

class _VpnRowState extends State<VpnRow> {
  // Same key the old card used, so a "Not now" given before this update holds.
  static const String _dismissKey = 'gvpn.card.dismissedUntil';
  static const Duration _quiet = Duration(days: 30);

  GVpnStatus? _status;
  bool _dismissed = false;
  StreamSubscription<GVpnStatus>? _sub;

  /// Refreshes the minutes left while paused. Does nothing in other states.
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

    final GTokens t = context.g;
    final String? server = s.label;
    final int minutesLeft = s.pausedUntil == null
        ? 0
        : s.pausedUntil!.difference(DateTime.now()).inMinutes.clamp(0, 9999) +
              1;

    final (
      Color tint,
      IconData icon,
      String title,
      String detail,
      String action,
      Color actionTone,
      VoidCallback onAction,
    ) = switch (s.state) {
      GVpnState.on || GVpnState.reconnecting => (
        t.success,
        Icons.gpp_good_rounded,
        s.state == GVpnState.on
            ? context.s('Protected')
            : context.s('Reconnecting'),
        server ?? context.s('Your connection is encrypted'),
        context.s('Disconnect'),
        t.danger,
        () => GVpn.disconnect(),
      ),
      GVpnState.connecting => (
        t.warning,
        Icons.sync_rounded,
        context.s('Connecting'),
        server ?? '',
        context.s('Open'),
        t.accentText,
        _open,
      ),
      GVpnState.paused => (
        t.warning,
        Icons.pause_circle_outline_rounded,
        context.s('Paused'),
        <String>[
          ?server,
          context.s1('resumes in {} min', minutesLeft),
        ].join('  ·  '),
        context.s('Resume now'),
        t.accentText,
        () => GVpn.connect(),
      ),
      GVpnState.off => (
        t.warning,
        Icons.gpp_maybe_rounded,
        context.s('Not protected'),
        context.s(
          'Uploading recovered files on public Wi-Fi? Turn on G VPN first.',
        ),
        context.s('Connect'),
        t.accentText,
        () => GVpn.connect(),
      ),
      GVpnState.unavailable => (
        t.accent,
        Icons.shield_outlined,
        'G VPN',
        context.s('Open G VPN to see whether this phone is protected.'),
        context.s('Open'),
        t.accentText,
        _open,
      ),
      GVpnState.notInstalled => (
        t.accent,
        Icons.shield_outlined,
        context.s('Protect public Wi-Fi'),
        context.s('G VPN is free, from the makers of G Recovery.'),
        context.s('Get G VPN'),
        t.accentText,
        _open,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(context.s('On this network')),
        EdgeRow(
          leading: Icon(icon, size: 22, color: tint),
          title: title,
          subtitle: detail.isEmpty ? null : detail,
          chevron: false,
          onTap: _open,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: actionTone,
                  minimumSize: const Size(GDesign.touch, GDesign.touch),
                  padding: const EdgeInsets.symmetric(
                    horizontal: GDesign.space12,
                  ),
                  textStyle: GDesignTheme.of(context).sans.copyWith(
                    fontSize: GDesign.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(action),
              ),
              if (s.state == GVpnState.notInstalled)
                IconButton(
                  onPressed: _notNow,
                  tooltip: context.s('Not now'),
                  icon: Icon(Icons.close_rounded, size: 20, color: t.muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
