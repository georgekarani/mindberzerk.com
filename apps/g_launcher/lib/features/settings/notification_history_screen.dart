import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/repositories/app_repository.dart';
import '../../design/components/components.dart';
import '../../platform/launcher_api.g.dart';
import '../../system/notification_history.dart';
import '../drawer/app_icon.dart';

/// Open the notification history. PHASE 9.
Future<void> openNotificationHistory(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationHistoryScreen()),
    );

/// The last week of notifications, newest first, kept on the phone.
///
/// Read from native each time the page opens and on pull, never held in
/// Dart. A row opens the app it came from; Clear deletes the list.
class NotificationHistoryScreen extends ConsumerWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(notificationHistoryProvider);
    final apps = ref.watch(appListProvider).asData?.value ?? const <AppEntry>[];
    final byPackage = <String, AppEntry>{
      for (final a in apps) a.packageName: a,
    };

    return ThemedScaffold(
      settingsLook: true,
      title: context.t('settings.notificationHistory'),
      actions: [
        IconButton(
          tooltip: context.t('notifHistory.clear'),
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: () async {
            HapticFeedback.selectionClick();
            await clearNotificationHistory();
            ref.invalidate(notificationHistoryProvider);
          },
        ),
      ],
      body: Builder(
        builder: (context) {
          final d = ChromeScope.of(context);
          final list = records.asData?.value ?? const <NotificationRecord>[];
          if (records.isLoading && list.isEmpty) {
            return const SizedBox.shrink();
          }
          if (list.isEmpty) {
            return Center(
              child: Text(
                context.t('notifHistory.empty'),
                style: d.text.caption.copyWith(color: d.colors.textMuted),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationHistoryProvider),
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: context.bottomInset + 16),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final r = list[i];
                final app = byPackage[r.packageName];
                final title = r.title.isNotEmpty ? r.title : (app?.label ?? '');
                return _HistoryRow(
                  icon: app == null
                      ? Icon(Icons.notifications_none, color: d.colors.textMuted)
                      : AppIcon(entry: app, size: 32, showBadge: false),
                  title: title,
                  text: r.text,
                  when: _when(context, r.at),
                  onTap: app == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          ref.read(launcherHostApiProvider).launchApp(
                                app.componentKey,
                                null,
                                null,
                                null,
                                null,
                              );
                        },
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Time today, else the short date. Localised by MaterialLocalizations, so
  /// a 24-hour phone reads 21:05 and a 12-hour one 9:05 PM.
  static String _when(BuildContext context, DateTime at) {
    final m = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final time = m.formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return sameDay ? time : '${m.formatShortMonthDay(at)}, $time';
  }
}

/// One kept notification: the app's icon, the title with its time, the text.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.when,
    this.onTap,
  });

  final Widget icon;
  final String title;
  final String text;
  final String when;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(dimension: 32, child: Center(child: icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: d.text.body.copyWith(color: d.colors.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: d.text.caption.copyWith(
                          color: d.colors.textFaint,
                        ),
                      ),
                    ],
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: d.text.caption.copyWith(
                        color: d.colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
