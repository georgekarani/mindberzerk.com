import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/server_api.g.dart';
import '../../bridge/server_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';

/// Adding or editing a home server, as a grouped form: where it is, how to
/// sign in, which folder, whether to encrypt. Test connection checks it
/// for real (signs in and writes a file) before Save is offered.
class ServerSetupPage extends ConsumerStatefulWidget {
  const ServerSetupPage({super.key, this.existing, this.protocol = 'smb'});

  final ServerConfig? existing;

  /// 'smb' or 'webdav', for a new server.
  final String protocol;

  static Route<void> route({ServerConfig? existing, String protocol = 'smb'}) =>
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ServerSetupPage(existing: existing, protocol: protocol),
      );

  @override
  ConsumerState<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<ServerSetupPage> {
  late final TextEditingController _host;
  late final TextEditingController _share;
  late final TextEditingController _port;
  late final TextEditingController _address;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _path;
  late final GShellNav _nav;

  bool _encrypt = false;
  bool _busy = false;
  ServerProbe? _probe;
  DavAddress? _parsed;

  /// A self-signed certificate the user has chosen to trust.
  String? _certPin;

  String get _protocol => widget.existing?.protocol ?? widget.protocol;
  bool get _isDav => _protocol == 'webdav';

  @override
  void initState() {
    super.initState();
    _nav = ref.read(gShellNavHiddenProvider.notifier)..hide();
    final ServerConfig? existing = widget.existing;
    _host = TextEditingController(text: existing?.host ?? '');
    _share = TextEditingController(text: existing?.share ?? '');
    _port = TextEditingController(text: '${existing?.port ?? 445}');
    _user = TextEditingController(text: existing?.username ?? '');
    _password = TextEditingController();
    _path = TextEditingController(
      text: existing?.remotePath ?? (_isDav ? 'Backups/Phone' : '/GRecovery'),
    );
    _encrypt = existing?.encrypt ?? false;
    _certPin = existing?.certPin;
    final String rebuilt = existing == null || existing.protocol != 'webdav'
        ? ''
        : DavAddress(
            host: existing.host,
            port: existing.port,
            basePath: existing.basePath ?? '',
            secure: existing.secure ?? true,
          ).text;
    _address = TextEditingController(text: rebuilt);
    _parsed = DavAddress.parse(rebuilt);
    for (final TextEditingController c in <TextEditingController>[
      _host,
      _share,
      _port,
      _user,
      _password,
      _path,
    ]) {
      // Any edit makes the last test stale.
      c.addListener(_stale);
    }
  }

  void _stale() {
    if (_probe != null) setState(() => _probe = null);
  }

  @override
  void dispose() {
    _nav.show();
    for (final TextEditingController c in <TextEditingController>[
      _host,
      _share,
      _port,
      _address,
      _user,
      _password,
      _path,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ServerConfig get _config {
    final ServerConfig? existing = widget.existing;
    final String folder = _path.text.trim();
    if (_isDav) {
      final DavAddress? parsed = _parsed;
      return ServerConfig(
        id: existing?.id ?? 'server',
        protocol: 'webdav',
        label: parsed?.host ?? '',
        host: parsed?.host ?? '',
        port: parsed?.port ?? 443,
        share: null,
        username: _user.text.trim(),
        remotePath: folder.isEmpty ? 'Backups/Phone' : folder,
        encrypt: _encrypt,
        wifiOnly: existing?.wifiOnly ?? true,
        whileCharging: existing?.whileCharging ?? true,
        scheduled: existing?.scheduled ?? false,
        secure: parsed?.secure ?? true,
        basePath: parsed?.basePath,
        certPin: _certPin,
      );
    }
    return ServerConfig(
      id: existing?.id ?? 'server',
      protocol: 'smb',
      label: _host.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 445,
      share: _share.text.trim().isEmpty ? null : _share.text.trim(),
      username: _user.text.trim(),
      remotePath: folder.isEmpty ? '/GRecovery' : folder,
      encrypt: _encrypt,
      wifiOnly: existing?.wifiOnly ?? true,
      whileCharging: existing?.whileCharging ?? true,
      scheduled: existing?.scheduled ?? false,
    );
  }

  bool get _fillable => _isDav ? _parsed != null : _host.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ServerProbe? probe = _probe;
    final bool ready = probe != null && probe.reachable && probe.writable;
    final DavAddress? parsed = _parsed;

    return LargeTitlePage(
      title: _isDav ? 'WebDAV' : context.s('Windows share'),
      backLabel: context.s('Home server'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.lock,
          semanticLabel: context.s('Where the password goes'),
          onTap: () => _explainSecurity(context),
        ),
      ],
      bottom: ActionBar(
        center: PrimaryButton(
          label: ready ? context.s('Save') : context.s('Test connection'),
          icon: ready ? GIcons.check : GIcons.wifi,
          busy: _busy,
          onTap: _busy || !_fillable ? null : (ready ? _save : _test),
        ),
      ),
      bottomExtent: ActionBar.extent(context),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: GroupedSection(
            header: context.s('Server'),
            children: <Widget>[
              if (_isDav) ...<Widget>[
                _FieldRow(
                  label: context.s('Address'),
                  controller: _address,
                  hint: 'https://cloud.example.com/dav/',
                  keyboard: TextInputType.url,
                  onChanged: (String value) => setState(() {
                    _parsed = DavAddress.parse(value);
                    _probe = null;
                    _certPin = null;
                  }),
                  last: parsed == null,
                ),
                if (parsed != null) ...<Widget>[
                  ListRow(title: context.s('Host'), detail: parsed.host),
                  ListRow(
                    title: context.s('Connection'),
                    detail: parsed.secure
                        ? context.s('Encrypted')
                        : context.s('Not encrypted'),
                  ),
                ],
              ] else ...<Widget>[
                _FieldRow(
                  label: context.s('Address'),
                  controller: _host,
                  hint: '192.168.1.40',
                  keyboard: TextInputType.url,
                ),
                _FieldRow(
                  label: context.s('Share'),
                  controller: _share,
                  hint: 'Backups',
                ),
                _FieldRow(
                  label: context.s('Port'),
                  controller: _port,
                  hint: '445',
                  keyboard: TextInputType.number,
                  last: true,
                ),
              ],
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space24),
            child: GroupedSection(
              header: context.s('Sign in'),
              footer: _isDav
                  ? context.s('With two-step sign in, use an app password.')
                  : null,
              children: <Widget>[
                _FieldRow(
                  label: context.s('Username'),
                  controller: _user,
                  hint: context.s('Required'),
                ),
                _FieldRow(
                  label: context.s('Password'),
                  controller: _password,
                  hint: widget.existing == null
                      ? context.s('Required')
                      : context.s('Unchanged'),
                  secret: true,
                  last: true,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space24),
            child: GroupedSection(
              header: context.s('On the server'),
              children: <Widget>[
                _FieldRow(
                  label: context.s('Folder'),
                  controller: _path,
                  hint: _isDav ? 'Backups/Phone' : '/GRecovery',
                ),
                ListRow(
                  title: context.s('Encrypt files'),
                  subtitle: _encrypt
                      ? context.s('Only this app can open them')
                      : context.s('Any computer app can open them'),
                  trailing: ToggleSwitch(
                    value: _encrypt,
                    semanticLabel: context.s('Encrypt files'),
                    onChanged: (bool on) => setState(() => _encrypt = on),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (probe != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: GDesign.space24),
              child: Reveal(
                child: _Result(
                  probe: probe,
                  onTrust: probe.certFingerprint == null ? null : _trust,
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: GDesign.space32)),
      ],
    );
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _probe = null;
    });
    final ServerProbe? probe = await ref
        .read(serverBridgeProvider)
        .test(_config, password: _password.text);
    if (!mounted) return;
    final bool ok = probe != null && probe.reachable && probe.writable;
    ok ? Haptics.confirm() : Haptics.destroy();
    setState(() {
      _busy = false;
      _probe = probe;
    });
  }

  Future<void> _trust() async {
    final String? fingerprint = _probe?.certFingerprint;
    if (fingerprint == null) return;
    setState(() => _certPin = fingerprint);
    await _test();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref
        .read(serverBridgeProvider)
        .save(_config, password: _password.text);
    ref.invalidate(serverConfigProvider);
    if (mounted) Navigator.of(context).pop();
  }

  void _explainSecurity(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 22, color: g.accentText),
              const SizedBox(width: GDesign.space12),
              Expanded(
                child: Text(text, style: g.body(color: g.muted)),
              ),
            ],
          ),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space8,
            GDesign.gutter,
            GDesign.space24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(context.s('Where the password goes'), style: g.title2()),
              const SizedBox(height: GDesign.space16),
              point(
                GIcons.lock,
                context.s('Encrypted by this phone and kept on it.'),
              ),
              point(
                GIcons.upload,
                context.s('Sent only to the address above. Nothing of ours.'),
              ),
              point(
                GIcons.key,
                context.s('A new screen lock may ask you to type it again.'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The address
// ─────────────────────────────────────────────────────────────────────────────

/// A WebDAV address, broken into the pieces the native layer needs.
///
/// Parsed in Dart rather than in Kotlin so the result can be shown on screen
/// while it is being typed. A parse that only happened on the other side of the
/// bridge would mean the user learning their path was wrong from a failed
/// connection rather than from looking at it.
@immutable
class DavAddress {
  const DavAddress({
    required this.host,
    required this.port,
    required this.basePath,
    required this.secure,
  });

  /// Null when there is not enough here to be an address.
  ///
  /// Lenient about the scheme, because someone copying from a browser bar gets
  /// one and someone typing from memory does not, and https is the right
  /// assumption for the missing case.
  static DavAddress? parse(String input) {
    final String raw = input.trim();
    if (raw.isEmpty) return null;

    final String withScheme = raw.contains('://') ? raw : 'https://$raw';

    final Uri? uri = Uri.tryParse(withScheme);
    if (uri == null) return null;
    if (uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final bool secure = uri.scheme == 'https';

    return DavAddress(
      host: uri.host,
      // Uri.port returns the scheme default when none was given, which is
      // exactly what is wanted here and is worth not second guessing.
      port: uri.hasPort ? uri.port : (secure ? 443 : 80),
      basePath: _tidy(uri.path),
      secure: secure,
    );
  }

  final String host;
  final int port;

  /// The DAV root, with no leading or trailing slash. Empty is legitimate: some
  /// servers put WebDAV at the domain root.
  final String basePath;

  final bool secure;

  /// The address written back out, for a field the user is editing.
  String get text {
    final String scheme = secure ? 'https' : 'http';
    final bool defaultPort = (secure && port == 443) || (!secure && port == 80);
    final String authority = defaultPort ? host : '$host:$port';
    return basePath.isEmpty
        ? '$scheme://$authority/'
        : '$scheme://$authority/$basePath/';
  }

  static String _tidy(String path) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') return '';
    return trimmed.split('/').where((String s) => s.isNotEmpty).join('/');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The result
// ─────────────────────────────────────────────────────────────────────────────

/// Which outcome a probe describes.
///
/// Read from [ServerProbe.code] rather than from the wording of
/// [ServerProbe.detail], because one of these needs a button and matching on
/// English would break the day these strings are translated.
enum _Outcome { connected, auth, cert, notDav, path, network }

_Outcome _outcomeOf(ServerProbe probe) {
  if (probe.reachable && probe.writable) return _Outcome.connected;
  switch (probe.code) {
    case 'auth':
      return _Outcome.auth;
    case 'cert':
      return _Outcome.cert;
    case 'not_dav':
      return _Outcome.notDav;
    case 'path':
      return _Outcome.path;
    case 'network':
      return _Outcome.network;
    default:
      return probe.reachable ? _Outcome.path : _Outcome.network;
  }
}

/// What the test found: one card with a mark, a title, the server's own
/// words, and for an unknown certificate its fingerprint and Trust.
class _Result extends StatelessWidget {
  const _Result({required this.probe, this.onTrust});

  final ServerProbe probe;
  final VoidCallback? onTrust;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final _Outcome outcome = _outcomeOf(probe);
    final bool ok = outcome == _Outcome.connected;
    final String title = switch (outcome) {
      _Outcome.connected => context.s('Connected'),
      _Outcome.auth => context.s('Sign in failed'),
      _Outcome.cert => context.s('Unknown certificate'),
      _Outcome.notDav => context.s('Not a WebDAV address'),
      _Outcome.path => context.s('The folder refused a file'),
      _Outcome.network => context.s('Could not reach the server'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: g.card,
          borderRadius: BorderRadius.circular(GDesign.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(GDesign.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: ok ? g.accent : g.danger.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      ok ? GIcons.check : GIcons.close,
                      size: 20,
                      color: ok ? g.onAccent : g.danger,
                    ),
                  ),
                  const SizedBox(width: GDesign.space12),
                  Expanded(child: Text(title, style: g.headline())),
                ],
              ),
              if (!ok && probe.detail.isNotEmpty) ...<Widget>[
                const SizedBox(height: GDesign.space8),
                Text(probe.detail, style: g.footnote()),
              ],
              if (ok) ...<Widget>[
                if (probe.freeBytes != null)
                  _Line(
                    label: context.s('Free on server'),
                    value: GFormat.bytes(probe.freeBytes!),
                  ),
                if (probe.serverName != null)
                  _Line(label: context.s('Server'), value: probe.serverName!),
              ],
              if (outcome == _Outcome.cert &&
                  probe.certFingerprint != null) ...<Widget>[
                const SizedBox(height: GDesign.space12),
                Text(
                  _grouped(probe.certFingerprint!),
                  style: g.figures(g.footnote(color: g.text)),
                ),
                const SizedBox(height: GDesign.space12),
                SecondaryButton(
                  label: context.s('Trust this certificate'),
                  onTap: onTrust,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// AB:CD:EF pairs, ten to a line.
  static String _grouped(String hex) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i + 1 < hex.length; i += 2) {
      if (i > 0) out.write(i % 20 == 0 ? '\n' : ':');
      out.write(hex.substring(i, i + 2).toUpperCase());
    }
    return out.toString();
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: GDesign.space8),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: g.footnote())),
          Text(value, style: g.figures(g.footnote(color: g.text))),
        ],
      ),
    );
  }
}

/// A grouped-list row with its label on the left and the field filling the
/// rest, as in iOS Settings forms.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.secret = false,
    this.keyboard = TextInputType.text,
    this.onChanged,
    this.last = false,
  });

  /// The bottom row of its section draws no separator.
  final bool last;
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool secret;
  final TextInputType keyboard;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: GDesign.rowMinHeight),
      margin: const EdgeInsetsDirectional.only(start: GDesign.space16),
      padding: const EdgeInsetsDirectional.only(end: GDesign.space16),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: g.hairline, width: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 104, child: Text(label, style: g.body())),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: secret,
              keyboardType: keyboard,
              onChanged: onChanged,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              cursorColor: g.accent,
              style: g.body(),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: g.body(color: g.faint),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: GDesign.space12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
