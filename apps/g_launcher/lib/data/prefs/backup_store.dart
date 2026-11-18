import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../repositories/app_repository.dart';
import 'backup_apps.dart';
import 'prefs_backup.dart';
import 'prefs_repository.dart';
import 'wallpaper_collections.dart';

/// Backups the launcher keeps for itself, and the index describing them.
///
/// ─── WHY A COPY IN APP STORAGE RATHER THAN A LIST OF PLACES ─────────────────
///
/// The screen wants a list of backups you can tap and restore. A list of places
/// the user once saved to cannot be that list: `FilePicker.saveFile` hands back
/// a SAF document string that Dart cannot read again, and the path `pickFile`
/// gives for an opened document is a cache copy the OS may evict at any time.
/// Both would draw a row that fails when tapped, which is the one thing a
/// backup feature must never do.
///
/// So a backup is written HERE first, into the support directory, and exporting
/// is a second and separate act on a file that already exists. Same reasoning
/// `wallpaper_collections.dart` spells out for photos: support dir, never
/// cache, because the cache is allowed to disappear under us.
///
/// ─── THE FILES ARE BYTES NOW ────────────────────────────────────────────────
///
/// v2 backups are zips, so everything here moved from String to [Uint8List].
/// Records written by the build that kept plain JSON carry `fileFormat: 'json'`
/// and keep their `.json` name, so the list survives the upgrade and those
/// files still open: [PrefsBackup.inspect] reads both shapes.
class BackupRecord {
  const BackupRecord({
    required this.id,
    required this.savedAt,
    required this.themeCount,
    required this.collectionCount,
    required this.sizeBytes,
    required this.imported,
    this.photoCount = 0,
    this.device,
    this.fileFormat = PrefsBackup.fileExtension,
    this.createdAt,
  });

  /// Microsecond stamp, and the file name. Unique per record because the
  /// directory is ours alone and nothing else writes into it.
  final String id;

  /// When this copy landed on the phone. For an imported file that is the
  /// moment of import, NOT the moment the backup was made, which is what
  /// [createdAt] carries.
  final DateTime savedAt;

  /// When the backup itself was taken, as recorded inside the file. Null for a
  /// file whose `createdAt` was missing or unparseable; the row then shows
  /// [savedAt] alone rather than inventing a date.
  final DateTime? createdAt;

  final int themeCount;
  final int collectionCount;

  /// Images carried in the container. Zero for a v1 file and for one taken with
  /// wallpapers switched off, which is a real difference between two backups
  /// and belongs on the row.
  final int photoCount;

  final int sizeBytes;

  /// The phone the backup was taken on, when the file records one.
  final String? device;

  /// `glbak` or the legacy `json`. Persisted rather than derived, so a record
  /// written before v2 still points at the file it actually named.
  final String fileFormat;

  /// True when this arrived through the file picker rather than being taken on
  /// this phone.
  final bool imported;

  /// The date a person would use to recognise this backup.
  DateTime get takenAt => createdAt ?? savedAt;

  String get fileName => 'g-launcher-$id.$fileFormat';

  /// True when this file can bring its photos with it to another phone.
  bool get carriesPhotos => photoCount > 0;

  /// Same test as [BackupSummary.isBlank], from the row's own counts.
  bool get isBlank => themeCount == 0 && collectionCount == 0 && photoCount == 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'themeCount': themeCount,
        'collectionCount': collectionCount,
        'photoCount': photoCount,
        'sizeBytes': sizeBytes,
        'device': device,
        'fileFormat': fileFormat,
        'imported': imported,
      };

  static BackupRecord? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final saved = DateTime.tryParse((j['savedAt'] as String?) ?? '');
    if (id == null || saved == null) return null;
    return BackupRecord(
      id: id,
      savedAt: saved.toLocal(),
      createdAt:
          DateTime.tryParse((j['createdAt'] as String?) ?? '')?.toLocal(),
      themeCount: (j['themeCount'] as num?)?.toInt() ?? 0,
      collectionCount: (j['collectionCount'] as num?)?.toInt() ?? 0,
      photoCount: (j['photoCount'] as num?)?.toInt() ?? 0,
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      device: j['device'] as String?,
      // Absent means a record from before the container changed, and those
      // files are all `.json`. Defaulting to the current extension here would
      // rename every one of them out of existence.
      fileFormat: (j['fileFormat'] as String?) ?? 'json',
      imported: j['imported'] as bool? ?? false,
    );
  }
}

