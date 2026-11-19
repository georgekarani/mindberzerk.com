import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../bridge/server_api.g.dart';
import '../../bridge/server_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import 'reclaim_page.dart';
import 'server_setup_page.dart';

/// The home server: where it stands, back up now, when it runs, the
/// server's facts, and forgetting it. With no server yet, the two kinds
/// that can be set up.
class ServerPage extends ConsumerWidget {
  const ServerPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const ServerPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ServerConfig? config = ref.watch(serverConfigProvider).value;
    if (config == null) return const _Empty();

    final GDesignTheme g = GDesignTheme.of(context);
    final TransferState? state = ref.watch(transferProvider).value;
    final bool running = state?.running ?? false;

    return LargeTitlePage(
      title: config.label,
      backLabel: context.s('More'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.settings,
          semanticLabel: context.s('Edit server'),
          onTap: () => Navigator.of(
            context,
          ).push(ServerSetupPage.route(existing: config)),
        ),
      ],
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GDesign.gutter,
              0,
              GDesign.gutter,
              GDesign.space16,
            ),
            child: Text(
              config.protocol == 'webdav'
                  ? context.s('WebDAV, reachable from anywhere')
                  : context.s('Windows share, on your home network only'),
              style: g.footnote(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            child: _State(
              state: state,
              action: running
                  ? SecondaryButton(
                      label: context.s('Stop'),
                      onTap: () => _toggleRun(ref, running: true),
                    )
                  : PrimaryButton(
                      label: context.s('Back up now'),
                      icon: GIcons.upload,
                      onTap: () => _toggleRun(ref, running: false),
                    ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: _Reclaim()),
        SliverToBoxAdapter(child: _Schedule(config: config)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space24),
            child: GroupedSection(
              header: context.s('Server'),
              children: <Widget>[
                ListRow(title: context.s('Address'), detail: _address(config)),
                if (config.share != null)
                  ListRow(title: context.s('Share'), detail: config.share),
                ListRow(title: context.s('Folder'), detail: config.remotePath),
                ListRow(
                  title: context.s('Signed in as'),
                  detail: config.username,
                ),
                if (config.protocol == 'webdav')
                  ListRow(
                    title: context.s('Certificate'),
                    detail: config.certPin == null
                        ? context.s('Public authority')
                        : context.s('Pinned by you'),
                  ),
                ListRow(
                  title: context.s('Files'),
                  detail: config.encrypt
                      ? context.s('Encrypted')
                      : context.s('Readable'),
                  subtitle: config.encrypt
                      ? context.s('Only this app can open them')
                      : context.s('Any app on your computer can open them'),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: GDesign.space24,
              bottom: GDesign.space32,
            ),
            child: GroupedSection(
              footer: context.s('Nothing on the server is touched or deleted.'),
              children: <Widget>[
                ListRow(
                  icon: GIcons.close,
                  title: context.s('Forget this server'),
                  destructive: true,
                  onTap: () => _confirmForget(context, ref),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Future<void> _toggleRun(WidgetRef ref, {required bool running}) async {
    final ServerBridge bridge = ref.read(serverBridgeProvider);
    if (running) {
      Haptics.select();
      await bridge.cancelBackup();
    } else {
      Haptics.confirm();
      await bridge.startBackup();
    }
    ref.invalidate(transferProvider);
  }

  /// The address as the user would type it into a browser.
  static String _address(ServerConfig config) {
    if (config.protocol != 'webdav') return config.host;
    final String scheme = (config.secure ?? true) ? 'https' : 'http';
    final int port = config.port;
    final bool standard =
        (scheme == 'https' && port == 443) || (scheme == 'http' && port == 80);
    final String authority = standard ? config.host : '${config.host}:$port';
    final String base = config.basePath ?? '';
    return base.isEmpty
        ? '$scheme://$authority/'
        : '$scheme://$authority/$base/';
  }

  Future<void> _confirmForget(BuildContext context, WidgetRef ref) async {
    final bool go = await showConfirmSheet(
      context: context,
      title: context.s('Forget this server'),
      message: context.s(
        'The address and password are removed from this phone. Everything '
        'already copied stays on the server, untouched.',
      ),
      confirmLabel: context.s('Forget'),
      cancelLabel: context.s('Keep'),
    );
    if (!go) return;
    await ref.read(serverBridgeProvider).forget();
    ref.invalidate(serverConfigProvider);
  }
}

/// Where the backup stands, with progress while copying, and the main
/// action at the bottom of the card.
class _State extends StatelessWidget {
  const _State({required this.state, required this.action});

  final TransferState? state;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final TransferState? s = state;
    final String title;
    final String body;
    Widget? extra;

    if (s == null || (s.lastRunMillis == null && !s.running)) {
      title = context.s('Ready');
      body = context.s('Nothing copied yet.');
    } else if (s.running) {
      final bool measured = s.bytesTotal > 0;
      title = context.s('Copying');
      body = s.currentName ?? context.s('Working through the list');
      extra = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: GDesign.space12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: measured ? s.bytesSent / s.bytesTotal : null,
              minHeight: 6,
              color: g.accent,
              backgroundColor: g.isDark ? g.hairline : g.fill,
            ),
          ),
          const SizedBox(height: GDesign.space8),
          Text(
            '${GFormat.count(s.sent)} / ${GFormat.count(s.total)}, '
            '${GFormat.bytes(s.bytesSent)} / ${GFormat.bytes(s.bytesTotal)}',
            style: g.figures(g.footnote()),
          ),
        ],
      );
    } else {
      final bool failed = s.lastError != null;
      title = failed
          ? context.s('Finished with problems')
          : context.s('Up to date');
      body = failed
          ? s.lastError!
          : context.s1('Last run {}', _ago(context, s.lastRunMillis!));
      if (s.sent > 0) {
        extra = Padding(
          padding: const EdgeInsets.only(top: GDesign.space16),
          child: Row(
            children: <Widget>[
              _Stat(
                value: GFormat.count(s.sent),
                label: context.s('files sent'),
              ),
              _Stat(
                value: GFormat.bytes(s.bytesSent),
                label: context.s('copied'),
              ),
              if (s.failed > 0)
                _Stat(
                  value: GFormat.count(s.failed),
                  label: context.s('could not be sent'),
                ),
            ],
          ),
        );
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.card,
        borderRadius: BorderRadius.circular(GDesign.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(GDesign.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: g.title2()),
            const SizedBox(height: GDesign.space4),
            Text(body, style: g.body(color: g.muted)),
            ?extra,
            const SizedBox(height: GDesign.space16),
            action,
          ],
        ),
      ),
    );
  }

  static String _ago(BuildContext context, int millis) {
    final Duration since = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(millis),
    );
    if (since.inMinutes < 1) return context.s('just now');
    if (since.inMinutes < 60) {
      return context.s1('{} minutes ago', '${since.inMinutes}');
    }
    if (since.inHours < 24) {
      return context.s1('{} hours ago', '${since.inHours}');
    }
    return context.s1('{} days ago', '${since.inDays}');
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: g.figures(g.headline()),
          ),
          Text(label, style: g.footnote()),
        ],
      ),
    );
  }
}

