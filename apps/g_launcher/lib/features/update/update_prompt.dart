/// The update offer on the desktop: a sheet when a new version is waiting on
/// Play, and a message with Restart once it has downloaded.
///
/// ─── WHY THE DESKTOP AND NOT ONLY SETTINGS ──────────────────────────────────
///
/// The offer used to live only in Settings, where most people never look, so
/// updates reached them whenever Play's own auto-update got round to it. The
/// flow now matches what users know from other Play apps: one sheet with the
/// app's icon, Update now or Later, Play's own dialog, the download running
/// while the desktop stays usable, then a message with Restart.
///
/// ─── WHAT IT NEVER DOES ─────────────────────────────────────────────────────
///
/// Restart on its own. The launcher IS the home screen, so finishing the
/// install is always the user's tap, through the same restart sheet Settings
/// uses (now, or when the screen turns off).
///
/// No version numbers. Play reports only the waiting build's version CODE,
/// which is a release-process number, not the version anyone knows the app
/// by, so the sheet names no version at all.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/prefs_repository.dart';
import '../../data/update/update_repository.dart';
import '../../design/branded_message.dart';
import '../../design/components/components.dart';
import '../settings/settings_sheets.dart' show confirmUpdateRestart;

/// When Later was chosen, per waiting build. Its own top-level key for the
/// reason [kUpdateRecordKey] is: Restore defaults must not re-arm it.
const kUpdateOfferKey = 'update.offered.v1';

/// How long Later holds before the same build is offered again.
const kUpdateOfferSnooze = Duration(days: 3);

class UpdatePrompt extends ConsumerStatefulWidget {
  const UpdatePrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<UpdatePrompt> {
  /// One sheet at a time, however many state changes arrive while it is up.
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    // listenManual, not watch: the desktop below must never rebuild for an
    // update state change. fireImmediately, because the startup check can
    // answer before the desktop mounts and a plain listener only hears later
    // changes (`ref.listen` in build does not offer it). Closed with this
    // State automatically.
    ref.listenManual<UpdateState>(
      appUpdateProvider,
      (prev, next) => WidgetsBinding.instance
          .addPostFrameCallback((_) => _onChange(prev, next)),
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _onChange(UpdateState? prev, UpdateState next) {
    if (!mounted) return;
    switch (next.status) {
      case UpdateStatus.available:
        // Only when a build first appears. Declining Play's own dialog drops
        // the state from downloading back to available, and that answer must
        // not re-open this sheet.
        final seen = prev?.status == UpdateStatus.available ||
            prev?.status == UpdateStatus.downloading;
        if (!seen) _maybeOffer(next);
      case UpdateStatus.readyToInstall:
        if (prev?.status != UpdateStatus.readyToInstall) _announceReady();
      default:
        break;
    }
  }

  Future<void> _maybeOffer(UpdateState update) async {
    final code = update.availableVersionCode;
    if (code == null || _sheetOpen) return;

    // Read before any await: `ref` is unsafe once this widget is gone.
    final store = ref.read(prefsStoreProvider);
    final notifier = ref.read(appUpdateProvider.notifier);

    if (await _snoozed(store, code) || !mounted) return;
    // Only over the desktop itself. Settings has its own banner, and a sheet
    // dropping over a screen the user is working in is an interruption.
    if (ModalRoute.of(context)?.isCurrent == false) return;

    _sheetOpen = true;
    final accepted = await _showOffer(context);
    _sheetOpen = false;

    if (accepted == true) {
      await notifier.startDownload();
    } else {
      // Later, or the sheet dismissed: the same answer.
      await store.write(
        kUpdateOfferKey,
        jsonEncode({'code': code, 'at': DateTime.now().toIso8601String()}),
      );
    }
  }

  void _announceReady() {
    final notifier = ref.read(appUpdateProvider.notifier);
    context.showMessage(
      context.t('update.downloaded'),
      actionLabel: context.t('settings.update.restart'),
      onAction: () {
        if (mounted) confirmUpdateRestart(context, notifier);
      },
      duration: const Duration(seconds: 10),
    );
  }

  static Future<bool> _snoozed(PrefsStore store, int code) async {
    final raw = await store.read(kUpdateOfferKey);
    if (raw == null) return false;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.tryParse(map['at'] as String? ?? '');
      return map['code'] == code &&
          at != null &&
          DateTime.now().difference(at) < kUpdateOfferSnooze;
    } catch (_) {
      // A corrupt record offers again, which is the harmless direction.
      return false;
    }
  }

  /// The offer: the app's icon, one title, one line, two choices. Framed by
  /// [ThemedSheet], so it slides up on GNOME and iOS and opens as a window on
  /// the desktops whose own dialogs do.
  static Future<bool?> _showOffer(BuildContext context) => ThemedSheet.show<bool>(
        context,
        builder: (ctx) {
          final c = ChromeScope.of(ctx).colors;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/brand/g_launcher_icon.png',
                      width: 72,
                      height: 72,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.system_update_alt,
                        size: 56,
                        color: c.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  ctx.t('update.newVersionTitle'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ctx.t('update.newVersionBody'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                ThemedButton(
                  label: ctx.t('update.now'),
                  expand: true,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 8),
                ThemedButton(
                  label: ctx.t('update.later'),
                  kind: ThemedButtonKind.text,
                  expand: true,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ],
            ),
          );
        },
      );
}