/// What the live setup would put into a backup taken right now.
///
/// Read from the same places [PrefsBackup.collect] reads, so the numbers on
/// screen and the numbers in the next file cannot disagree.
class BackupContents {
  const BackupContents({
    required this.distroCount,
    required this.collectionCount,
    required this.photoCount,
    required this.photoBytes,
  });

  final int distroCount;
  final int collectionCount;
  final int photoCount;

  /// What the images would add to the file. Measured by stat, never estimated,
  /// per the house rule that a figure shown to the user is a measurement.
  final int photoBytes;
}

final backupContentsProvider = FutureProvider<BackupContents>((ref) async {
  final keys = await ref.watch(prefsStoreProvider).keys();
  final collections = await ref.watch(wallpaperCollectionsProvider.future);

  var bytes = 0;
  var photos = 0;
  for (final c in collections) {
    for (final p in c.paths) {
      try {
        // Counted only when it can be read, because only those travel.
        bytes += await File(p).length();
        photos += 1;
      } catch (_) {}
    }
  }

  return BackupContents(
    distroCount:
        keys.where((k) => k.startsWith(PrefsBackup.themePrefix)).length,
    collectionCount: collections.length,
    photoCount: photos,
    photoBytes: bytes,
  );
});

/// The phone's own name, for stamping into a backup and for telling two backups
/// apart in a list.
///
/// Null when the plugin throws or the platform is not Android. A backup is not
/// worth failing over a cosmetic label.
final deviceLabelProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final model = info.model.trim();
    return model.isEmpty ? null : model;
  } catch (_) {
    return null;
  }
});

/// Whether new backups carry wallpaper bytes.
///
/// Its own key rather than a [GlobalPrefs] field: that class is the promoted
/// overlay for `LauncherPrefs` and its change detection enumerates exactly
/// those fields. This is a property of the backup feature, not of a distro's
/// appearance, and wedging it into the overlay would pollute a mechanism built
/// for something else.
class IncludeWallpapersNotifier extends AsyncNotifier<bool> {
  static const storageKey = 'backups.includeWallpapers.v1';

  @override
  Future<bool> build() async {
    final raw = await ref.watch(prefsStoreProvider).read(storageKey);
    // Default ON. The whole point of v2 is that a collection survives the move
    // to a new phone, and a default of off would ship that fix switched off.
    return raw == null ? true : raw == 'true';
  }

  Future<void> set(bool value) async {
    state = AsyncData(value);
    await ref.read(prefsStoreProvider).write(storageKey, '$value');
  }
}

final includeWallpapersProvider =
    AsyncNotifierProvider<IncludeWallpapersNotifier, bool>(
  IncludeWallpapersNotifier.new,
);

class BackupsNotifier extends AsyncNotifier<List<BackupRecord>> {
  static const storageKey = 'backups.index.v1';
  static const schemaVersion = 1;

  /// How many copies are kept. Older ones are deleted as new ones arrive.
  ///
  /// Five covers "I broke it yesterday and did not notice until now" without
  /// the directory growing without bound on a phone chosen for being cheap. It
  /// matters more now than it did: a backup carrying photos is megabytes, not
  /// kilobytes.
  static const keepMax = 5;

  @override
  Future<List<BackupRecord>> build() async {
    final raw = await ref.watch(prefsStoreProvider).read(storageKey);
    if (raw == null) return _withOrphans(const []);

    List<BackupRecord> parsed;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      // A file written by a newer build reads as empty rather than throwing,
      // the same contract every other store in this layer follows.
      final v = (j['schemaVersion'] as num?)?.toInt() ?? 0;
      if (v > schemaVersion) return const [];
      parsed = <BackupRecord>[];
      for (final e in (j['records'] as List? ?? const [])) {
        if (e is! Map) continue;
        // A malformed entry is dropped rather than failing the whole index.
        // Losing one row beats losing the list that names every other backup.
        final r = BackupRecord.fromJson(e.cast<String, dynamic>());
        if (r != null) parsed.add(r);
      }
    } catch (_) {
      return const [];
    }

