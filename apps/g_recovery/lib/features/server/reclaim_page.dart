import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/shell.dart';
import '../../bridge/server_api.g.dart';
import '../../bridge/server_bridge.dart';
import '../../bridge/storage_api.g.dart';
import '../../bridge/storage_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../core/messenger/g_message.dart';
import '../../core/messenger/g_messenger.dart';
import '../../ui/file_thumbnail.dart';
import '../device/widgets/device_detail.dart';
import '../storage/state/storage_providers.dart';

/// Files already on the home server that can leave the phone.
///
/// Nothing is removed on trust: each picked file is hashed here and on the
/// server first, and only matches go to the trash, where Android keeps them
/// for 30 days.
class ReclaimPage extends ConsumerStatefulWidget {
  const ReclaimPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const ReclaimPage(),
  );

  @override
  ConsumerState<ReclaimPage> createState() => _ReclaimPageState();
}

class _ReclaimPageState extends ConsumerState<ReclaimPage> {
  final Set<String> _picked = <String>{};

  /// Files whose copies did not match on the last run; kept and shown.
  final Set<String> _failed = <String>{};

  /// What the run is doing, or null when idle.
  String? _stage;

  late final GShellNav _nav = ref.read(gShellNavHiddenProvider.notifier);

  @override
  void initState() {
    super.initState();
    _nav.hide();
  }