/// Space that can be freed because the files are verified on the server.
class _Reclaim extends ConsumerWidget {
  const _Reclaim();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ReclaimCandidate> ready =
        (ref.watch(reclaimableProvider).value ?? const <ReclaimCandidate>[])
            .where((ReclaimCandidate c) => c.verified)
            .toList();
    if (ready.isEmpty) return const SizedBox.shrink();
    final int bytes = ready.fold<int>(
      0,
      (int sum, ReclaimCandidate c) => sum + c.sizeBytes,
    );
    return Padding(
      padding: const EdgeInsets.only(top: GDesign.space24),
      child: GroupedSection(
        header: context.s('Free up space'),
        children: <Widget>[
          ListRow(
            icon: GIcons.sparkles,
            title: context.s1('{} can be reclaimed', GFormat.bytes(bytes)),
            subtitle: context.s1(
              '{} files already on the server',
              GFormat.count(ready.length),
            ),
            onTap: () => Navigator.of(context).push(ReclaimPage.route()),
          ),
        ],
      ),
    );
  }
}

/// When backups run: on their own, Wi-Fi only, while charging.
class _Schedule extends ConsumerWidget {
  const _Schedule({required this.config});

  final ServerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? next = ref.watch(nextRunProvider).value;
    return Padding(
      padding: const EdgeInsets.only(top: GDesign.space24),
      child: GroupedSection(
        header: context.s('When'),
        children: <Widget>[
          ListRow(
            title: context.s('Back up on its own'),
            subtitle: !config.scheduled
                ? context.s('Only when you tap Back up now')
                : next == null
                ? context.s('About once a day')
                : context.s1('Next run {}', _when(context, next)),
            trailing: ToggleSwitch(
              value: config.scheduled,
              semanticLabel: context.s('Back up on its own'),
              onChanged: (bool _) async {
                await ref
                    .read(serverBridgeProvider)
                    .setSchedule(enabled: !config.scheduled);
                ref.invalidate(serverConfigProvider);
                ref.invalidate(nextRunProvider);
              },
            ),
          ),
          ListRow(
            title: context.s('Wi-Fi only'),
            subtitle: context.s('Never on mobile data'),
            trailing: ToggleSwitch(
              value: config.wifiOnly,
              semanticLabel: context.s('Wi-Fi only'),
              onChanged: (bool v) => _save(ref, wifiOnly: v),
            ),
          ),
          ListRow(
            title: context.s('While charging'),
            subtitle: context.s('Waits for a charger before starting'),
            trailing: ToggleSwitch(
              value: config.whileCharging,
              semanticLabel: context.s('While charging'),
              onChanged: (bool v) => _save(ref, charging: v),
            ),
          ),
        ],
      ),
    );
  }

  /// Saves one changed condition, keeping every other field as it was.
  Future<void> _save(WidgetRef ref, {bool? wifiOnly, bool? charging}) async {
    final ServerConfig next = ServerConfig(
      id: config.id,
      protocol: config.protocol,
      label: config.label,
      host: config.host,
      port: config.port,
      share: config.share,
      username: config.username,
      remotePath: config.remotePath,
      encrypt: config.encrypt,
      wifiOnly: wifiOnly ?? config.wifiOnly,
      whileCharging: charging ?? config.whileCharging,
      scheduled: config.scheduled,
      secure: config.secure,
      basePath: config.basePath,
      certPin: config.certPin,
    );
    final ServerBridge bridge = ref.read(serverBridgeProvider);
    await bridge.save(next);
    if (next.scheduled) await bridge.setSchedule(enabled: true);
    ref.invalidate(serverConfigProvider);
    ref.invalidate(nextRunProvider);
  }

  static String _when(BuildContext context, int millis) {
    final Duration until = DateTime.fromMillisecondsSinceEpoch(
      millis,
    ).difference(DateTime.now());
    if (until.isNegative) return context.s('due now');
    if (until.inHours < 1) {
      return context.s1('in {} minutes', '${until.inMinutes}');
    }
    if (until.inHours < 24) {
      return context.s1('in {} hours', '${until.inHours}');
    }
    return context.s1('in {} days', '${until.inDays}');
  }
}

