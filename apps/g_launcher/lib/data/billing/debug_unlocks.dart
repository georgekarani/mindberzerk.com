/// Debug builds only: unlock paid distros and features without Play.
///
/// ─── WHY THIS EXISTS ────────────────────────────────────────────────────────
///
/// A debug build on an emulator cannot buy anything, so twelve of fifteen
/// distros could not be applied, and an audit could only look at three of them
/// plus pictures of the rest. This adds SKUs to the owned set at the one place
/// ownership is decided, so a debug-unlocked distro downloads, installs and
/// applies exactly as a bought one does.
///
/// ─── WHY IT CANNOT LEAK INTO A RELEASE ──────────────────────────────────────
///
/// [build] returns an empty set and never reads storage unless [kDebugMode],
/// which is a compile-time constant, so a release build carries the code but
/// can never produce a non-empty set, whatever is stored on the phone. The
/// Settings section that writes it is gated on the same constant.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../prefs/prefs_repository.dart';

/// Its own top-level key, so Restore defaults leaves test unlocks alone.
const kDebugUnlocksKey = 'debug.unlockedSkus.v1';

class DebugUnlocks extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    if (!kDebugMode) return const <String>{};
    _load();
    return const <String>{};
  }

  Future<void> _load() async {
    final raw = await ref.read(prefsStoreProvider).read(kDebugUnlocksKey);
    if (raw == null) return;
    try {
      state = {for (final s in jsonDecode(raw) as List) s as String};
    } catch (_) {
      // A corrupt record unlocks nothing, the safe direction.
    }
  }

  /// Unlock or relock one SKU.
  Future<void> set(String sku, bool on) async {
    if (!kDebugMode) return;
    final next = {...state};
    if (on) {
      next.add(sku);
    } else {
      next.remove(sku);
    }
    state = next;
    await ref
        .read(prefsStoreProvider)
        .write(kDebugUnlocksKey, jsonEncode(next.toList()..sort()));
  }
}

/// The SKUs a debug build treats as owned. Always empty in a release build.
final debugUnlocksProvider =
    NotifierProvider<DebugUnlocks, Set<String>>(DebugUnlocks.new);