  @override
  void dispose() {
    _nav.show();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final StorageBridge bridge = ref.watch(storageBridgeProvider);
    final AsyncValue<List<ReclaimCandidate>> source = ref.watch(
      reclaimableProvider,
    );
    final List<ReclaimCandidate> all =
        source.value ?? const <ReclaimCandidate>[];
    final List<ReclaimCandidate> ready = all
        .where((ReclaimCandidate c) => c.verified)
        .toList();
    final int total = _sum(ready);
    final int picked = _sum(
      ready.where((ReclaimCandidate c) => _picked.contains(c.fileId)),
    );
    final bool busy = _stage != null;
    final bool everything = _picked.length == ready.length;
    final int? download = _remoteCost(total);

    return LargeTitlePage(
      title: context.s('Free up space'),
      backLabel: context.s('Home server'),
      onBack: () => Navigator.of(context).maybePop(),
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.info,
          semanticLabel: context.s('How this is checked'),
          onTap: () => showDeviceNote(
            context,
            context.s('How this is checked'),
            <String>[
              context.s(
                'Each file is hashed on the phone and on the server. Only '
                'files whose copies match are removed.',
              ),
              context.s(
                'Removed files go to the trash, where Android keeps them for '
                '30 days.',
              ),
              if (download != null)
                context.s(
                  'This server is outside your network, so checking reads '
                  'each copy back. On mobile data that uses as much data as '
                  'the space you free.',
                ),
            ],
          ),
        ),
      ],
      bottom: busy || ready.isEmpty
          ? null
          : ActionBar(
              leading: BarIconButton(
                icon: GIcons.checkCircle,
                semanticLabel: everything
                    ? context.s('Select none')
                    : context.s('Select all'),
                onTap: () => setState(() {
                  if (everything) {
                    _picked.clear();
                  } else {
                    _picked.addAll(ready.map((ReclaimCandidate c) => c.fileId));
                  }
                }),
              ),
              center: PrimaryButton(
                label: _picked.isEmpty
                    ? context.s('Tap files to pick')
                    : context.s1('Check and free {}', GFormat.bytes(picked)),
                onTap: _picked.isEmpty ? null : _run,
              ),
            ),
      bottomExtent: busy || ready.isEmpty ? 0 : ActionBar.extent(context),
      slivers: <Widget>[
        if (busy)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator.adaptive(),
                  const SizedBox(height: GDesign.space16),
                  Text(_stage!, style: g.headline()),
                ],
              ),
            ),
          )
        else if (!source.hasValue)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (ready.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Reveal(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(GIcons.server, size: 48, color: g.faint),
                    const SizedBox(height: GDesign.space12),
                    Text(
                      all.isEmpty
                          ? context.s('Back up first')
                          : context.s('Nothing matches the server'),
                      style: g.headline(),
                    ),
                    Text(
                      context.s('Files the server holds will show here'),
                      style: g.footnote(),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...<Widget>[
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
                  CountUpText(
                    value: total,
                    format: (num v) => context.s1(
                      '{} safe to remove',
                      GFormat.bytes(v.round()),
                    ),
                    style: g.figures(g.largeTitle()),
                  ),
                  Text(
                    download == null
                        ? context.s1(
                            '{} files already on your server',
                            GFormat.count(ready.length),
                          )
                        : context.s('Checking uses data off Wi-Fi'),
                    style: g.footnote(),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: ready.length,
              itemBuilder: (BuildContext context, int i) {
                final ReclaimCandidate c = ready[i];
                final bool failed = _failed.contains(c.fileId);
                return PhotoGridTile(
                  image: FileThumbnail(
                    fileId: c.fileId,
                    bridge: bridge,
                    name: c.name,
                  ),
                  selected: _picked.contains(c.fileId),
                  badge: PhotoChip(
                    failed ? context.s('Kept') : GFormat.bytes(c.sizeBytes),
                  ),
                  onTap: failed
                      ? null
                      : () => setState(() {
                          if (!_picked.remove(c.fileId)) _picked.add(c.fileId);
                        }),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: GDesign.space24)),
        ],
      ],
    );
  }

  static int _sum(Iterable<ReclaimCandidate> items) =>
      items.fold<int>(0, (int s, ReclaimCandidate c) => s + c.sizeBytes);

  /// Bytes a full check would download, or null when the server is on the
  /// local network and checking is free.
  int? _remoteCost(int bytes) {
    final ServerConfig? config = ref.watch(serverConfigProvider).value;
    if (config == null || !_isRemote(config)) return null;
    return bytes;
  }

  /// WebDAV to a public host. SMB and private address ranges are local.
  static bool _isRemote(ServerConfig config) {
    if (config.protocol != 'webdav') return false;
    final String host = config.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.local')) return false;
    if (!host.contains('.')) return false;
    if (host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('169.254.')) {
      return false;
    }
    final List<String> parts = host.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final int? second = int.tryParse(parts[1]);
      if (second != null && second >= 16 && second <= 31) return false;
    }
    return true;
  }

  Future<void> _run() async {
    setState(() {
      _stage = context.s('Checking the server copies');
      _failed.clear();
    });
    final List<String> chosen = _picked.toList();
    final List<String> verified = await ref
        .read(serverBridgeProvider)
        .verify(chosen);
    if (!mounted) return;

    final Set<String> ok = verified.toSet();
    final List<String> failed = <String>[
      for (final String id in chosen)
        if (!ok.contains(id)) id,
    ];
    if (verified.isEmpty) {
      setState(() {
        _stage = null;
        _failed.addAll(failed);
      });
      GMessenger.show(
        context,
        GMessage(context.s('Nothing matched. All kept.')),
      );
      return;
    }

    setState(() => _stage = context.s('Moving to the trash'));
    final List<StorageOutcome> outcomes = await ref
        .read(storageBridgeProvider)
        .remove(verified, permanent: false);
    if (!mounted) return;

    final int removed = outcomes
        .where(
          (StorageOutcome o) => o.status == 'trashed' || o.status == 'deleted',
        )
        .length;
    setState(() {
      _stage = null;
      _picked.removeAll(verified);
      _failed.addAll(failed);
    });
    ref
      ..invalidate(reclaimableProvider)
      ..invalidate(storageOverviewProvider);
    Haptics.confirm();
    GMessenger.show(
      context,
      failed.isEmpty
          ? GMessage.success(
              context.s1('{} moved to the trash', GFormat.count(removed)),
            )
          : GMessage(
              context.s1(
                '{} freed. Some did not match and were kept.',
                GFormat.count(removed),
              ),
            ),
    );
  }
}
