/// The home layout lock. PHASE G1.
///
/// One switch, global across distros like the hidden set: when it is on,
/// icons, the dock, desklets and panel modules stay where they are. Launching,
/// opening folders and changing the wallpaper or theme all still work.
///
/// ─── TWO LAYERS, AND WHY BOTH ───────────────────────────────────────────────
///
/// [DeskletEdit] refuses to enter any edit mode while locked. That is the
/// floor: every jiggle, every resize handle and every panel editor starts
/// there, so nothing can open one by accident, including a hold that some
/// future surface wires up without knowing about the lock.
///
/// The floor is silent, which is right for a backstop and wrong for a person.
/// So the places a person actually reaches for (a hold, a drop, a menu action)
/// ask [layoutLockRefuses] first, which says why nothing happened and offers
/// the way out in the same message.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/prefs_repository.dart';
import '../../design/branded_message.dart';

/// Whether the home layout is locked. False until the global bucket loads,
/// so a cold start never refuses a gesture on a guess.
final layoutLockedProvider = Provider<bool>(
  (ref) => ref.watch(globalPrefsProvider).asData?.value.layoutLocked ?? false,
);

/// Lock or unlock the layout for every distro.
///
/// Written straight to the global bucket rather than through a theme's
/// `PrefsNotifier.edit`, because the message's Unlock button can outlive the
/// widget that showed it and has only the container to work with. The result
/// is the same write the settings switch makes: `layoutLocked` is promoted, so
/// that switch lands here too.
Future<void> writeLayoutLocked(ProviderContainer container, bool locked) async {
  final current = await container.read(globalPrefsProvider.future);
  await container
      .read(globalPrefsProvider.notifier)
      .write(current.withLayoutLocked(locked));
}

/// True, after telling the person, when the layout is locked.
///
/// Call at the top of anything that would move, add or remove something on
/// the home screen, the dock or the panel, and return when it answers true:
///
///     if (layoutLockRefuses(context)) return;
///
/// Takes only a [BuildContext] so the docks, which are plain widgets with no
/// `ref`, can ask too.
bool layoutLockRefuses(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(layoutLockedProvider)) return false;

  context.showMessage(
    context.t('home.layoutLocked'),
    actionLabel: context.t('home.unlock'),
    onAction: () => writeLayoutLocked(container, false),
    // Longer than the default: the message carries the way out, and a
    // button that is gone before the thumb arrives is no way out at all.
    duration: const Duration(milliseconds: 4500),
  );
  return true;
}
