import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../i18n/g_strings.dart';
import '../prefs/prefs_keys.dart';
import '../prefs/prefs_store.dart';
import 'app_update.dart';

/// Offers a new version once, as a sheet: Update downloads it through Play
/// in the background, and the same sheet turns into Restart when it lands.
///
/// Shown at most once per Play build. Dismissing it is an answer; the More
/// row still carries the update for anyone who changes their mind.
Future<void> offerUpdateOnce(BuildContext context, WidgetRef ref) async {
  final GUpdateState update = ref.read(gUpdateProvider);
  final int? build = update.availableVersionCode;
  if (update.stage != GUpdateStage.available || build == null) return;
  if (!update.flexibleAllowed && !update.immediateAllowed) return;

  final PrefsStore prefs = ref.read(prefsStoreProvider);
  if (prefs.readInt(GPrefsKeys.updateOffered) == build) return;
  await prefs.writeInt(GPrefsKeys.updateOffered, build);
  if (!context.mounted) return;

  await presentSheet<void>(
    context: context,
    builder: (BuildContext sheet) => const _UpdateSheet(),
  );
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final GUpdateState update = ref.watch(gUpdateProvider);
    final GUpdateController controller = ref.read(gUpdateProvider.notifier);
    final bool ready = update.stage == GUpdateStage.ready;
    final bool fetching = update.stage == GUpdateStage.downloading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space24,
        GDesign.gutter,
        GDesign.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Badge(ready: ready, busy: fetching),
          const SizedBox(height: GDesign.space16),
          DirectionalSwitcher(
            index: ready ? 1 : 0,
            child: Text(
              ready
                  ? context.s('Ready to restart')
                  : context.s('A new version is here'),
              key: ValueKey<bool>(ready),
              style: g.title2(),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: GDesign.space24),
          PrimaryButton(
            pill: true,
            busy: fetching,
            label: ready ? context.s('Restart') : context.s('Update'),
            icon: ready ? GIcons.refresh : GIcons.download,
            onTap: fetching
                ? null
                : () async {
                    Haptics.confirm();
                    if (ready) {
                      await controller.install();
                    } else if (update.flexibleAllowed) {
                      await controller.download();
                    } else {
                      if (context.mounted) Navigator.of(context).pop();
                      await controller.updateNow();
                    }
                  },
          ),
          const SizedBox(height: GDesign.space8),
          Pressable(
            onTap: () => Navigator.of(context).pop(),
            semanticLabel: context.s('Later'),
            child: SizedBox(
              height: GDesign.touch,
              child: Center(
                child: Text(context.s('Later'), style: g.footnote()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's download mark: an accent disc that breathes while Play
/// fetches, and swaps its arrow for a restart mark when the file is in.
class _Badge extends StatefulWidget {
  const _Badge({required this.ready, required this.busy});

  final bool ready;
  final bool busy;

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Badge old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final bool move = widget.busy && !MediaQuery.disableAnimationsOf(context);
    if (move && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!move && _breath.isAnimating) {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return ScaleTransition(
      scale: Tween<double>(
        begin: 1,
        end: 1.08,
      ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut)),
      child: DecoratedBox(
        decoration: BoxDecoration(color: g.accent, shape: BoxShape.circle),
        child: SizedBox.square(
          dimension: 72,
          child: AnimatedSwitcher(
            duration: GDesign.motion(context, GDesign.normal),
            transitionBuilder: (Widget child, Animation<double> a) =>
                RotationTransition(
                  turns: Tween<double>(begin: -0.25, end: 0).animate(a),
                  child: FadeTransition(opacity: a, child: child),
                ),
            child: Icon(
              widget.ready ? GIcons.refresh : GIcons.download,
              key: ValueKey<bool>(widget.ready),
              size: 32,
              color: g.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}
