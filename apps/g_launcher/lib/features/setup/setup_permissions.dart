import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/prefs/prefs_repository.dart';
import '../../engine/effective_theme.dart';
import '../../engine/theme_spec.dart';
import '../../i18n/i18n.dart';
import '../../system/notification_badges.dart';
import 'setup_live_preview.dart';
import 'setup_sheet.dart';

/// Board 4, Before installing: the home app and notification badges.
///
/// The two things only Android can grant, asked together and last, when the
/// user has just watched their desktop take shape and has a reason to say yes.
///
/// The home role matters most: without it the launcher is an app that is
/// forgotten the moment it is closed. So Install asks for it itself, once, and
/// once more with the reason if the first answer was no. See the setup
/// screen's `_install` for the sequence.
class SetupPermissions extends ConsumerWidget {
  const SetupPermissions({
    super.key,
    required this.theme,
    required this.isDefault,
    required this.homeAsks,
    required this.onInstall,
    required this.onBack,
  });

  final EffectiveTheme theme;

  /// Whether G Launcher already holds the home role.
  final bool isDefault;

  /// How many times Android's home picker has been opened from here.
  final int homeAsks;

  final VoidCallback onInstall;
  final VoidCallback onBack;

  /// Shells whose badge style resolves to none have nowhere to draw one.
  bool get _offersBadges =>
      theme.shell != ShellKind.tui && theme.shell != ShellKind.tiling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = SetupInk.forSpec(theme.spec);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final granted =
        ref.watch(notificationAccessProvider).asData?.value ?? false;
    final style = badgeStyleFor(theme);

    final homeStatus = isDefault
        ? ref.t('setup.perm.homeSet')
        : homeAsks == 0
            ? ref.t('setup.perm.homeAsk')
            : ref.t('setup.perm.homeStill');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: SetupStageScaffold(
        theme: theme,
        ink: ink,
        liveLabel: ref.t('setup.ready.live'),
        sheetFraction: _offersBadges ? 0.64 : 0.5,
        showPreview: theme.shell != ShellKind.tui,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SetupGrip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: SetupHeading(
                ink: ink,
                kicker: ref.t('setup.perm.kicker'),
                title: _offersBadges
                    ? ref.t('setup.perm.title')
                    : ref.t('setup.perm.titleHomeOnly'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _Card(
                    ink: ink,
                    icon: Icons.home_outlined,
                    highlight: !isDefault,
                    title: ref.t('setup.perm.homeTitle'),
                    body: ref.t(
                      'setup.perm.homeBody',
                      {'name': theme.spec.name},
                    ),
                    footer: _Status(
                      ink: ink,
                      done: isDefault,
                      warn: !isDefault && homeAsks > 0,
                      label: homeStatus,
                    ),
                  ),
                  if (_offersBadges) ...[
                    const SizedBox(height: 12),
                    _Card(
                      ink: ink,
                      icon: Icons.notifications_none_rounded,
                      title: ref.t('setup.perm.badgesTitle'),
                      body: ref.t('setup.perm.badgesBody'),
                      footer: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SetupSegmented<BadgeStyle>(
                            ink: ink,
                            options: {
                              BadgeStyle.none: ref.t('setup.perm.badgesOff'),
                              BadgeStyle.dot: ref.t('setup.perm.badgesDots'),
                              BadgeStyle.count:
                                  ref.t('setup.perm.badgesNumbers'),
                            },
                            selected: style,
                            onChanged: (v) => ref
                                .read(prefsProvider(theme.spec.id).notifier)
                                .edit(
                                  (p) => p.copyWith(
                                    badgeStyle: switch (v) {
                                      BadgeStyle.none => 'off',
                                      BadgeStyle.dot => 'dot',
                                      BadgeStyle.count => 'count',
                                    },
                                  ),
                                ),
                          ),
                          if (style != BadgeStyle.none) ...[
                            const SizedBox(height: 10),
                            _Status(
                              ink: ink,
                              done: granted,
                              label: granted
                                  ? ref.t('setup.perm.badgesAllowed')
                                  : ref.t('setup.perm.badgesAsk'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SetupPrimaryButton(
                    ink: ink,
                    label: ref.t('setup.next.install'),
                    onPressed: onInstall,
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: SetupLink(
                      ink: ink,
                      label: ref.t('common.back'),
                      onPressed: onBack,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One permission: an icon, what it is for, and its state underneath.
class _Card extends StatelessWidget {
  const _Card({
    required this.ink,
    required this.icon,
    required this.title,
    required this.body,
    required this.footer,
    this.highlight = false,
  });

  final SetupInk ink;
  final IconData icon;
  final String title;
  final String body;
  final Widget footer;

  /// Tints the icon plate in the accent: the one the user still has to act on.
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: highlight
                        ? ink.accent.withValues(alpha: 0.25)
                        : const Color(0x1AFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: ink.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: ink.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: ink.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            footer,
          ],
        ),
      );
}

/// A coloured dot and a line of state: done, waiting, or needs attention.
class _Status extends StatelessWidget {
  const _Status({
    required this.ink,
    required this.done,
    required this.label,
    this.warn = false,
  });

  final SetupInk ink;
  final bool done;
  final bool warn;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: done
                ? const Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: Color(0xFF26A269),
                  )
                : Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: warn
                          ? const Color(0xFFE66100)
                          : const Color(0xFFF1C232),
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, height: 1.4, color: ink.textMuted),
            ),
          ),
        ],
      );
}
