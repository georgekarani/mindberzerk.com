import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../bridge/storage_api.g.dart';
import '../../../core/format.dart';
import '../../../core/i18n/g_strings.dart';
import '../../../core/messenger/g_message.dart';
import '../../../core/messenger/g_messenger.dart';
import 'storage_providers.dart';

/// What moving files to the system trash actually did.
@immutable
class TrashResult {
  const TrashResult({required this.done, required this.consent});

  /// Ids Android confirmed as trashed. Only these turn to dust.
  final Set<String> done;

  /// Android stopped to ask the user to confirm; nothing else went wrong.
  final bool consent;
}

/// Moves files to the system trash, where Android keeps them for 30 days
/// and Recovery can bring them back. Never a permanent delete.
Future<TrashResult> trashFiles(WidgetRef ref, List<String> fileIds) async {
  final List<StorageOutcome> outcomes = await ref
      .read(storageBridgeProvider)
      .remove(fileIds, permanent: false);
  return TrashResult(
    done: <String>{
      for (final StorageOutcome o in outcomes)
        if (o.status == 'trashed' || o.status == 'deleted') o.fileId,
    },
    consent: outcomes.any((StorageOutcome o) => o.status == 'needsConsent'),
  );
}

/// Turns each confirmed file's tile to dust, up to two dozen, one after
/// another so the eye can follow them.
Future<void> dustAway(
  BuildContext context,
  Iterable<String> ids,
  Map<String, GlobalKey> keys,
) async {
  int n = 0;
  for (final String id in ids) {
    final GlobalKey? key = keys[id];
    if (key == null || n++ >= 24) continue;
    await Dust.scatter(context, key);
    if (!context.mounted) return;
  }
}

/// One line on what happened, said once.
void reportTrash(BuildContext context, TrashResult result, int freedBytes) {
  if (result.consent) {
    GMessenger.show(
      context,
      GMessage(context.s('Android is asking you to confirm those')),
    );
    return;
  }
  if (result.done.isEmpty) return;
  GMessenger.show(
    context,
    GMessage.success(
      context.s1(
        'Freed {}. They wait in Recovery for 30 days.',
        GFormat.bytes(freedBytes),
      ),
    ),
  );
}
