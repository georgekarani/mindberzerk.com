import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/theme/theme_controller.dart';
import '../../bridge/apps_api.g.dart';
import '../../bridge/apps_bridge.dart';
import '../../bridge/hardware_bridge.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import '../../ui/art/escape_art.dart';
import '../device/widgets/device_detail.dart';
import '../more/settings_pages.dart';
import '../recovery/state/recovery_providers.dart';
import 'state/onboarding_providers.dart';

/// First run in three screens that slide into each other: what the app
/// does, a look, and the access it needs. The quick scan starts on the
/// first frame, so the last screen can say how much it already found.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage>
    with WidgetsBindingObserver {
  int _step = 0;
  static const int _steps = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(prescanProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Settings screens return here; re-read what was granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref
      ..invalidate(recoveryAccessProvider)
      ..invalidate(appsStateProvider);
  }

  void _go(int step) {
    Haptics.select();
    setState(() => _step = step);
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && _step > 0) _go(_step - 1);
      },
      child: Material(
        color: g.ground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GDesign.gutter),
            child: Column(
              children: <Widget>[
                const SizedBox(height: GDesign.space12),
                _Dots(step: _step, of: _steps),
                Expanded(
                  child: DirectionalSwitcher(
                    index: _step,
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: switch (_step) {
                        0 => _Welcome(onNext: () => _go(1)),
                        1 => _Look(onNext: () => _go(2)),
                        _ => const _Access(),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Progress as dots; the current one stretches into a pill.
class _Dots extends StatelessWidget {
  const _Dots({required this.step, required this.of});

  final int step;
  final int of;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final Duration d = GDesign.motion(context, GDesign.normal);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < of; i++)
          AnimatedContainer(
            duration: d,
            curve: GDesign.enter,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == step ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i <= step ? g.accent : g.text.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// What the app does, in one line under moving art.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Spacer(),
        const EscapeArt(height: 260),
        const SizedBox(height: GDesign.space32),
        Reveal(
          child: Text(
            context.s('Deleted is not always gone'),
            style: g.largeTitle(),
          ),
        ),
        const SizedBox(height: GDesign.space8),
        Reveal(
          index: 1,
          child: Text(
            context.s('Find it, see it, bring it back'),
            style: g.body(color: g.muted),
          ),
        ),
        const Spacer(),
        PrimaryButton(label: context.s('Get started'), onTap: onNext),
        const SizedBox(height: GDesign.space24),
      ],
    );
  }
}

/// Light or dark, drawn as two small phones, with the quick scan's status
/// underneath.
class _Look extends ConsumerWidget {
  const _Look({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final ThemeMode mode = ref.watch(gThemeProvider).mode;
    final GThemeController controller = ref.read(gThemeProvider.notifier);
    final bool checked = ref.watch(prescanProvider).hasValue;
    final Brightness shown = mode == ThemeMode.system
        ? MediaQuery.platformBrightnessOf(context)
        : (mode == ThemeMode.dark ? Brightness.dark : Brightness.light);

    void pick(ThemeMode next) {
      Haptics.select();
      controller.setMode(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: GDesign.space48),
        Text(context.s('Pick a look'), style: g.largeTitle()),
        const SizedBox(height: GDesign.space8),
        Text(
          context.s('Change it any time in Settings'),
          style: g.body(color: g.muted),
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            Reveal(
              child: ModeChoice(
                label: context.s('Light'),
                dark: false,
                selected: shown == Brightness.light,
                onTap: () => pick(ThemeMode.light),
              ),
            ),
            Reveal(
              index: 1,
              child: ModeChoice(
                label: context.s('Dark'),
                dark: true,
                selected: shown == Brightness.dark,
                onTap: () => pick(ThemeMode.dark),
              ),
            ),
          ],
        ),
        const SizedBox(height: GDesign.space24),
        GroupedSection(
          children: <Widget>[
            ListRow(
              title: context.s('Match the phone'),
              trailing: ToggleSwitch(
                value: mode == ThemeMode.system,
                semanticLabel: context.s('Match the phone'),
                onChanged: (bool on) => pick(
                  on
                      ? ThemeMode.system
                      : (shown == Brightness.dark
                            ? ThemeMode.dark
                            : ThemeMode.light),
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (checked)
              Icon(GIcons.checkCircle, size: 16, color: g.accentText)
            else
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(width: GDesign.space8),
            Text(
              checked
                  ? context.s('Your phone is checked')
                  : context.s('Checking your phone'),
              style: g.footnote(),
            ),
          ],
        ),
        const SizedBox(height: GDesign.space16),
        PrimaryButton(label: context.s('Continue'), onTap: onNext),
        const SizedBox(height: GDesign.space24),
      ],
    );
  }
}

/// The access the app works best with, as switches, and the count the quick
/// scan found as the headline.
class _Access extends ConsumerStatefulWidget {
  const _Access();

  @override
  ConsumerState<_Access> createState() => _AccessState();
}

class _AccessState extends ConsumerState<_Access> {
  /// Set once the user has been sent to a settings screen, which is when
  /// "Continue without it" becomes fair to offer.
  bool _asked = false;

  Future<void> _ask(Future<Object?> Function() request) async {
    await request();
    if (mounted) setState(() => _asked = true);
  }

  Future<void> _finish() async {
    await ref.read(recoveryBridgeProvider).startBackgroundScan();
    ref.read(onboardingDoneProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool files =
        ref.watch(recoveryAccessProvider).value?.allFilesAccess ?? false;
    final AppsState? apps = ref.watch(appsStateProvider).value;
    final bool sizes = apps?.usageAccess ?? false;
    final int found = ref.watch(prescanProvider).value?.deletedItems ?? 0;

    void explain(String title, String text) =>
        showDeviceNote(context, title, <String>[text]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: GDesign.space48),
        if (found > 0)
          CountUpText(
            value: found,
            format: (num v) =>
                context.s1('{} files can come back', GFormat.count(v.round())),
            style: g.figures(g.largeTitle()),
          )
        else
          Text(context.s('Let it look everywhere'), style: g.largeTitle()),
        const SizedBox(height: GDesign.space8),
        Text(
          context.s('All optional, all changeable later'),
          style: g.body(color: g.muted),
        ),
        const Spacer(),
        GroupedSection(
          children: <Widget>[
            ListRow(
              icon: GIcons.folderOpen,
              title: context.s('All files'),
              subtitle: context.s('Finds what other apps deleted'),
              onTap: () => explain(
                context.s('All files'),
                context.s(
                  'Android only shows an app the files it deleted itself. '
                  'This lets G Recovery see trash folders, app leftovers and '
                  'the thumbnail cache, where most deleted files are.',
                ),
              ),
              trailing: ToggleSwitch(
                value: files,
                semanticLabel: context.s('All files'),
                onChanged: files
                    ? null
                    : (_) => _ask(
                        ref.read(recoveryBridgeProvider).requestAllFilesAccess,
                      ),
              ),
            ),
            ListRow(
              icon: GIcons.grid,
              title: context.s('App sizes'),
              subtitle: context.s('Shows what each app takes'),
              onTap: () => explain(
                context.s('App sizes'),
                context.s(
                  'Usage access lets the Apps list show sizes and cache. It '
                  'reads sizes, never what you do in apps.',
                ),
              ),
              trailing: ToggleSwitch(
                value: sizes,
                semanticLabel: context.s('App sizes'),
                onChanged: sizes
                    ? null
                    : (_) =>
                          _ask(ref.read(appsBridgeProvider).requestUsageAccess),
              ),
            ),
            ListRow(
              icon: GIcons.wifi,
              title: context.s('Wi-Fi name'),
              subtitle: context.s('Android files it under location'),
              onTap: () =>
                  _ask(ref.read(hardwareBridgeProvider).requestLocation),
            ),
          ],
        ),
        const Spacer(),
        PrimaryButton(
          label: files
              ? context.s('Scan my phone')
              : context.s('Allow all files'),
          onTap: files
              ? _finish
              : () => _ask(
                  ref.read(recoveryBridgeProvider).requestAllFilesAccess,
                ),
        ),
        AnimatedSize(
          duration: GDesign.motion(context, GDesign.normal),
          child: _asked && !files
              ? Padding(
                  padding: const EdgeInsets.only(top: GDesign.space8),
                  child: SecondaryButton(
                    label: context.s('Continue without it'),
                    onTap: _finish,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: GDesign.space24),
      ],
    );
  }
}
