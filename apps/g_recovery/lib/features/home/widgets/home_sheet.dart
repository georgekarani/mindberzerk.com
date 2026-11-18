import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../app/theme/tokens.dart';
import '../../../bridge/compress_api.g.dart';
import '../../../bridge/compress_bridge.dart';
import '../../../bridge/messages_api.g.dart';
import '../../../bridge/recovery_api.g.dart';
import '../../../bridge/server_api.g.dart';
import '../../../bridge/server_bridge.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../messages/messages_page.dart';
import '../../messages/state/messages_providers.dart';
import '../../recovery/category_page.dart';
import '../../recovery/state/recovery_providers.dart';
import '../../server/server_page.dart';
import '../../storage/compress/compress_page.dart';
import 'vpn_row.dart';

/// Everything on Home that is not the figure.
///
/// At peek the sheet shows what can come back, as one row of categories.
/// Pulled up it adds only what is true right now (file access off, expiring
/// files, a stale or missing backup), then G VPN and making room. Nothing here
/// starts a scan to fill itself in.
class HomeSheet extends ConsumerWidget {
  const HomeSheet({required this.scroll, super.key});

  /// The sheet's drag controller, so pulling the list moves the sheet.
  final ScrollController scroll;

  /// A backup older than this is worth a row.
  static const int _staleDays = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GTokens t = context.g;
    final GDesignTheme g = GDesignTheme.of(context);
    final RecoverySummary? summary = ref.watch(prescanProvider).value;
    // Statuses and app media are known only after a full scan walks folders.
    final RecoverySummary? full = ref.watch(scanControllerProvider).value;
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;
    final RecoveryAccess? access = ref.watch(recoveryAccessProvider).value;
    final ServerConfig? server = ref.watch(serverConfigProvider).value;
    final TransferState? transfer = ref.watch(transferProvider).value;
    final CompressSummary? compress = ref.watch(compressSummaryProvider).value;

    final List<_Category> categories = _categories(
      context,
      summary,
      full,
      capture,
    )..sort((_Category a, _Category b) => b.count.compareTo(a.count));

    final int expiring = summary?.expiringSoonItems ?? 0;
    final int? lastBackup = transfer?.lastRunMillis;
    final int? backupDays = lastBackup == null
        ? null
        : DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(lastBackup))
              .inDays;

    return ListView(
      controller: scroll,
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + GDesign.space16,
      ),
      children: <Widget>[
        const SheetHandle(),
        SectionLabel(context.s('What can come back')),
        SizedBox(
          height: GDesign.touch,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            children: <Widget>[
              for (final _Category category in categories)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    end: GDesign.space8,
                  ),
                  child: FloatChip(
                    label:
                        '${category.label}  ${GFormat.count(category.count)}',
                    solid: true,
                    tone: category.count > 0 ? null : g.muted,
                    onTap: () => category.open(context),
                  ),
                ),
            ],
          ),
        ),

        // Only what is currently true, most urgent first.
        if (access != null && !access.allFilesAccess)
          EdgeRow(
            leading: Icon(
              Icons.folder_open_rounded,
              size: 22,
              color: t.warning,
            ),
            title: context.s('Turn on file access'),
            subtitle: context.s(
              'Android hides what other apps deleted until you do.',
            ),
            onTap: () async {
              await ref.read(recoveryBridgeProvider).requestAllFilesAccess();
              ref.invalidate(recoveryAccessProvider);
              ref.invalidate(prescanProvider);
            },
          ),
        if (expiring > 0)
          EdgeRow(
            leading: Icon(Icons.timer_outlined, size: 22, color: t.danger),
            title: context.s1(
              '{} expire within 48 hours',
              GFormat.count(expiring),
            ),
            onTap: () => Navigator.of(context).push(
              CategoryPage.route(
                title: context.s('Expiring'),
                sourceIds: kAllSourceIds,
              ),
            ),
          ),
        if (server != null && backupDays != null && backupDays >= _staleDays)
          EdgeRow(
            leading: Icon(Icons.cloud_off_outlined, size: 22, color: t.warning),
            title: context.s1('{} days since the last backup', backupDays),
            onTap: () => Navigator.of(context).push(ServerPage.route()),
          ),
        if (server != null && lastBackup == null)
          EdgeRow(
            leading: Icon(
              Icons.cloud_upload_outlined,
              size: 22,
              color: t.warning,
            ),
            title: context.s('Never backed up to your server'),
            onTap: () => Navigator.of(context).push(ServerPage.route()),
          ),

        // G VPN, before making room: the moment a phone is about to upload
        // recovered files is when public Wi-Fi matters. Hides itself entirely
        // after "Not now" while G VPN is missing.
        const VpnRow(),

        if (compress != null) _CompressRow(summary: compress),
      ],
    );
  }

  /// What can come back, grouped by what happened to it.
  ///
  /// Kinds count deleted items only. Previews, statuses and media still inside
  /// a chat app each get their own chip, so no figure here adds up things the
  /// user would not call "deleted".
  static List<_Category> _categories(
    BuildContext context,
    RecoverySummary? summary,
    RecoverySummary? full,
    MessageCapture? capture,
  ) => <_Category>[
    _Category(
      label: context.s('Photos'),
      count: summary?.imageCount ?? 0,
      kind: 'image',
    ),
    _Category(
      label: context.s('Video'),
      count: summary?.videoCount ?? 0,
      kind: 'video',
    ),
    _Category(
      label: context.s('Messages'),
      count: capture?.messageCount ?? 0,
      messages: true,
    ),
    _Category(
      label: context.s('Docs'),
      count: summary?.documentCount ?? 0,
      kind: 'document',
    ),
    _Category(
      label: context.s('Audio'),
      count: summary?.audioCount ?? 0,
      kind: 'audio',
    ),
    _Category(
      label: context.s('Previews'),
      count: full?.previewItems ?? summary?.previewItems ?? 0,
      sourceIds: const <String>['thumbnails'],
      roles: const <String>{kRoleCache},
    ),
    if ((full?.statusItems ?? 0) > 0)
      _Category(
        label: context.s('Statuses'),
        count: full!.statusItems,
        sourceIds: const <String>['app_trash'],
        roles: const <String>{kRoleStatus},
      ),
    if ((full?.appMediaItems ?? 0) > 0)
      _Category(
        label: context.s('Still in chat apps'),
        count: full!.appMediaItems,
        roles: const <String>{kRoleMedia},
      ),
  ];
}

