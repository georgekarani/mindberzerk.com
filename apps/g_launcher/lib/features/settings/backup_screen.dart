import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/backup_folder.dart';
import '../../data/prefs/backup_schedule.dart';
import '../../data/prefs/backup_store.dart';
import '../../data/prefs/prefs_backup.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../data/prefs/wallpaper_collections.dart';
import '../../data/repositories/app_repository.dart';
import '../../design/branded_message.dart';
import '../../design/components/components.dart';
import 'backup_format.dart';
import 'backup_restore_screen.dart';

/// Settings > Backup.
///
/// Backups are always on. The only choices are how often and whether the
/// user's own wallpaper photos go along. Every backup lands in app storage and
/// in Documents/GLauncher on the phone, under one fixed file name, so a
/// restore always knows what to open. See [BackupsNotifier].
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Picks up backups that reached the folder from elsewhere (an older
    // install, another phone) before the list is drawn.
    ref.read(backupsProvider.notifier).absorbFolder();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backUp() => _guard(() async {
        final record = await ref.read(backupsProvider.notifier).create();
        if (!mounted) return;
        context.showMessage(
          record == null
              ? context.t('settings.backup.failed')
              : context.t('settings.backup.done'),
        );
      });

  Future<void> _findBackups() => _guard(() async {
        final picked = await ref.read(backupFolderProvider.notifier).choose();
        if (picked == null || !mounted) return;
        final added = await ref.read(backupsProvider.notifier).absorbFolder();
        if (!mounted) return;

        // ─── STRAIGHT TO THE ONE THEY CAME FOR ────────────────────────────
        //
        // This reported a count and left a list to read. Someone who has just
        // pointed at their backup folder wants the newest backup in it, so
        // that one opens. The rest stay in the list behind it.
        final found = _newestBroughtIn(
          ref.read(backupsProvider).value ?? const [],
        );
        if (added > 0 && found != null) {
          _openRestore(found);
          return;
        }

        context.showMessage(switch (added) {
          0 => context.t('settings.backup.noneInFolder'),
          1 => context.t('settings.backup.foundOne'),
          _ => context.t('settings.backup.foundCount', {'count': '$added'}),
        });
      });

  /// Settings only, never photos: a copy sent to another phone should be a
  /// message-sized file.
  Future<void> _send() => _guard(() async {
        final Uint8List bytes;
        try {
          bytes = await PrefsBackup.encode(
            store: ref.read(prefsStoreProvider),
            repo: ref.read(prefsRepositoryProvider),
            collections: await ref.read(wallpaperCollectionsProvider.future),
            includeWallpapers: false,
            deviceLabel: await ref.read(deviceLabelProvider.future),
            installedApps: const {},
          );
        } catch (_) {
          if (mounted) {
            context.showMessage(context.t('settings.backup.prepareFailed'));
          }
          return;
        }
        final ok = await ref
            .read(launcherHostApiProvider)
            .shareBackup(PrefsBackup.suggestedFileName(), bytes);
        if (!ok && mounted) {
          context.showMessage(context.t('settings.backup.sendFailed'));
        }
      });

  Future<void> _open() => _guard(() async {
        final file = await FilePicker.pickFile(type: FileType.any);
        if (file == null) return;

        final bytes = Uint8List.fromList(await file.readAsBytes());
        final summary = PrefsBackup.inspect(bytes);
        if (summary == null) {
          if (mounted) context.showMessage(context.t('settings.thatIsNotA'));
          return;
        }
        final record =
            await ref.read(backupsProvider.notifier).adopt(bytes, summary);
        if (!mounted) return;
        if (record == null) {
          context.showMessage(context.t('settings.couldNotReadThat'));
          return;
        }
        _openRestore(record);
      });

  /// The newest backup that came from the folder and holds a layout.
  ///
  /// Not simply the newest record. After a reinstall the newest file is the
  /// one this fresh install wrote a moment ago, a few hundred bytes with
  /// nothing arranged in it, and restoring that would be restoring nothing.
  /// `imported` is what separates a backup brought in from one made here.
  static BackupRecord? _newestBroughtIn(List<BackupRecord> records) {
    BackupRecord? best;
    for (final r in records) {
      if (!r.imported || r.themeCount < 1) continue;
      if (best == null || r.takenAt.isAfter(best.takenAt)) best = r;
    }
    return best;
  }

  void _openRestore(BackupRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackupRestoreScreen(record: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backups = ref.watch(backupsProvider);
    final records =
        backups.hasValue ? backups.requireValue : const <BackupRecord>[];
    final latest = records.isEmpty ? null : records.first;

    final scheduleAsync = ref.watch(backupScheduleProvider);
    final frequency = scheduleAsync.hasValue
        ? scheduleAsync.requireValue.frequency
        : BackupFrequency.daily;

    final photosAsync = ref.watch(includeWallpapersProvider);
    final withPhotos = photosAsync.hasValue && photosAsync.requireValue;
    final contents = ref.watch(backupContentsProvider).value;

    final folder = ref.watch(backupFolderProvider).value;
    final c = ChromeScope.of(context).colors;

    return ThemedScaffold(
      settingsLook: true,
      title: context.t('settings.backup'),
      body: ListView(
        padding: EdgeInsets.only(bottom: context.bottomInset + 24),
        children: [
          _Status(latest: latest),
          ThemedSectionHeader(context.t('settings.backup.savedTo')),
          ThemedListCard(children: [
            ThemedListRow(
              icon: Icons.smartphone,
              title: context.t('settings.backup.thisPhone'),
              subtitle: _whereOnPhone(folder),
              trailing: latest == null
                  ? null
                  : Icon(Icons.check_rounded, size: 20, color: c.ok),
            ),
          ]),
          ThemedSectionHeader(context.t('settings.backup.howOften')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                for (final f in const [
                  BackupFrequency.onChange,
                  BackupFrequency.daily,
                  BackupFrequency.weekly,
                ]) ...[
                  if (f != BackupFrequency.onChange) const SizedBox(width: 8),
                  Expanded(
                    child: ThemedButton(
                      label: _frequencyLabel(context, f),
                      expand: true,
                      kind: f == frequency
                          ? ThemedButtonKind.primary
                          : ThemedButtonKind.secondary,
                      onPressed: _busy
                          ? null
                          : () => ref
                              .read(backupScheduleProvider.notifier)
                              .setFrequency(f),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ThemedListCard(children: [
            ThemedListRow(
              icon: Icons.photo_library_outlined,
              title: context.t('settings.backup.photos'),
              subtitle: contents == null || contents.photoCount == 0
                  ? null
                  : context.t('settings.backup.photosSub', {
                      'n': '${contents.photoCount}',
                      'size': sizeLabel(context, contents.photoBytes),
                    }),
              enabled: !_busy && photosAsync.hasValue,
              trailing: ThemedToggle(
                value: withPhotos,
                onChanged: _busy || !photosAsync.hasValue
                    ? null
                    : (v) =>
                        ref.read(includeWallpapersProvider.notifier).set(v),
              ),
            ),
          ]),
          if (records.isNotEmpty) ...[
            ThemedSectionHeader(context.t('settings.backup.found')),
            ThemedListCard(children: [
              for (final r in records)
                ThemedListRow(
                  icon: r.imported ? Icons.phonelink_ring : Icons.history,
                  title: _titleOf(context, r),
                  subtitle: _subtitleOf(context, r),
                  enabled: !_busy,
                  onTap: () => _openRestore(r),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: c.textFaint,
                  ),
                ),
            ]),
          ],
          ThemedSectionHeader(context.t('settings.backup.more')),
          ThemedListCard(children: [
            ThemedListRow(
              icon: Icons.manage_search,
              title: context.t('settings.backup.findBackups'),
              enabled: !_busy,
              onTap: _findBackups,
            ),
            ThemedListRow(
              icon: Icons.folder_open,
              title: context.t('settings.backup.openFile'),
              enabled: !_busy,
              onTap: _open,
            ),
            ThemedListRow(
              icon: Icons.send_outlined,
              title: context.t('settings.backup.sendCopy'),
              enabled: !_busy,
              onTap: _send,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: ThemedButton(
                    label: context.t('settings.backup.restore'),
                    kind: ThemedButtonKind.secondary,
                    expand: true,
                    onPressed: _busy || latest == null
                        ? null
                        : () => _openRestore(latest),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ThemedButton(
                    label: context.t('settings.backup.backUpNow'),
                    expand: true,
                    onPressed: _busy ? null : _backUp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The file path in plain words. A folder the user picked is named by its
  /// own display name; the automatic one by its full path and file name.
  String _whereOnPhone(String? folder) {
    if (folder == null || folder == BackupsNotifier.autoFolderLabel) {
      return '${BackupsNotifier.autoFolderLabel}/${BackupsNotifier.latestFileName}';
    }
    return '$folder/${BackupsNotifier.latestFileName}';
  }
}

/// The header: is this phone backed up, and when was the last one.
class _Status extends StatelessWidget {
  const _Status({required this.latest});

  final BackupRecord? latest;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final r = latest;
    final ok = r != null;
    final tone = ok ? d.colors.ok : d.colors.warn;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline_rounded : Icons.schedule_rounded,
            size: 28,
            color: tone,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok
                      ? context.t('settings.backup.autoOn')
                      : context.t('settings.backup.noneYet'),
                  style: d.text.title,
                ),
                if (r != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.t('settings.backup.latest', {
                      'when': dayLabel(context, r.takenAt),
                      'size': sizeLabel(context, r.sizeBytes),
                    }),
                    style: d.text.caption.copyWith(color: d.colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _frequencyLabel(BuildContext c, BackupFrequency f) => switch (f) {
      BackupFrequency.daily => c.t('settings.backup.daily'),
      BackupFrequency.weekly => c.t('settings.backup.weekly'),
      BackupFrequency.onChange => c.t('settings.backup.onChange'),
    };

String _titleOf(BuildContext c, BackupRecord r) {
  final when = dayLabel(c, r.takenAt);
  if (!r.imported) {
    return c.t('settings.backup.thisPhoneOn', {'when': when});
  }
  return r.device == null
      ? c.t('settings.backup.openedFileOn', {'when': when})
      : c.t('settings.backup.deviceOn', {'device': r.device!, 'when': when});
}

String _subtitleOf(BuildContext c, BackupRecord r) {
  final parts = <String>[
    plural(c, r.themeCount, 'settings.backup.distroOne',
        'settings.backup.distroOther'),
    if (r.carriesPhotos)
      plural(c, r.photoCount, 'settings.backup.pictureOne',
          'settings.backup.pictureOther'),
    sizeLabel(c, r.sizeBytes),
  ];
  return parts.join(', ');
}
