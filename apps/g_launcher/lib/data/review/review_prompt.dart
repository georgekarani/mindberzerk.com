/// Google Play's own rating prompt, asked once per version, at a calm moment.
///
/// ─── WHY THIS EXISTS ────────────────────────────────────────────────────────
///
/// Most of the low ratings on the listing are from 2021 builds that no longer
/// exist. The people using version 6 rarely leave one, because nothing asks.
/// This asks, the way Play allows: the in-app review sheet, which rates without
/// leaving the launcher and which Play itself rations.
///
/// ─── WHEN ───────────────────────────────────────────────────────────────────
///
/// All of these, or not at all:
///
///   * at least [kReviewAfter] on THIS version, so someone has lived with the
///     update rather than meeting it;
///   * at least [kReviewMinOpens] returns to the home screen on it, so they use
///     the launcher rather than merely having it installed;
///   * never twice for the same version code, and never within [kReviewGap] of
///     the last ask, whatever the version;
///   * a quiet moment: [kReviewSettle] after the launcher comes back to the
///     front, and only if it is still in front then. Never on cold start, never
///     mid-gesture.
///
/// Play can still decline to show the sheet (it keeps its own quota and says
/// nothing either way), so an ask is recorded as made whether or not anything
/// appeared. That is what keeps this from retrying into Play's quota forever.
///
/// ─── WHAT IT NEVER DOES ─────────────────────────────────────────────────────
///
/// No pre-prompt asking whether you like the app, no star picker of our own,
/// no routing of unhappy people away from the store. Play forbids gating the
/// prompt on sentiment, and a launcher that interrupts the home screen to fish
/// for five stars is the behaviour the rest of this app refuses.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../prefs/prefs_repository.dart';
import '../repositories/app_repository.dart';

/// How long someone has been on a version before being asked about it.
const kReviewAfter = Duration(days: 3);

/// Returns to the home screen on that version before asking.
const kReviewMinOpens = 5;

/// The shortest time between two asks, across versions.
const kReviewGap = Duration(days: 120);

/// How long the launcher must sit in front, untouched by lifecycle, first.
const kReviewSettle = Duration(seconds: 3);

/// Its own top-level key, like the update throttle, so Restore defaults never
/// wipes it and re-arms an ask somebody has already answered.
const kReviewRecordKey = 'review.record.v1';

@immutable
class _Record {
  const _Record({
    required this.code,
    required this.since,
    this.opens = 0,
    this.askedCode,
    this.askedAt,
  });

  final int code;
  final DateTime since;
  final int opens;
  final int? askedCode;
  final DateTime? askedAt;

  _Record copyWith({int? opens, int? askedCode, DateTime? askedAt}) => _Record(
        code: code,
        since: since,
        opens: opens ?? this.opens,
        askedCode: askedCode ?? this.askedCode,
        askedAt: askedAt ?? this.askedAt,
      );

  /// A new version starts its own count but keeps when we last asked.
  _Record forVersion(int newCode, DateTime now) => _Record(
        code: newCode,
        since: now,
        askedCode: askedCode,
        askedAt: askedAt,
      );

  bool due(DateTime now) =>
      askedCode != code &&
      opens >= kReviewMinOpens &&
      now.difference(since) >= kReviewAfter &&
      (askedAt == null || now.difference(askedAt!) >= kReviewGap);

  Map<String, Object?> toJson() => {
        'code': code,
        'since': since.toIso8601String(),
        'opens': opens,
        if (askedCode != null) 'askedCode': askedCode,
        if (askedAt != null) 'askedAt': askedAt!.toIso8601String(),
      };

  static _Record? fromJson(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return _Record(
        code: m['code'] as int,
        since: DateTime.parse(m['since'] as String),
        opens: m['opens'] as int? ?? 0,
        askedCode: m['askedCode'] as int?,
        askedAt: m['askedAt'] == null
            ? null
            : DateTime.tryParse(m['askedAt'] as String),
      );
    } catch (_) {
      // A corrupt record means a fresh count, never an immediate ask.
      return null;
    }
  }
}

class ReviewPrompt {
  ReviewPrompt(this._ref);

  final Ref _ref;
  AppLifecycleListener? _life;
  Timer? _settle;
  bool _busy = false;

  void start() {
    // Android only, and only a build Play installed can show the sheet; a
    // debug build simply never gets past `isAvailable`.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _life = AppLifecycleListener(
      onResume: _arrived,
      onPause: _left,
      onHide: _left,
    );
  }

  void dispose() {
    _settle?.cancel();
    _life?.dispose();
  }

  void _left() {
    _settle?.cancel();
    _settle = null;
  }

  /// Counted per return to the front, then asked only after it has settled.
  Future<void> _arrived() async {
    final record = await _count();
    if (record == null || !record.due(DateTime.now())) return;
    _settle?.cancel();
    _settle = Timer(kReviewSettle, _ask);
  }

  Future<_Record?> _count() async {
    try {
      final code = await _ref.read(launcherHostApiProvider).getVersionCode();
      final store = _ref.read(prefsStoreProvider);
      final now = DateTime.now();
      final raw = await store.read(kReviewRecordKey);
      var record = raw == null ? null : _Record.fromJson(raw);
      record = record == null
          ? _Record(code: code, since: now)
          : (record.code == code ? record : record.forVersion(code, now));
      record = record.copyWith(opens: record.opens + 1);
      await store.write(kReviewRecordKey, jsonEncode(record.toJson()));
      return record;
    } catch (e) {
      debugPrint('Review prompt count skipped: $e');
      return null;
    }
  }

  Future<void> _ask() async {
    if (_busy) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != AppLifecycleState.resumed) return;
    _busy = true;
    try {
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;

      // Recorded BEFORE the request: Play does not say whether it showed the
      // sheet, and a crash between the two must not leave the ask re-armed.
      final store = _ref.read(prefsStoreProvider);
      final raw = await store.read(kReviewRecordKey);
      final record = raw == null ? null : _Record.fromJson(raw);
      if (record == null || !record.due(DateTime.now())) return;
      await store.write(
        kReviewRecordKey,
        jsonEncode(record
            .copyWith(askedCode: record.code, askedAt: DateTime.now())
            .toJson()),
      );

      await review.requestReview();
    } catch (e) {
      debugPrint('Review prompt unavailable: $e');
    } finally {
      _busy = false;
    }
  }
}

/// Watched from `_Root` for its side effect, like the update check beside it,
/// so it lives for the process and not for whichever shell is on screen.
final reviewPromptWatchProvider = Provider<void>((ref) {
  final prompt = ReviewPrompt(ref)..start();
  ref.onDispose(prompt.dispose);
});
