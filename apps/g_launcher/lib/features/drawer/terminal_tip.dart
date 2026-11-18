/// One quiet line, once: the Terminal is in your apps.
///
/// ─── WHY ────────────────────────────────────────────────────────────────────
///
/// A review asked how to use the terminal. It is an app in the drawer like any
/// other, which is exactly why nobody notices it. So the first time someone
/// opens their apps, the launcher says where it is and offers to open it, in
/// the same branded message every other notice uses. Then never again.
///
/// Not on the Terminal distro, whose whole desktop already is one, and never
/// on first boot of the launcher itself: only once someone has gone looking
/// for their apps, which is when a pointer to one more app is relevant.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/prefs_repository.dart';
import '../../design/branded_message.dart';
import '../../engine/effective_theme.dart';
import '../../engine/theme_spec.dart';
import '../terminal/terminal_screen.dart';
import 'drawer_items.dart';

/// Its own top-level key, so Restore defaults never shows it again.
const kTerminalTipKey = 'tip.terminal.v1';

class TerminalTip extends ConsumerStatefulWidget {
  const TerminalTip({super.key, required this.theme, required this.child});

  final EffectiveTheme theme;
  final Widget child;

  @override
  ConsumerState<TerminalTip> createState() => _TerminalTipState();
}

class _TerminalTipState extends ConsumerState<TerminalTip> {
  /// Long enough for the drawer's own entrance to finish first.
  static const _delay = Duration(milliseconds: 700);

  /// Cancelled on dispose, so a drawer closed inside [_delay] never fires it.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.theme.shell == ShellKind.tui) return;
    _timer = Timer(_delay, _maybeShow);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShow() async {
    // `ref` resolves through `context`, which is `_element!` once unmounted:
    // touching it after the drawer closed was the release Null check crash.
    if (!mounted) return;
    final store = ref.read(prefsStoreProvider);
    if (await store.read(kTerminalTipKey) != null || !mounted) return;
    // Written before showing, so a crash mid-message cannot repeat it.
    await store.write(kTerminalTipKey, '1');
    if (!mounted) return;
    final theme = widget.theme;
    // The toast outlives the drawer, so its action holds the Navigator rather
    // than this State: Open still works after the drawer has closed.
    final navigator = Navigator.of(context);
    context.showMessage(
      context.t('tip.terminal', {'name': terminalLabelFor(theme)}),
      actionLabel: context.t('tip.open'),
      onAction: () {
        if (navigator.mounted) openTerminal(navigator.context, theme);
      },
      duration: const Duration(seconds: 6),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