    // ─── THE INDEX IS RECONCILED AGAINST DISK, NOT TRUSTED ────────────────
    //
    // A record whose file is gone would draw a row that fails on tap, which is
    // the failure this whole class exists to avoid. Files can vanish without
    // the index knowing: "clear storage" empties the directory while leaving
    // nothing behind to tell us.
    final dir = await backupsDir();
    final present = <BackupRecord>[];
    for (final r in parsed) {
      if (await File('${dir.path}/${r.fileName}').exists()) present.add(r);
    }
    return _withOrphans(present);
  }

  /// Copies the restored cloud copy into the backups folder under a normal
  /// backup name, once. The copy itself stays, so Google keeps carrying it.
  Future<void> _adoptCloudCopy() async {
    try {
      final src = File('${(await cloudBackupDir()).path}/$_cloudFile');
      if (!await src.exists()) return;
      final dir = await backupsDir();
      final already =
          await dir.list().any((e) => e is File && e.path.endsWith('.glbak'));
      if (already) return;
      final id = (await src.lastModified()).microsecondsSinceEpoch;
      await src.copy('${dir.path}/g-launcher-$id.glbak');
    } catch (_) {}
  }

  /// [known] plus every backup FILE on disk that the index does not name.
  ///
  /// ─── THE REVERSE OF THE CHECK ABOVE, FOR AUTO BACKUP ──────────────────────
  ///
  /// Android's Auto Backup now carries `files/backups/` and nothing else, so on
  /// a reinstall from Play the backup files come back but the index (a shared
  /// preference) does not. Without this the files would sit on disk and the
  /// list would say there are no backups, which is exactly the complaint.
  /// Each file is read once, its summary rebuilt from its own header, and the
  /// index rewritten so the next build is a plain read again.
  Future<List<BackupRecord>> _withOrphans(List<BackupRecord> known) async {
    // A fresh restore from Google: the list is empty and only the cloud copy
    // came back. Moved into the backups folder, it is found below like any
    // other file. Never when there is a list, which means this phone already
    // has its own backups and the cloud copy is just the newest of them.
    if (known.isEmpty) await _adoptCloudCopy();
    final dir = await backupsDir();
    final named = {for (final r in known) r.fileName};
    final found = <BackupRecord>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final m = RegExp(r'^g-launcher-(\d+)\.(\w+)$').firstMatch(name);
        if (m == null || named.contains(name)) continue;
        final bytes = await entity.readAsBytes();
        final summary = PrefsBackup.inspect(bytes);
        if (summary == null) continue;
        found.add(BackupRecord(
          id: m.group(1)!,
          savedAt: await entity.lastModified(),
          createdAt: summary.takenAt,
          themeCount: summary.themeCount,
          collectionCount: summary.collectionCount,
          photoCount: summary.photoCount,
          sizeBytes: bytes.length,
          device: summary.device,
          fileFormat: m.group(2)!,
          imported: true,
        ));
      }
    } catch (_) {
      return known;
    }
    if (found.isEmpty) return known;

    final merged = [...known, ...found]
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    await ref.read(prefsStoreProvider).write(
          storageKey,
          jsonEncode({
            'schemaVersion': schemaVersion,
            'records': [for (final r in merged) r.toJson()],
          }),
        );
    return merged;
  }

  /// Newest first, which is both the display order and the prune order.
  Future<List<BackupRecord>> _snapshot() async =>
      state.hasValue ? state.requireValue : await future;

  Future<void> _write(List<BackupRecord> next) async {
    state = AsyncData(next);
    await ref.read(prefsStoreProvider).write(
          storageKey,
          jsonEncode({
            'schemaVersion': schemaVersion,
            'records': [for (final r in next) r.toJson()],
          }),
        );
  }

  /// Take a backup of the current setup. Returns the record, or null when the
  /// result is something [PrefsBackup.inspect] will not vouch for.
  ///
  /// [themeNames] comes from the caller because the registry lives above this
  /// layer. Passing it is optional, and its absence costs only display names on
  /// the restore screen, which falls back to distro ids.
  Future<BackupRecord?> create({
    Map<String, String> themeNames = const {},
  }) async {
    final Uint8List bytes;
    try {
      bytes = await PrefsBackup.encode(
        store: ref.read(prefsStoreProvider),
        repo: ref.read(prefsRepositoryProvider),
        // Awaited here rather than inside the service, so the service keeps
        // taking a plain list and never has to know a provider exists.
        collections: await ref.read(wallpaperCollectionsProvider.future),
        includeWallpapers: await ref.read(includeWallpapersProvider.future),
        deviceLabel: await ref.read(deviceLabelProvider.future),
        themeNames: themeNames,
        // Every installed app, from which `collect` keeps only the ones a
        // layout actually places. Read rather than watched: a backup is a
        // snapshot of one moment, and re-taking it because an app updated
        // mid-encode would be worse than recording the moment we started.
        installedApps: await _appRefs(),
      );
    } catch (_) {
      return null;
    }

    // Inspected rather than counted by hand. The counts on the row then come
    // from the same reader the restore screen uses, so a row can never describe
    // a file differently from the screen that restores it.
    final summary = PrefsBackup.inspect(bytes);
    if (summary == null) return null;

    final record = await _store(bytes, summary, imported: false);
    // A blank backup stays local. Sent to Google it would replace the real
    // copy a reinstall restores from.
    if (record != null && !summary.isBlank) {
      unawaited(_writeCloudCopy(
        bytes,
        withWallpapers: summary.photoCount > 0,
        themeNames: themeNames,
      ));
    }
    return record;
  }

  // ─── THE COPY GOOGLE CARRIES ──────────────────────────────────────────────
  //
  // Android's Auto Backup gives an app 25 MB and drops the WHOLE backup when
  // it is over, so a backups folder holding five copies with wallpapers would
  // send Google nothing at all. The backup rules therefore carry one file,
  // `files/cloud/latest.glbak`: the newest backup, settings only. Small enough
  // to always fit, and on a reinstall from Play it is restored before first
  // launch and picked up by [_withOrphans].
  static const _cloudFile = 'latest.glbak';

  Future<void> _writeCloudCopy(
    Uint8List bytes, {
    required bool withWallpapers,
    Map<String, String> themeNames = const {},
  }) async {
    try {
      var out = bytes;
      if (withWallpapers) {
        out = await PrefsBackup.encode(
          store: ref.read(prefsStoreProvider),
          repo: ref.read(prefsRepositoryProvider),
          collections: await ref.read(wallpaperCollectionsProvider.future),
          includeWallpapers: false,
          deviceLabel: await ref.read(deviceLabelProvider.future),
          themeNames: themeNames,
          installedApps: await _appRefs(),
        );
      }
      final dir = await cloudBackupDir();
      final tmp = File('${dir.path}/$_cloudFile.tmp');
      await tmp.writeAsBytes(out, flush: true);
      await tmp.rename('${dir.path}/$_cloudFile');
    } catch (_) {
      // A missed cloud copy costs only the Google route; the backup the user
      // asked for is saved, and the next one writes this again.
    }
  }

  /// Label, package and preinstalled flag for every app on this phone, keyed by
  /// componentKey. Empty when the list cannot be read, which costs the backup
  /// its app names and nothing else.
  Future<Map<String, BackupAppRef>> _appRefs() async {
    try {
      final apps = await ref.read(appListProvider.future);
      return {
        for (final a in apps)
          a.componentKey: BackupAppRef(
            label: a.label,
            packageName: a.packageName,
            system: a.isSystem,
          ),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Copy a backup the user opened from elsewhere into our own directory, so it
  /// survives the picker's cache and can be restored again later.
  Future<BackupRecord?> adopt(Uint8List bytes, BackupSummary summary) =>
      _store(bytes, summary, imported: true);

  Future<BackupRecord?> _store(
    Uint8List bytes,
    BackupSummary summary, {
    required bool imported,
  }) async {
    final dir = await backupsDir();
    final id = '${DateTime.now().microsecondsSinceEpoch}';

    // A v1 file adopted from elsewhere keeps its own extension. Renaming it to
    // `.glbak` would claim a container it does not have, and the sniff in
    // `inspect` would then be the only thing standing between that claim and a
    // confusing failure.
    final ext = summary.schemaVersion >= 2 ? PrefsBackup.fileExtension : 'json';
    final file = File('${dir.path}/g-launcher-$id.$ext');

    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      return null;
    }

    final record = BackupRecord(
      id: id,
      savedAt: DateTime.now(),
      createdAt: summary.takenAt,
      themeCount: summary.themeCount,
      collectionCount: summary.collectionCount,
      photoCount: summary.photoCount,
      sizeBytes: await file.length(),
      device: summary.device,
      fileFormat: ext,
      imported: imported,
    );

    final current = await _snapshot();
    final next = [record, ...current];

    // Pruned before the index is written, so a failed delete leaves an orphan
    // file rather than an index entry pointing at nothing.
    final kept = next.take(keepMax).toList();
    for (final gone in next.skip(keepMax)) {
      try {
        await File('${dir.path}/${gone.fileName}').delete();
      } catch (_) {}
    }

    await _write(kept);
    // A copy of every backup this phone MADE goes to the visible folder.
    // Not the imported ones: they came from that folder, or from a file the
    // user already holds, and a second copy would only crowd out real ones.
    // Never a blank one: it would take over the fixed-name latest file.
    if (!imported && !summary.isBlank) {
      unawaited(_mirror(record.fileName, bytes));
    }
    return record;
  }

  // ─── THE VISIBLE FOLDER ───────────────────────────────────────────────────
  //
  // Backups used to live only in app storage, which an uninstall wipes, and
  // the folder option needed the user to pick a folder first, which nobody
  // did. Native now falls back to Documents/G Launcher/Backups when none is
  // picked, so every backup is mirrored there with no question asked, and
  // [absorbFolder] reads it back: on this install by itself, and after a
  // reinstall once the user taps "Find backups" (Android hides an old
  // install's files from a new one until the user picks the folder).

  static const _absorbedKey = 'backups.absorbed.v1';

  /// Folder file names already accounted for: mirrored from here or imported.
  /// Without this, a backup pruned from the internal list of five would be
  /// "found" in the folder again and re-imported on every visit.
  Future<Set<String>> _absorbed() async {
    final raw = await ref.read(prefsStoreProvider).read(_absorbedKey);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _remember(Iterable<String> names) async {
    final next = {...await _absorbed(), ...names};
    await ref
        .read(prefsStoreProvider)
        .write(_absorbedKey, jsonEncode([...next]));
  }

  /// The newest backup's name in Documents/GLauncher. Never changes, so a
  /// restore, a new phone, or a person in the Files app always knows which
  /// file is the current one.
  static const latestFileName = 'glauncher-backup.glbak';

  /// How the native side names the automatic folder.
  static const autoFolderLabel = 'Documents/GLauncher';

  /// A dated copy for GLauncher/History: glauncher-2026-11-12-0941.glbak.
  static final _numberedLatest = RegExp(r'^glauncher-backup \(\d+\)\.glbak$');

  static String historyFileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'glauncher-${t.year}-${two(t.month)}-${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}.glbak';
  }

  /// Copies a fresh backup to the phone's shared storage.
  ///
  /// Two writes: the fixed-name latest file, replaced in place, and a dated
  /// copy in History. Only History is pruned, to [keepMax] copies; the
  /// latest file is never deleted. Best-effort like everything here: a
  /// failed copy leaves the app-storage backup, which is the one restores
  /// read on this phone.
  Future<void> _mirror(String fileName, Uint8List bytes) async {
    try {
      final api = ref.read(launcherHostApiProvider);
      await api.writeBackup(latestFileName, bytes);
      final dated = historyFileName(DateTime.now());
      final uri = await api.writeBackup(dated, bytes);
      await _remember([latestFileName, if (uri != null) dated]);
      if (uri == null) return;

      // Newest first from native, so everything past keepMax is the oldest.
      final rows = await api.listBackups();
      var history = 0;
      var numberedLatest = 0;
      for (final raw in rows) {
        final j = _row(raw);
        if (j == null) continue;
        final name = j.name.toLowerCase();
        // Numbered copies of the latest file ("glauncher-backup (2).glbak")
        // piled up one per backup before native learned to reuse its own.
        // Keep the newest, which is the one native writes to now, and clear
        // the rest. Only rows this install can see are listed, so this never
        // touches a file it may not delete.
        if (_numberedLatest.hasMatch(name)) {
          numberedLatest++;
          if (numberedLatest > 1) await api.deleteBackup(j.uri);
          continue;
        }
        if (!name.startsWith('glauncher-') ||
            name.startsWith('glauncher-backup')) {
          continue;
        }
        history++;
        if (history > keepMax) await api.deleteBackup(j.uri);
      }
    } catch (_) {
      // Shared storage is a convenience copy; never fail a backup over it.
    }
  }

  /// The backup a restore should use: the most recently TAKEN one that holds
  /// something. Not the newest file, which after a reinstall is often a blank
  /// copy written seconds earlier, and not the newest import, whose date is
  /// the moment it was copied in.
  Future<BackupRecord?> best() async {
    final usable = (await future).where((r) => !r.isBlank).toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return usable.isEmpty ? null : usable.first;
  }

  /// Every place a backup can be found without asking the user anything:
  /// Google's restored copy, this install's own files, and the visible folder
  /// as far as Android lets this install see it. Then [best].
  Future<BackupRecord?> findAutomatically() async {
    // Absorbing writes the index through [_write], which updates state, so
    // [best] reads the merged list without a rebuild.
    await absorbFolder();
    return best();
  }

  /// Imports every backup in the folder that this phone does not already have.
  /// Returns how many were added. Safe to call on every visit.
  ///
  /// One pass at a time: the screen absorbs on open and the Find button
  /// absorbs again, and two overlapping passes would import the same file
  /// twice before either had recorded it.
  Future<int> absorbFolder() =>
      _absorbing ??= _absorbFolder().whenComplete(() => _absorbing = null);

  Future<int>? _absorbing;

  Future<int> _absorbFolder() async {
    final List<String?> rows;
    try {
      rows = await ref.read(launcherHostApiProvider).listBackups();
    } catch (_) {
      return 0;
    }
    final known = {
      for (final r in await _snapshot()) r.fileName,
      ...await _absorbed(),
    };
    final api = ref.read(launcherHostApiProvider);
    final taken = <String>[];
    var added = 0;
    // Oldest first, so the newest backup ends up at the top of the list.
    for (final raw in rows.reversed) {
      final j = _row(raw);
      if (j == null) continue;
      final name = _canonical(j.name);
      if (known.contains(name)) continue;
      taken.add(name);
      final bytes = await api.readBackup(j.uri);
      if (bytes == null) continue;
      final summary = PrefsBackup.inspect(bytes);
      if (summary == null || summary.isBlank) continue;
      if (await _alreadyHeld(summary)) continue;
      if (await adopt(bytes, summary) != null) added++;
    }
    if (taken.isNotEmpty) await _remember(taken);
    return added;
  }

  /// The name as this app wrote it, without an extension MediaStore may have
  /// appended to a type it did not recognise (`.glbak.bin`).
  /// True when a backup taken at the same moment is already in the index.
  Future<bool> _alreadyHeld(BackupSummary summary) async {
    final taken = summary.takenAt;
    if (taken == null) return false;
    for (final r in await _snapshot()) {
      final at = r.createdAt;
      if (at != null && at.isAtSameMomentAs(taken)) return true;
    }
    return false;
  }

  static String _canonical(String name) {
    final i = name.toLowerCase().indexOf('.glbak');
    return i < 0 ? name : name.substring(0, i + '.glbak'.length);
  }

  static ({String uri, String name})? _row(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final uri = j['uri'] as String?;
      final name = j['name'] as String?;
      if (uri == null || name == null) return null;
      return (uri: uri, name: name);
    } catch (_) {
      return null;
    }
  }

  /// The bytes of one backup, or null when the file has gone since the index
  /// was reconciled. Callers treat null as "this one cannot be used" rather
  /// than as an error worth a message of its own.
  Future<Uint8List?> read(BackupRecord record) async {
    try {
      final dir = await backupsDir();
      return await File('${dir.path}/${record.fileName}').readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    final current = await _snapshot();
    final gone = current.where((r) => r.id == id).toList();
    await _write(current.where((r) => r.id != id).toList());
    try {
      final dir = await backupsDir();
      for (final r in gone) {
        await File('${dir.path}/${r.fileName}').delete();
      }
    } catch (_) {}
  }
}

/// Where our copies live. Support dir, never cache, for the reason spelled out
/// on [BackupRecord].
/// `files/cloud/`, the one folder Android's Auto Backup carries. See
/// `res/xml/backup_rules.xml`.
Future<Directory> cloudBackupDir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}/cloud');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<Directory> backupsDir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}/backups');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

final backupsProvider =
    AsyncNotifierProvider<BackupsNotifier, List<BackupRecord>>(
  BackupsNotifier.new,
);
