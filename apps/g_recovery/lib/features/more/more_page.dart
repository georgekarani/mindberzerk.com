import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/theme/theme_controller.dart';
import '../../bridge/content_api.g.dart';
import '../../bridge/messages_api.g.dart';
import '../../bridge/recovery_api.g.dart';
import '../../bridge/server_api.g.dart';
import '../../bridge/server_bridge.dart';
import '../../bridge/storage_api.g.dart';
import '../../core/app_info.dart';
import '../../core/content/content_store.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../core/messenger/g_message.dart';
import '../../core/messenger/g_messenger.dart';
import '../../core/update/app_update.dart';
import '../../ui/file_thumbnail.dart';
import '../../ui/g_sort.dart';
import '../learn/limits_page.dart';
import '../messages/state/messages_providers.dart';
import '../recovery/state/recovery_providers.dart';
import '../server/server_page.dart';
import '../storage/browse/browse_page.dart';
import '../storage/state/storage_files.dart';
import '../storage/state/storage_providers.dart';
import 'language_page.dart';
import 'settings_pages.dart';

/// The newest photos on the phone, for the Home server card's stack.
const StorageScope _recentPhotos = StorageScope(
  title: 'Recent photos',
  kind: 'image',
  sort: GSortMode.newest,
);

/// More: the Home server as a photo card, then three grouped lists.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecoveryAccess? access = ref.watch(recoveryAccessProvider).value;
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;
    final GThemeState theme = ref.watch(gThemeProvider);
    final GUpdateState update = ref.watch(gUpdateProvider);
    final GAppInfo appInfo = ref.watch(gAppInfoProvider);
    final int off = _missing(access, capture);

    return LargeTitlePage(
      title: context.s('More'),
      grouped: true,
      slivers: <Widget>[
        const SliverToBoxAdapter(child: _ServerCard()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space24),
            child: GroupedSection(
              header: context.s('Your phone'),
              children: <Widget>[
                ListRow(
                  icon: GIcons.folderOpen,
                  title: context.s('Browse files'),
                  onTap: () => Navigator.of(
                    context,
                  ).push(BrowsePage.route(backLabel: context.s('More'))),
                ),
                ListRow(
                  icon: GIcons.help,
                  title: context.s('What can come back'),
                  onTap: () => Navigator.of(context).push(LimitsPage.route()),
                ),
                ListRow(
                  icon: GIcons.messages,
                  title: context.s('Keep deleted messages'),
                  subtitle: (capture?.capturing ?? false)
                      ? context.s1(
                          '{} kept',
                          GFormat.count(capture!.messageCount),
                        )
                      : null,
                  trailing: ToggleSwitch(
                    value: capture?.capturing ?? false,
                    semanticLabel: context.s('Keep deleted messages'),
                    onChanged: (bool value) async {
                      await ref
                          .read(messagesBridgeProvider)
                          .setCapturing(value: value);
                      ref.invalidate(messageCaptureProvider);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space24),
            child: GroupedSection(
              header: context.s('Settings'),
              children: <Widget>[
                ListRow(
                  icon: theme.mode == ThemeMode.dark ? GIcons.moon : GIcons.sun,
                  title: context.s('Appearance'),
                  detail: _modeName(context, theme.mode),
                  onTap: () =>
                      Navigator.of(context).push(AppearancePage.route()),
                ),
                ListRow(
                  icon: GIcons.globe,
                  title: context.s('Language'),
                  detail: GLanguage.forCode(
                    ref.watch(gLocaleProvider),
                  ).nativeName,
                  onTap: () => Navigator.of(context).push(LanguagePage.route()),
                ),
                ListRow(
                  icon: GIcons.key,
                  title: context.s('Permissions'),
                  detail: off == 0
                      ? context.s('All on')
                      : context.s1('{} off', '$off'),
                  onTap: () =>
                      Navigator.of(context).push(PermissionsPage.route()),
                ),
                ListRow(
                  icon: GIcons.shield,
                  title: context.s('Privacy'),
                  onTap: () => Navigator.of(context).push(PrivacyPage.route()),
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
              header: 'G Recovery',
              children: <Widget>[
                const _CoverageRow(),
                ListRow(
                  icon: GIcons.info,
                  title: context.s('Version'),
                  detail: appInfo.hasVersion ? appInfo.version : null,
                  onTap: _updateVisible(update.stage)
                      ? null
                      : () => _tapUpdate(context, ref, update),
                ),
                if (_updateVisible(update.stage))
                  ListRow(
                    icon: _updateIcon(update.stage),
                    title: _updateTitle(context, update.stage),
                    subtitle: _updateDetail(context, update),
                    onTap: () => _tapUpdate(context, ref, update),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _updateVisible(GUpdateStage stage) =>
      stage != GUpdateStage.idle &&
      stage != GUpdateStage.unavailable &&
      stage != GUpdateStage.current;

  static IconData _updateIcon(GUpdateStage stage) => switch (stage) {
    GUpdateStage.available => GIcons.download,
    GUpdateStage.downloading => GIcons.hourglass,
    GUpdateStage.ready => GIcons.refresh,
    _ => GIcons.checkCircle,
  };

  static String _updateTitle(BuildContext context, GUpdateStage stage) =>
      switch (stage) {
        GUpdateStage.available => context.s('Update available'),
        GUpdateStage.downloading => context.s('Downloading update'),
        GUpdateStage.ready => context.s('Restart to finish updating'),
        GUpdateStage.checking => context.s('Checking'),
        _ => context.s('Up to date'),
      };

  static String? _updateDetail(BuildContext context, GUpdateState update) {
    // The title says it all; only a finished download needs a hint.
    return update.stage == GUpdateStage.ready
        ? context.s('Tap to restart')
        : null;
  }

  /// Installs, downloads or checks, depending on where the update stands.
  static Future<void> _tapUpdate(
    BuildContext context,
    WidgetRef ref,
    GUpdateState update,
  ) async {
    final GUpdateController controller = ref.read(gUpdateProvider.notifier);
    if (update.stage == GUpdateStage.downloading) return;

    if (update.stage == GUpdateStage.ready) {
      final GUpdateOutcome outcome = await controller.install();
      if (!context.mounted || outcome == GUpdateOutcome.done) return;
      GMessenger.show(
        context,
        GMessage.danger(context.s('Play could not install the update')),
      );
      return;
    }

    if (update.stage == GUpdateStage.available) {
      final bool immediate =
          update.immediateAllowed &&
          (update.isUrgent || !update.flexibleAllowed);
      final GUpdateOutcome outcome = immediate
          ? await controller.updateNow()
          : await controller.download();
      if (!context.mounted) return;
      if (outcome == GUpdateOutcome.failed ||
          outcome == GUpdateOutcome.notPossible) {
        GMessenger.show(
          context,
          GMessage.warning(context.s('Play could not start the update')),
        );
      }
      return;
    }

    final GUpdateOutcome outcome = await controller.refresh(force: true);
    if (!context.mounted) return;
    if (outcome != GUpdateOutcome.done) {
      GMessenger.show(
        context,
        GMessage.warning(context.s('Play did not answer')),
      );
      return;
    }
    if (ref.read(gUpdateProvider).stage == GUpdateStage.current) {
      GMessenger.show(
        context,
        GMessage.success(context.s('This is the newest build')),
      );
    }
  }

  static String _modeName(BuildContext context, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => context.s('Auto'),
        ThemeMode.light => context.s('Light'),
        ThemeMode.dark => context.s('Dark'),
      };

  /// How many of the two access switches are off.
  static int _missing(RecoveryAccess? access, MessageCapture? capture) =>
      <bool>[
        access?.allFilesAccess ?? false,
        capture?.listenerEnabled ?? false,
      ].where((bool on) => !on).length;
}

/// The Home server, led by three of the user's newest photos fanned out:
/// what it does is copy exactly these somewhere they own.
class _ServerCard extends ConsumerWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final ServerConfig? server = ref.watch(serverConfigProvider).value;
    final List<StorageFile> recent =
        ref.watch(storageFilesProvider(_recentPhotos)).value?.files ??
        const <StorageFile>[];
    final List<ImageProvider> stack = <ImageProvider>[
      for (final StorageFile f in recent.take(3))
        FileThumbnail(
          fileId: f.fileId,
          bridge: ref.watch(storageBridgeProvider),
          maxPixels: 160,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        0,
      ),
      child: Pressable(
        onTap: () => Navigator.of(context).push(ServerPage.route()),
        scale: 0.98,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: g.card,
            borderRadius: BorderRadius.circular(GDesign.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(GDesign.space16),
            child: Row(
              children: <Widget>[
                _Fan(photos: stack),
                const SizedBox(width: GDesign.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        server?.label ?? context.s('Home server'),
                        style: g.headline(),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        server == null
                            ? context.s(
                                'Copy your photos to a computer you own',
                              )
                            : context.s(
                                'Your photos, copied to a machine you own',
                              ),
                        style: g.footnote(),
                      ),
                    ],
                  ),
                ),
                Icon(GIcons.forward, size: 18, color: g.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three photos overlapping like a small stack of prints.
class _Fan extends StatelessWidget {
  const _Fan({required this.photos});

  final List<ImageProvider> photos;

  static const double _side = 56;
  static const double _step = 14;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return SizedBox(
      width: _side + 2 * _step,
      height: _side + 8,
      child: Stack(
        children: <Widget>[
          for (int i = 0; i < 3; i++)
            PositionedDirectional(
              start: i * _step,
              top: i * 4.0,
              child: Container(
                width: _side,
                height: _side,
                decoration: BoxDecoration(
                  color: g.fill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: g.card, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: i < photos.length
                    ? SizedPhoto(image: photos[i])
                    : Icon(GIcons.photos, size: 20, color: g.faint),
              ),
            ),
        ],
      ),
    );
  }
}

/// The recovery knowledge (folders, apps, how each hides deleted files),
/// which updates without a new app version. Tapping checks again.
class _CoverageRow extends ConsumerWidget {
  const _CoverageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ContentPackInfo> packs =
        ref.watch(installedPacksProvider).value ?? const <ContentPackInfo>[];
    final ContentSyncResult? sync = ref.watch(contentSyncProvider).value;
    return ListRow(
      icon: GIcons.shieldCheck,
      title: context.s('Recovery coverage'),
      detail: switch (sync?.status) {
        'updated' => context.s('Updated'),
        'upToDate' => context.s('Current'),
        'offline' => context.s('Offline'),
        null => null,
        _ => context.s('Retry'),
      },
      subtitle: packs.isEmpty
          ? context.s('Built into this version')
          : context.s('Updates without a new app version'),
      onTap: () {
        ref.invalidate(contentSyncProvider);
        ref.invalidate(installedPacksProvider);
      },
    );
  }
}