/// No server yet: what it is, the two kinds, and how it works.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return LargeTitlePage(
      title: context.s('Home server'),
      backLabel: context.s('More'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GDesign.gutter,
              GDesign.space8,
              GDesign.gutter,
              GDesign.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: g.card,
                    borderRadius: BorderRadius.circular(GDesign.cardRadius),
                  ),
                  child: Icon(GIcons.server, size: 30, color: g.accentText),
                ),
                const SizedBox(height: GDesign.space16),
                Text(
                  context.s('Your files, on your own machine'),
                  style: g.title2(),
                ),
                const SizedBox(height: GDesign.space8),
                Text(
                  context.s('No account. Nothing passes through us.'),
                  style: g.body(color: g.muted),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: context.s('Choose your server'),
            children: <Widget>[
              ListRow(
                icon: GIcons.monitor,
                title: context.s('Windows share'),
                subtitle: context.s('Home network only'),
                onTap: () => Navigator.of(
                  context,
                ).push(ServerSetupPage.route(protocol: 'smb')),
              ),
              ListRow(
                icon: GIcons.globe,
                title: 'WebDAV',
                subtitle: context.s('Nextcloud and others, from anywhere'),
                onTap: () => Navigator.of(
                  context,
                ).push(ServerSetupPage.route(protocol: 'webdav')),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: GDesign.space24,
              bottom: GDesign.space32,
            ),
            child: GroupedSection(
              children: <Widget>[
                ListRow(
                  icon: GIcons.help,
                  title: context.s('How this works'),
                  onTap: () => _explain(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _explain(BuildContext context) {
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
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space8,
            GDesign.gutter,
            GDesign.space24,
          ),
          children: <Widget>[
            Text(context.s('How this works'), style: g.title2()),
            const SizedBox(height: GDesign.space16),
            point(
              GIcons.upload,
              context.s(
                'Files go one way, from the phone to your server. Deleting '
                'something on the server never deletes it here.',
              ),
            ),
            point(
              GIcons.folder,
              context.s(
                'Your folders are kept, so the copy can be browsed with '
                'anything, not just this app.',
              ),
            ),
            point(
              GIcons.wifi,
              context.s(
                'A Windows share works only on the same network. WebDAV over '
                'https works from anywhere, so an overnight backup away from '
                'home is possible.',
              ),
            ),
          ],
        );
      },
    );
  }
}