@immutable
class _Category {
  const _Category({
    required this.label,
    required this.count,
    this.kind,
    this.sourceIds,
    this.roles = kRolesDeleted,
    this.messages = false,
  });

  final String label;
  final int count;
  final String? kind;
  final List<String>? sourceIds;
  final Set<String> roles;
  final bool messages;

  void open(BuildContext context) {
    if (messages) {
      Navigator.of(context).push(MessagesPage.route());
      return;
    }
    Navigator.of(context).push(
      CategoryPage.route(
        title: label,
        kind: kind,
        sourceIds: sourceIds ?? kAllSourceIds,
        roles: roles,
      ),
    );
  }
}

/// Files that could take less room, without deleting anything.
///
/// Hidden when nothing qualifies: an offer to shrink zero files is noise.
class _CompressRow extends StatelessWidget {
  const _CompressRow({required this.summary});

  final CompressSummary summary;

  @override
  Widget build(BuildContext context) {
    final GTokens t = context.g;
    final int shots = summary.screenshotCount;
    final int photos = summary.photoCount;
    final int clips = summary.videoCount ?? 0;
    if (shots == 0 && photos == 0 && clips == 0) {
      return const SizedBox.shrink();
    }

    final int held =
        summary.screenshotBytes +
        summary.photoBytes +
        (summary.videoBytes ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(context.s('Make room without deleting')),
        EdgeRow(
          leading: Icon(Icons.compress_rounded, size: 22, color: t.muted),
          title: context.s('Make files smaller'),
          subtitle: _parts(shots, photos, clips),
          value: GFormat.bytes(held),
          divider: false,
          onTap: () => Navigator.of(context).push(CompressPage.route()),
        ),
      ],
    );
  }

  static String _parts(int shots, int photos, int clips) {
    final List<String> parts = <String>[
      if (shots > 0)
        '${GFormat.count(shots)} ${shots == 1 ? 'screenshot' : 'screenshots'}',
      if (photos > 0)
        '${GFormat.count(photos)} ${photos == 1 ? 'photo' : 'photos'}',
      if (clips > 0) '${GFormat.count(clips)} ${clips == 1 ? 'clip' : 'clips'}',
    ];
    if (parts.length <= 1) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}
