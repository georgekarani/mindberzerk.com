import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bridge/recovery_api.g.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../../core/messenger/g_message.dart';
import '../../../core/messenger/g_messenger.dart';
import 'recovery_providers.dart';

/// What a restore or a permanent delete actually did, item by item.
@immutable
class RecoveryActionResult {
  const RecoveryActionResult({required this.done, this.problem});

  /// Ids the native side confirmed. Only these get the restore flight or the
  /// dust; anything else stays on screen, because it is still there.
  final Set<String> done;

  /// The first failure's own explanation, when any item failed.
  final String? problem;
}

/// Restores ([purge] false) or permanently deletes ([purge] true) the items,
/// and reports what really happened.
///
/// Does not refresh the lists: callers play the flight or the dust over the
/// items first, while they are still on screen, then call [refreshRecovery].
Future<RecoveryActionResult> runRecoveryAction(
  WidgetRef ref,
  List<String> itemIds, {
  required bool purge,
}) async {
  final List<RestoreOutcome> outcomes = purge
      ? await ref.read(recoveryBridgeProvider).purge(itemIds)
      : await ref.read(recoveryBridgeProvider).restore(itemIds);
  final Set<String> done = <String>{};
  String? problem;
  for (final RestoreOutcome outcome in outcomes) {
    if (outcome.status == 'restored') {
      done.add(outcome.itemId);
    } else {
      problem ??= outcome.detail;
    }
  }
  return RecoveryActionResult(done: done, problem: problem);
}

/// Every count and list that a restore or delete changed, asked again.
///
/// A restore moves files between sources, so all lists are forgotten, not
/// only the one the action started from.
void refreshRecovery(WidgetRef ref) {
  ref.read(selectionProvider.notifier).clear();
  ref.read(scanControllerProvider.notifier).forget();
  ref.invalidate(recoveryItemsProvider);
  ref.invalidate(prescanProvider);
}

/// Says something only when part of an action failed. Success needs no
/// message: the photo flying home or turning to dust already said it.
void reportRecoveryProblem(BuildContext context, RecoveryActionResult result) {
  final String? problem = result.problem;
  if (problem == null) return;
  final String done = context.s1('{} done.', GFormat.count(result.done.length));
  GMessenger.show(context, GMessage.warning('$done $problem'));
}
