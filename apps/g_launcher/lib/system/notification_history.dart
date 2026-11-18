/// Notification history, on the phone only. PHASE 9.
///
/// ─── OPT-IN, AND OFF MEANS GONE ─────────────────────────────────────────────
///
/// The switch is `GlobalPrefs.notificationHistory`, null meaning off. Native
/// keeps the copy (titles and text of the last week, at most two hundred) in
/// the app's private files and deletes it when the switch goes off. Dart holds
/// nothing between reads.
///
/// Recording needs the same notification access the badges use, granted on
/// Android's own settings page; without it nothing is posted to the service
/// and the history stays empty.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _channel = MethodChannel('g_launcher/notifications');

/// One kept notification.
class NotificationRecord {
  const NotificationRecord({
    required this.packageName,
    required this.title,
    required this.text,
    required this.at,
  });

  final String packageName;
  final String title;
  final String text;
  final DateTime at;
}

/// Tell native whether to keep notifications. Off deletes what was kept.
Future<void> setNotificationHistory(bool on) async {
  try {
    await _channel.invokeMethod<void>('historySet', {'on': on});
  } on PlatformException {
    // Nothing recorded is the safe failure.
  } on MissingPluginException {
    // Older native half: it cannot record, so there is nothing to stop.
  }
}

/// Delete everything kept so far and keep recording.
Future<void> clearNotificationHistory() async {
  try {
    await _channel.invokeMethod<void>('historyClear');
  } on PlatformException {
    // Already empty, or nothing to clear on this build.
  } on MissingPluginException {
    // Same.
  }
}

/// The kept notifications, newest first. Re-read with `ref.invalidate`.
///
/// AUTO-DISPOSED, so every visit to the screen reads the file again. A plain
/// FutureProvider kept its first answer for the life of the process, and the
/// screen opened before anything arrived stayed empty on every later visit.
final notificationHistoryProvider =
    FutureProvider.autoDispose<List<NotificationRecord>>((ref) async {
  try {
    final raw = await _channel.invokeListMethod<Object?>(
      'history',
      {'limit': 200},
    );
    return [
      for (final e in raw ?? const <Object?>[])
        if (e is Map && e['package'] is String)
          NotificationRecord(
            packageName: e['package'] as String,
            title: (e['title'] as String?) ?? '',
            text: (e['text'] as String?) ?? '',
            at: DateTime.fromMillisecondsSinceEpoch(
              (e['at'] as num?)?.toInt() ?? 0,
            ),
          ),
    ];
  } on PlatformException {
    return const [];
  } on MissingPluginException {
    return const [];
  }
});
