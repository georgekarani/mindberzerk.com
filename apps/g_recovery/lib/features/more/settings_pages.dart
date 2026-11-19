import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../app/theme/theme_controller.dart';
import '../../bridge/messages_api.g.dart';
import '../../bridge/recovery_api.g.dart';
import '../../core/i18n/g_strings.dart';
import '../messages/state/messages_providers.dart';
import '../recovery/state/recovery_providers.dart';

// ── Appearance ───────────────────────────────────────────────────────────

/// Light or dark, shown as two small phones, plus a switch to follow the
/// phone's own setting.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const AppearancePage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(gThemeProvider).mode;
    final GThemeController controller = ref.read(gThemeProvider.notifier);
    final bool auto = mode == ThemeMode.system;
    final Brightness shown = auto
        ? MediaQuery.platformBrightnessOf(context)
        : (mode == ThemeMode.dark ? Brightness.dark : Brightness.light);

    void pick(ThemeMode next) {
      Haptics.select();
      controller.setMode(next);
    }

    return LargeTitlePage(
      title: context.s('Appearance'),
      backLabel: context.s('More'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: GroupedSection(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GDesign.space24,
                  horizontal: GDesign.space16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    ModeChoice(
                      label: context.s('Light'),
                      dark: false,
                      selected: shown == Brightness.light,
                      onTap: () => pick(ThemeMode.light),
                    ),
                    ModeChoice(
                      label: context.s('Dark'),
                      dark: true,
                      selected: shown == Brightness.dark,
                      onTap: () => pick(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
              ListRow(
                title: context.s('Match the phone'),
                trailing: ToggleSwitch(
                  value: auto,
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
        ),
      ],
    );
  }
}

/// One mode: a miniature screen drawn in that mode's colours, its name, and
/// a round check.
class ModeChoice extends StatelessWidget {
  const ModeChoice({
    required this.label,
    required this.dark,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool dark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final GDesignTheme mini = dark
        ? GDesignTheme.dark(
            accent: g.accent,
            accentText: g.accentText,
            sans: g.sans,
            mono: g.mono,
          )
        : GDesignTheme.light(
            accent: g.accent,
            accentText: g.accentText,
            sans: g.sans,
            mono: g.mono,
          );

    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      child: Column(
        children: <Widget>[
          AnimatedContainer(
            duration: GDesign.motion(context, GDesign.fast),
            width: 92,
            height: 168,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? g.accent : g.hairline,
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: mini.ground,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Bar(color: mini.text, width: 40, height: 7),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: mini.fill,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _Bar(color: mini.text, width: 46, height: 4),
                      const SizedBox(height: 3),
                      _Bar(color: mini.muted, width: 30, height: 4),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: mini.fill,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: mini.card,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: mini.hairline),
                        ),
                        alignment: Alignment.center,
                        child: _Bar(color: mini.accent, width: 10, height: 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: GDesign.space12),
          Text(label, style: g.body()),
          const SizedBox(height: GDesign.space8),
          SelectMark(selected: selected),
        ],
      ),
    );
  }
}

/// A rounded line standing in for text in the miniature.
class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.width, required this.height});

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}

// ── Permissions ──────────────────────────────────────────────────────────

/// The two switches the app needs from Android, each with what it unlocks
/// and a way to turn it on.
class PermissionsPage extends ConsumerWidget {
  const PermissionsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const PermissionsPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecoveryAccess? access = ref.watch(recoveryAccessProvider).value;
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;
    final bool files = access?.allFilesAccess ?? false;
    final bool notes = capture?.listenerEnabled ?? false;

    return LargeTitlePage(
      title: context.s('Permissions'),
      backLabel: context.s('More'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: GroupedSection(
            children: <Widget>[
              ListRow(
                icon: GIcons.folderOpen,
                title: context.s('All files'),
                subtitle: context.s('Reach every app folder'),
                detail: files ? context.s('On') : context.s('Off'),
                onTap: files
                    ? null
                    : () async {
                        await ref
                            .read(recoveryBridgeProvider)
                            .requestAllFilesAccess();
                        ref.invalidate(recoveryAccessProvider);
                      },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space24),
            child: GroupedSection(
              children: <Widget>[
                ListRow(
                  icon: GIcons.bell,
                  title: context.s('Notifications'),
                  subtitle: context.s('Keep messages before deletion'),
                  detail: notes ? context.s('On') : context.s('Off'),
                  onTap: () async {
                    await ref
                        .read(messagesBridgeProvider)
                        .openListenerSettings();
                    ref.invalidate(messageCaptureProvider);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Privacy ──────────────────────────────────────────────────────────────

/// Everything that leaves the phone, all three, and what never does.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const PrivacyPage(),
  );

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return LargeTitlePage(
      title: context.s('Privacy'),
      backLabel: context.s('More'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GDesign.gutter,
              0,
              GDesign.gutter,
              GDesign.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.s('Nothing of yours leaves this phone'),
                  style: g.title2(),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: context.s('What goes out'),
            children: <Widget>[
              ListRow(
                icon: GIcons.download,
                title: context.s('Recovery coverage'),
                subtitle: context.s('Where phones hide deleted files'),
              ),
              ListRow(
                icon: GIcons.refresh,
                title: context.s('Update check'),
                subtitle: context.s('Asks Play for a newer version'),
              ),
              ListRow(
                icon: GIcons.eye,
                title: context.s('Which screens you open'),
                subtitle: context.s('Never what was on them'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: GDesign.space24),
            child: GroupedSection(
              header: context.s('What never does'),
              children: <Widget>[
                ListRow(
                  icon: GIcons.docs,
                  title: context.s('Your files, and every scan of them'),
                ),
                ListRow(
                  icon: GIcons.messages,
                  title: context.s('The message archive'),
                ),
                ListRow(
                  icon: GIcons.server,
                  title: context.s('Your home server address and password'),
                ),
                ListRow(
                  icon: GIcons.lock,
                  title: context.s('There is no account to attach it to'),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: GDesign.space24,
              bottom: GDesign.space32,
            ),
            child: GroupedSection(
              children: <Widget>[
                ListRow(
                  icon: GIcons.shieldCheck,
                  title: context.s('No ads, ever'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
