import 'package:device_probe/device_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../../core/i18n/g_strings.dart';
import '../../recovery/state/recovery_providers.dart';
import '../state/identity_providers.dart';
import '../widgets/device_detail.dart';

/// The software: the Android version as one large numeral, how old the
/// security patch is, then the build facts.
class SystemPage extends ConsumerWidget {
  const SystemPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const SystemPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final DeviceIdentity? id = ref.watch(deviceIdentityProvider).value;
    final int? patchAge = _patchAgeDays(id?.securityPatch);

    return DeviceDetail(
      title: context.s('System'),
      hero: id == null
          ? DeviceLoading(label: context.s('Reading the system'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.6, end: 1),
                      duration: GDesign.motion(context, GDesign.slow),
                      curve: Curves.easeOutBack,
                      builder:
                          (BuildContext context, double s, Widget? child) =>
                              Transform.scale(
                                scale: s,
                                alignment: Alignment.bottomLeft,
                                child: child,
                              ),
                      child: Text(
                        id.androidRelease,
                        style: g.figures(
                          g
                              .largeTitle(color: g.accentText)
                              .copyWith(fontSize: 72, height: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: GDesign.space12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Android', style: g.headline()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GDesign.space16),
                HeroFigures(
                  figures: <(String?, String)>[
                    (id.skin, context.s('Interface')),
                    (
                      patchAge == null
                          ? null
                          : patchAge < 45
                          ? context.s('Current')
                          : context.s1('{} days old', patchAge),
                      context.s('Security patch'),
                    ),
                  ],
                ),
              ],
            ),
      sections: <Widget>[
        if (id != null)
          FactSection(
            header: context.s('This phone'),
            rows: <(String, String?)>[
              (context.s('Name'), id.marketingName),
              (context.s('Maker'), id.manufacturer),
              (context.s('Model'), id.model),
              (context.s('API level'), '${id.sdkInt}'),
              (context.s('Security patch'), id.securityPatch),
            ],
          ),
        if (id != null)
          GroupedSection(
            header: context.s('Build'),
            footer: context.s('Tap to copy'),
            children: <Widget>[
              ListRow(
                title: id.fingerprint,
                trailing: Icon(GIcons.copy, size: 18, color: g.faint),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: id.fingerprint));
                  Haptics.confirm();
                },
              ),
            ],
          ),
      ],
    );
  }

  /// Days since a "YYYY-MM-DD" patch date, or null when it is not one.
  static int? _patchAgeDays(String? patch) {
    final DateTime? when = patch == null ? null : DateTime.tryParse(patch);
    return when == null ? null : DateTime.now().difference(when).inDays;
  }
}

/// What this app is allowed to read: a large lock that is open or shut,
/// one action when it can be opened, then the storage facts.
class AccessPage extends ConsumerWidget {
  const AccessPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const AccessPage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final StorageAccess? access = ref.watch(storageAccessProvider).value;
    final bool full = access?.allFilesAccessGranted ?? false;

    Future<void> allow() async {
      await ref.read(recoveryBridgeProvider).requestAllFilesAccess();
      ref
        ..invalidate(storageAccessProvider)
        ..invalidate(recoveryAccessProvider);
    }

    return DeviceDetail(
      title: context.s('Access'),
      onInfo: () => showDeviceNote(context, context.s('About access'), <String>[
        context.s(
          'With full access the app can reach trash folders, leftovers from '
          'other apps and the thumbnail cache. That is where most deleted '
          'files are found.',
        ),
        context.s(
          'Without it, only files this app made are visible. Nothing is ever '
          'sent anywhere either way.',
        ),
      ]),
      hero: access == null
          ? DeviceLoading(label: context.s('Checking access'))
          : Column(
              children: <Widget>[
                AnimatedSwitcher(
                  duration: GDesign.motion(context, GDesign.normal),
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      ScaleTransition(scale: a, child: child),
                  child: Icon(
                    full ? GIcons.shieldCheck : GIcons.lock,
                    key: ValueKey<bool>(full),
                    size: 64,
                    color: full ? g.accent : g.muted,
                  ),
                ),
                const SizedBox(height: GDesign.space12),
                Text(
                  full ? context.s('Full access') : context.s('Limited access'),
                  style: g.headline(),
                ),
                Text(
                  full
                      ? context.s('Every folder is reachable')
                      : context.s('Only this app\'s own files'),
                  style: g.footnote(),
                ),
                if (!full && access.allFilesAccessPossible) ...<Widget>[
                  const SizedBox(height: GDesign.space16),
                  PrimaryButton(label: context.s('Allow'), onTap: allow),
                ],
              ],
            ),
      sections: <Widget>[
        if (access != null)
          FactSection(
            header: context.s('Storage'),
            rows: <(String, String?)>[
              (context.s('Model'), _tier(context, access.tier)),
              (
                context.s('System trash'),
                access.osTrashBin ? context.s('Yes') : context.s('No'),
              ),
              (context.s('API level'), '${access.sdkInt}'),
            ],
          ),
      ],
    );
  }

  static String _tier(BuildContext context, String tier) => switch (tier) {
    'legacy' => context.s('Before scoped storage'),
    'scoped' => context.s('Scoped storage'),
    'managed' => context.s('Scoped, with full access'),
    _ => tier,
  };
}
