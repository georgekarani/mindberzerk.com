/// Quick Settings: the things this launcher actually owns, under your thumb.
///
/// ─── WHY THIS IS NOT A COPY OF ANDROID'S TRAY ───────────────────────────────
///
/// The obvious build is six pill toggles: Wi-Fi, Bluetooth, torch, dark mode,
/// rotate, night light. Most of them cannot be built, and shipping them anyway
/// would be a panel where half the controls accept a tap and change nothing.
///
///   * `WifiManager.setWifiEnabled` has been refused to third-party apps since
///     Android 10. A launcher can OPEN the Wi-Fi panel; it cannot flip it.
///   * Night light has no public API at all.
///   * Rotate and brightness both need `WRITE_SETTINGS`, a special-access grant
///     the user has to go and find, and a toggle that silently does nothing
///     until they do is worse than no toggle.
///
/// So every tile here is something the launcher genuinely owns: who draws the
/// status icons, G VPN, light and dark, the desktop layout, the accent.
///
/// ─── ONE SHEET, FIVE DESKTOPS ───────────────────────────────────────────────
///
/// The same controls are drawn in the idiom of the shell they open from, so
/// the sheet reads as part of that desktop rather than a launcher overlay:
///
///   * GNOME: pill toggles with a split arrow, as in GNOME 46.
///   * Plasma: Breeze tiles, icon over label, accent tint and edge.
///   * Aqua: Control Centre modules on frosted glass.
///   * Tiling: a rofi-style grid in a sharp accent frame, lowercase mono.
///   * Terminal: a box-drawn menu with checkboxes.
///
/// ─── NO TEXT IS EVER CUT ────────────────────────────────────────────────────
///
/// Forty-seven languages ship, and German, Finnish or Tamil labels run two or
/// three times the English. Nothing in this file sets `maxLines` or an
/// ellipsis, and nothing that holds text has a fixed height: tiles take a
/// minimum height and grow, and a row of tiles grows together so the grid stays
/// even. A label that is long gets a second line, never a "...".
///
/// ─── IT OPENS FROM WHAT OPENED IT ───────────────────────────────────────────
///
/// The tray button and the GNOME status area pass their own rect to [toggle],
/// and the sheet hangs off that edge: down from a top bar, up from a bottom
/// panel. Opened with no rect (the keyboard), it falls back to the panel edge.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_family/g_family.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/layout_preset.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../data/repositories/app_repository.dart';
import '../../data/update/update_repository.dart';
import '../../engine/effective_theme.dart';
import '../../engine/theme_spec.dart';
import '../../system/gvpn_status.dart';
import '../../system/notification_badges.dart';
import '../../system/system_stats.dart';
import '../../platform/launcher_api.g.dart' show AppEntry, NowPlaying;
import '../desklets/desklet_edit.dart';
import '../drawer/app_icon.dart';
import '../panel/applets/clock_panel_sections.dart'
    show clockPanelMediaProvider, notificationCounts, openNotificationShade;
import '../panel/modules/panel_readouts.dart';
import '../panel/panel_edit.dart';
import '../panel/panel_editor_sheet.dart';
import '../panel/panel_modules.dart' show panelIsNarrow;
import '../settings/settings_screen.dart';
import '../settings/settings_sheets.dart' show confirmUpdateRestart;
import 'workspaces/workspace_controller.dart';

/// Is the Quick Settings panel open?
final quickSettingsProvider =
    NotifierProvider<QuickSettingsOpen, bool>(QuickSettingsOpen.new);

class QuickSettingsOpen extends Notifier<bool> {
  /// Where on screen the control that opened the sheet sits, if it said.
  Rect? anchor;

  @override
  bool build() => false;

  /// Opens the sheet. [from] is the opener's context, so the sheet can hang
  /// off the right edge of the screen.
  void open({BuildContext? from}) {
    anchor = _rectOf(from);
    if (!state) state = true;
  }

  void close() {
    if (state) state = false;
  }

  void toggle({BuildContext? from}) => state ? close() : open(from: from);

  static Rect? _rectOf(BuildContext? context) {
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// The panel. Mounted above the shell, drawing nothing while closed.
class QuickSettingsPanel extends ConsumerWidget {
  const QuickSettingsPanel({super.key, required this.theme});

  final EffectiveTheme theme;

  /// Clear of the bar it hangs from.
  static const _gap = 8.0;

  /// The side panel's widest, so a tablet gets a panel and not half a screen.
  static const _sideWidth = 380.0;

  /// The sheet's widest away from a phone, centred on its anchor.
  static const _maxWidth = 440.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(quickSettingsProvider)) return const SizedBox.shrink();

    final notifier = ref.read(quickSettingsProvider.notifier);
    final look = _Look.of(theme);
    final media = MediaQuery.of(context);
    final screen = media.size;
    final pad = media.padding;

    // Down from a control in the top half, up from one in the bottom half.
    // With no rect, the shell's own panel edge decides.
    final anchor = notifier.anchor;
    final fromTop = anchor != null
        ? anchor.center.dy < screen.height / 2
        : theme.panelSide == TopBarSide.top;
    final fallbackBar = theme.panelHeight ?? 56;
    final top = fromTop
        ? (anchor?.bottom ?? pad.top + fallbackBar) + _gap
        : pad.top + _gap;
    final bottom = fromTop
        ? pad.bottom + _gap
        : (anchor != null
                ? screen.height - anchor.top
                : pad.bottom + fallbackBar) +
            _gap;

    final width = (screen.width - 16).clamp(0.0, _maxWidth);
    final centre = anchor?.center.dx ?? screen.width / 2;
    final left = (centre - width / 2).clamp(8.0, screen.width - width - 8);

    final Widget sheet = _Sheet(theme: theme, look: look);

    return Material(
      // theme-exempt: the sheet paints the palette itself a layer down.
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: notifier.close,
              child: ColoredBox(
                // Light, so the desktop stays visible: the accent swatches
                // are judged against it.
                color: theme.palette.bgBottom.withValues(alpha: 0.4),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Deepin's Control Center opens as a tall panel against the right
          // edge. Every other distro hangs the sheet off its bar.
          if (theme.quickSettingsSide)
            Positioned(
              top: pad.top + _gap,
              bottom: pad.bottom + _gap,
              right: _gap,
              width: (screen.width * 0.9).clamp(0.0, _sideWidth),
              child: _Entrance(
                offset: const Offset(0.12, 0),
                child: SingleChildScrollView(child: sheet),
              ),
            )
          else
            Positioned(
              left: left,
              width: width,
              top: fromTop ? top : null,
              bottom: fromTop ? null : bottom,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (screen.height - top - bottom).clamp(0.0, 4000),
                ),
                child: _Entrance(
                  offset: Offset(0, fromTop ? -0.04 : 0.04),
                  child: SingleChildScrollView(
                    reverse: !fromTop,
                    child: sheet,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A short slide and fade in from the edge the sheet hangs off.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.offset, required this.child});

  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: offset * (1 - t),
            child: child,
          ),
        ),
        child: child,
      );
}

// ─── LOOK ───────────────────────────────────────────────────────────────────

enum _Family { gnome, plasma, aqua, tiling, tui }

/// Everything the five desktops draw differently, resolved once per build.
class _Look {
  const _Look({
    required this.family,
    required this.surface,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.fill,
    required this.line,
    required this.font,
    required this.scale,
  });

  factory _Look.of(EffectiveTheme t) {
    final p = t.palette;
    final family = switch (t.shell) {
      ShellKind.gnome => _Family.gnome,
      ShellKind.plasma => _Family.plasma,
      ShellKind.aqua => _Family.aqua,
      ShellKind.tiling => _Family.tiling,
      ShellKind.tui => _Family.tui,
    };
    final mono = family == _Family.tiling || family == _Family.tui;
    return _Look(
      family: family,
      surface: p.bar,
      text: family == _Family.tui ? p.accent : p.onDark,
      muted: (family == _Family.tui ? p.accent : p.onDark)
          .withValues(alpha: 0.66),
      accent: p.accent,
      onAccent:
          ThemeData.estimateBrightnessForColor(p.accent) == Brightness.dark
              ? Colors.white // theme-exempt: legible ink on the accent
              : const Color(0xFF111111), // theme-exempt: legible ink
      fill: p.onDark.withValues(alpha: family == _Family.aqua ? 0.16 : 0.09),
      line: p.onDark.withValues(alpha: 0.16),
      font: mono ? t.typography.mono : t.typography.display,
      scale: t.textScale,
    );
  }

  final _Family family;
  final Color surface;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;

  /// The fill an idle control sits on.
  final Color fill;

  /// Hairlines and idle outlines.
  final Color line;
  final String? font;
  final double scale;

  bool get mono => family == _Family.tiling || family == _Family.tui;

  /// Corner radius of the sheet and of the cards inside it.
  double get sheetRadius => switch (family) {
        _Family.gnome => 30,
        _Family.plasma => 18,
        _Family.aqua => 26,
        _Family.tiling => 10,
        _Family.tui => 0,
      };

  double get cardRadius => switch (family) {
        _Family.gnome => 24,
        _Family.plasma => 14,
        _Family.aqua => 26,
        _Family.tiling => 6,
        _Family.tui => 0,
      };

  /// Tiling and terminal desktops speak in lowercase.
  String say(String s) => mono ? s.toLowerCase() : s;

  TextStyle style(double size, {FontWeight? weight, Color? color}) =>
      TextStyle(
        fontFamily: font,
        fontSize: size * scale,
        fontWeight: weight,
        height: 1.25,
        color: color ?? text,
      );
}

// ─── MODEL ──────────────────────────────────────────────────────────────────

/// One quick toggle, whatever shape the desktop draws it in.
class _Toggle {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.state,
    required this.active,
    this.onTap,
    this.onMore,
  });

  final IconData icon;
  final String label;

  /// What it is set to, in a word: "Dark", "Off", the layout's name.
  final String state;
  final bool active;

  /// Null when the control cannot act here: drawn, but dimmed.
  final VoidCallback? onTap;

  /// Opens the thing behind the toggle (G VPN's app). GNOME draws it as the
  /// split arrow; the other desktops answer a long press.
  final VoidCallback? onMore;
}

/// The toggles this distro can honour, in order.
List<_Toggle> _toggles(BuildContext context, WidgetRef ref, EffectiveTheme t) {
  final prefs = ref.read(prefsProvider(t.spec.id).notifier);
  final close = ref.read(quickSettingsProvider.notifier).close;
  void tap() => HapticFeedback.selectionClick();

  // Who draws the status row. A dock with its own tray owns it the same way a
  // panel does (Deepin), so it gets the same switch, worded for the dock.
  final hasPanel = t.panels.isNotEmpty || t.dockTray;
  final statusOn = hasPanel ? !t.statusBar : t.statusBar;

  // Light, dark, auto, cycled. Dimmed on a distro with no light palette
  // rather than accepting a tap and changing nothing.
  final hasLight = t.spec.paletteLight != null;
  final mode = t.prefs.themeMode ?? 'system';
  const modes = ['light', 'dark', 'system'];

  final layouts = t.spec.layouts;
  final currentLayout = layouts.isEmpty
      ? null
      : layouts.firstWhere(
          (l) => l.id == t.prefs.layoutPreset,
          orElse: () => layouts.firstWhere(
            (l) => l.isDefault,
            orElse: () => layouts.first,
          ),
        );

  final vpn = ref.watch(gvpnStatusProvider).asData?.value;
  final vpnShown = vpn != null &&
      vpn.state != GVpnState.notInstalled &&
      vpn.state != GVpnState.unavailable;
  final vpnBusy = vpn != null &&
      (vpn.state == GVpnState.connecting ||
          vpn.state == GVpnState.reconnecting);

  return [
    _Toggle(
      icon: hasPanel ? Icons.signal_wifi_4_bar : Icons.smartphone_outlined,
      label: context.t(hasPanel ? 'qs.statusIcons' : 'settings.statusBar'),
      state: !hasPanel
          ? context.t(statusOn ? 'qs.on' : 'qs.off')
          : !statusOn
              ? context.t('qs.androidBar')
              : context.t(t.panels.isEmpty ? 'qs.onDock' : 'qs.onPanel'),
      active: statusOn,
      onTap: () {
        tap();
        prefs.edit((p) => p.copyWith(statusBar: hasPanel ? statusOn : !statusOn));
      },
    ),
    if (vpn != null && vpnShown)
      _Toggle(
        icon: Icons.vpn_key_outlined,
        label: 'G VPN',
        state: switch (vpn.state) {
          GVpnState.on => vpn.label ?? context.t('panel.vpnOn'),
          GVpnState.connecting ||
          GVpnState.reconnecting =>
            context.t('panel.vpnConnecting'),
          GVpnState.paused => context.t('panel.vpnPaused'),
          _ => context.t('qs.off'),
        },
        active: vpn.protected,
        onTap: vpnBusy
            ? null
            : () {
                tap();
                vpn.protected ? GVpn.disconnect() : GVpn.connect();
              },
        onMore: () {
          close();
          GVpn.open(referrer: 'g_launcher_panel');
        },
      ),
    _Toggle(
      icon: t.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
      label: context.t('qs.appearance'),
      state: context.t(switch (mode) {
        'light' => 'settings.light',
        'dark' => 'settings.dark',
        _ => 'settings.badges.auto',
      }),
      active: t.dark,
      onTap: hasLight
          ? () {
              tap();
              final next = modes[(modes.indexOf(mode) + 1) % modes.length];
              prefs.edit((p) => p.copyWith(themeMode: next));
            }
          : null,
    ),
    // Xfce, GNOME, KDE on Kali; Zorin's layouts on Zorin. A tap moves to the
    // next one, the same write Appearance makes (see [applyLayoutPreset]).
    if (layouts.length > 1 && currentLayout != null)
      _Toggle(
        icon: Icons.space_dashboard_outlined,
        label: context.t('qs.layout'),
        state: currentLayout.name,
        active: false,
        onTap: () {
          tap();
          final i = layouts.indexOf(currentLayout);
          final next = layouts[(i + 1) % layouts.length];
          prefs.edit((p) => applyLayoutPreset(p, next.id));
        },
      ),
  ];
}

/// Edit panel and All settings, run against the navigator rather than the
/// sheet, because closing the sheet unmounts the context that asked.
class _Actions {
  _Actions(BuildContext context, WidgetRef ref, this.theme)
      : _navigator = Navigator.of(context),
        _close = ref.read(quickSettingsProvider.notifier).close,
        _edit = ref.read(deskletEditProvider.notifier);

  final EffectiveTheme theme;
  final NavigatorState _navigator;
  final VoidCallback _close;
  final DeskletEdit _edit;

  bool get canEditPanel => theme.panelEdit && theme.panels.isNotEmpty;

  Future<void> editPanel() async {
    HapticFeedback.selectionClick();
    _close();
    _edit.enterPanel();
    await showPanelEditor(_navigator.context, theme);
    _edit.exit();
  }

  void settings() {
    HapticFeedback.selectionClick();
    _close();
    _navigator.push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(theme: theme)),
    );
  }
}

// ─── THE SHEET ──────────────────────────────────────────────────────────────

class _Sheet extends ConsumerWidget {
  const _Sheet({required this.theme, required this.look});

  final EffectiveTheme theme;
  final _Look look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toggles = _toggles(context, ref, theme);
    final actions = _Actions(context, ref, theme);
    final close = ref.read(quickSettingsProvider.notifier).close;
    final narrow = panelIsNarrow(context);

    final extras = <Widget>[
      // On an upright phone the panel drops its pager and readouts, so they
      // open here instead. Only the ones this distro put on its panel.
      if (narrow) _Workspaces(theme: theme, look: look),
      if (narrow) _Readouts(theme: theme, look: look),
      if (theme.spec.accents.isNotEmpty)
        _Swatches(theme: theme, look: look, accents: theme.spec.accents),
      _Media(look: look),
      _Notes(look: look, onLeave: close),
    ];

    final body = switch (look.family) {
      _Family.gnome => _gnome(context, ref, toggles, actions, extras),
      _Family.plasma => _plasma(context, ref, toggles, actions, extras),
      _Family.aqua => _aqua(context, ref, toggles, actions, extras),
      _Family.tiling => _tiling(context, ref, toggles, actions, extras),
      _Family.tui => _tui(context, ref, toggles, actions, extras),
    };

    return Semantics(
      container: true,
      label: context.t('gestures.quickSettings'),
      child: body,
    );
  }

  /// A frosted sheet: the distro's bar colour over a blur of the desktop.
  Widget _glass({
    required Widget child,
    required EdgeInsets padding,
    Color? border,
    double borderWidth = 1,
    List<BoxShadow>? shadow,
  }) {
    final radius = BorderRadius.circular(look.sheetRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ??
            const [
              BoxShadow(
                color: Color(0x73000000), // theme-exempt: shadow
                blurRadius: 48,
                offset: Offset(0, 18),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: look.surface.withValues(alpha: 0.88),
              borderRadius: radius,
              border:
                  Border.all(color: border ?? look.line, width: borderWidth),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _stack(List<Widget> children, {double gap = 12}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );

  // ── GNOME: battery pill, pill toggles, then the rest. ──
  Widget _gnome(BuildContext context, WidgetRef ref, List<_Toggle> toggles,
      _Actions actions, List<Widget> extras) {
    return _glass(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: _stack([
        Row(
          children: [
            _Battery(look: look),
            const Spacer(),
            _UpdateChip(look: look),
            const SizedBox(width: 8),
            if (actions.canEditPanel)
              _RoundButton(
                look: look,
                icon: Icons.edit_outlined,
                label: context.t('qs.editPanel'),
                onTap: actions.editPanel,
              ),
            const SizedBox(width: 8),
            _RoundButton(
              look: look,
              icon: Icons.settings_outlined,
              label: context.t('qs.settings'),
              onTap: actions.settings,
            ),
          ],
        ),
        _Grid(
          columns: 2,
          children: [for (final t in toggles) _PillTile(look: look, toggle: t)],
        ),
        ...extras,
      ]),
    );
  }

  // ── Plasma: a big thin clock header, then Breeze tiles. ──
  Widget _plasma(BuildContext context, WidgetRef ref, List<_Toggle> toggles,
      _Actions actions, List<Widget> extras) {
    return _glass(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  look.accent.withValues(alpha: 0.16),
                  look.accent.withValues(alpha: 0),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
              child: _ClockHeader(
                look: look,
                size: 40,
                trailing: [
                  _UpdateChip(look: look),
                  if (actions.canEditPanel)
                    _RoundButton(
                      look: look,
                      icon: Icons.edit_outlined,
                      label: context.t('qs.editPanel'),
                      onTap: actions.editPanel,
                    ),
                  _RoundButton(
                    look: look,
                    icon: Icons.settings_outlined,
                    label: context.t('qs.settings'),
                    onTap: actions.settings,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _stack([
              _Grid(
                columns: 3,
                gap: 8,
                children: [
                  for (final t in toggles) _BreezeTile(look: look, toggle: t),
                ],
              ),
              ...extras,
            ], gap: 10),
          ),
        ],
      ),
    );
  }

  // ── Aqua: a large clock on the desktop itself, then glass modules. ──
  Widget _aqua(BuildContext context, WidgetRef ref, List<_Toggle> toggles,
      _Actions actions, List<Widget> extras) {
    final appearance =
        toggles.firstWhere((t) => t.label == context.t('qs.appearance'));
    final rest = [for (final t in toggles) if (t != appearance) t];

    Widget module(Widget child, {EdgeInsets? padding}) => _Module(
          look: look,
          padding: padding ?? const EdgeInsets.all(14),
          child: child,
        );

    return _stack([
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
        child: _ClockHeader(
          look: look,
          size: 54,
          light: true,
          trailing: [
            _UpdateChip(look: look, glass: true),
            if (actions.canEditPanel)
              _RoundButton(
                look: look,
                icon: Icons.edit_outlined,
                label: context.t('qs.editPanel'),
                onTap: actions.editPanel,
                glass: true,
              ),
          ],
        ),
      ),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: module(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rest.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _CircleToggle(look: look, toggle: rest[i]),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _SquareModule(look: look, toggle: appearance)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _SquareModule(
                      look: look,
                      toggle: _Toggle(
                        icon: Icons.settings_outlined,
                        label: context.t('qs.settings'),
                        state: '',
                        active: false,
                        onTap: actions.settings,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ...extras,
    ]);
  }

  // ── Tiling: a labelled frame, a big mono clock, an outlined grid. ──
  Widget _tiling(BuildContext context, WidgetRef ref, List<_Toggle> toggles,
      _Actions actions, List<Widget> extras) {
    return _glass(
      padding: const EdgeInsets.all(14),
      border: look.accent,
      borderWidth: 2,
      shadow: [
        BoxShadow(color: look.accent.withValues(alpha: 0.12), spreadRadius: 6),
        const BoxShadow(
          color: Color(0x99000000), // theme-exempt: shadow
          blurRadius: 60,
          offset: Offset(0, 30),
        ),
      ],
      child: _stack([
        Row(
          children: [
            Flexible(
              child: Text(
                look.say(context.t('qs.title')),
                style: look.style(13, weight: FontWeight.w700, color: look.accent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: look.line)),
            const SizedBox(width: 8),
            _UpdateChip(look: look),
            const SizedBox(width: 8),
            if (actions.canEditPanel) ...[
              _RoundButton(
                look: look,
                icon: Icons.edit_outlined,
                label: context.t('qs.editPanel'),
                onTap: actions.editPanel,
              ),
              const SizedBox(width: 8),
            ],
            _RoundButton(
              look: look,
              icon: Icons.settings_outlined,
              label: context.t('qs.settings'),
              onTap: actions.settings,
            ),
          ],
        ),
        _ClockHeader(look: look, size: 52, inline: true),
        _Grid(
          columns: 3,
          gap: 8,
          children: [for (final t in toggles) _CellTile(look: look, toggle: t)],
        ),
        ...extras,
      ]),
    );
  }

  // ── Terminal: a box-drawn menu. ──
  Widget _tui(BuildContext context, WidgetRef ref, List<_Toggle> toggles,
      _Actions actions, List<Widget> extras) {
    final title = look.say(context.t('qs.title'));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: look.surface,
        border: Border.all(color: look.accent, width: 2),
        boxShadow: [
          BoxShadow(color: look.accent.withValues(alpha: 0.2), blurRadius: 24),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: _ClockHeader(look: look, size: 44, inline: true),
                ),
                for (final t in toggles) _TuiRow(look: look, toggle: t),
                _UpdateChip(look: look),
                if (actions.canEditPanel)
                  _TuiRow.action(
                    look: look,
                    label: look.say(context.t('qs.editPanel')),
                    onTap: actions.editPanel,
                  ),
                _TuiRow.action(
                  look: look,
                  label: look.say(context.t('qs.settings')),
                  onTap: actions.settings,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: look.muted,
                  ),
                ),
                ...extras,
              ],
            ),
          ),
          Positioned(
            top: -11,
            left: 14,
            child: ColoredBox(
              color: look.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(title, style: look.style(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SHARED PIECES ──────────────────────────────────────────────────────────

/// On Aqua every section is a glass module of its own; elsewhere it sits
/// straight on the sheet. Called only once a section knows it has content.
Widget _framed(_Look look, Widget child) => look.family == _Family.aqua
    ? _Module(look: look, padding: const EdgeInsets.all(4), child: child)
    : child;

/// A grid whose rows grow together, so a label that wraps in one tile lifts
/// its neighbours to match instead of leaving a ragged row.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children, this.gap = 10});

  final int columns;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[
      for (var i = 0; i < children.length; i += columns)
        children.sublist(i, (i + columns).clamp(0, children.length)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: c < rows[r].length ? rows[r][c] : const SizedBox(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A tappable surface: fill, corners, optional outline, ink on press.
class _Surface extends StatelessWidget {
  const _Surface({
    required this.color,
    required this.radius,
    required this.child,
    this.border,
    this.onTap,
    this.onLongPress,
    this.padding = EdgeInsets.zero,
  });

  final Color color;
  final double radius;
  final Widget child;
  final BorderSide? border;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ?? BorderSide.none,
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Label over state, both free to wrap.
class _Labels extends StatelessWidget {
  const _Labels({
    required this.look,
    required this.toggle,
    required this.color,
    this.size = 14,
    this.align = CrossAxisAlignment.start,
  });

  final _Look look;
  final _Toggle toggle;
  final Color color;
  final double size;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final textAlign =
        align == CrossAxisAlignment.center ? TextAlign.center : TextAlign.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Text(
          look.say(toggle.label),
          textAlign: textAlign,
          style: look.style(size, weight: FontWeight.w700, color: color),
        ),
        if (toggle.state.isNotEmpty)
          Text(
            look.say(toggle.state),
            textAlign: textAlign,
            style: look.style(size - 2, color: color.withValues(alpha: 0.75)),
          ),
      ],
    );
  }
}

Widget _semantic(_Toggle t, Widget child) => Semantics(
      button: true,
      toggled: t.active,
      enabled: t.onTap != null,
      label: '${t.label}, ${t.state}',
      excludeSemantics: true,
      child: Opacity(opacity: t.onTap == null ? 0.45 : 1, child: child),
    );

/// GNOME 46's pill, with a split arrow when the toggle has more behind it.
class _PillTile extends StatelessWidget {
  const _PillTile({required this.look, required this.toggle});

  final _Look look;
  final _Toggle toggle;

  @override
  Widget build(BuildContext context) {
    final on = toggle.active;
    final ink = on ? look.onAccent : look.text;
    return _semantic(
      toggle,
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Material(
          color: on ? look.accent : look.fill,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: InkWell(
                  onTap: toggle.onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(
                      children: [
                        Icon(toggle.icon, size: 20, color: ink),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Labels(look: look, toggle: toggle, color: ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (toggle.onMore != null) ...[
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: on
                      ? look.onAccent.withValues(alpha: 0.18)
                      : look.line,
                ),
                InkWell(
                  onTap: toggle.onMore,
                  child: SizedBox(
                    width: 44,
                    child: Icon(Icons.chevron_right, size: 20, color: ink),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A Breeze tile: icon in a rounded square above the label, accent tint and
/// edge when on.
class _BreezeTile extends StatelessWidget {
  const _BreezeTile({required this.look, required this.toggle});

  final _Look look;
  final _Toggle toggle;

  @override
  Widget build(BuildContext context) {
    final on = toggle.active;
    return _semantic(
      toggle,
      _Surface(
        color: on ? look.accent.withValues(alpha: 0.2) : look.fill,
        radius: look.cardRadius,
        border: BorderSide(color: on ? look.accent : look.line),
        onTap: toggle.onTap,
        onLongPress: toggle.onMore,
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: on ? look.accent : look.fill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  toggle.icon,
                  size: 20,
                  color: on ? look.onAccent : look.text,
                ),
              ),
              const SizedBox(height: 12),
              _Labels(look: look, toggle: toggle, color: look.text, size: 13),
            ],
          ),
        ),
      ),
    );
  }
}

/// Control Centre's round toggle with its label beside it.
class _CircleToggle extends StatelessWidget {
  const _CircleToggle({required this.look, required this.toggle});

  final _Look look;
  final _Toggle toggle;

  @override
  Widget build(BuildContext context) {
    final on = toggle.active;
    return _semantic(
      toggle,
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle.onTap,
        onLongPress: toggle.onMore,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: on ? look.accent : look.text.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(
                toggle.icon,
                size: 20,
                color: on ? look.onAccent : look.text,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Labels(look: look, toggle: toggle, color: look.text, size: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass module of its own, for one toggle, icon over label.
class _SquareModule extends StatelessWidget {
  const _SquareModule({required this.look, required this.toggle});

  final _Look look;
  final _Toggle toggle;

  @override
  Widget build(BuildContext context) {
    final on = toggle.active;
    return _semantic(
      toggle,
      _Module(
        look: look,
        onTap: toggle.onTap,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: on ? look.accent : look.text.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(
                toggle.icon,
                size: 20,
                color: on ? look.onAccent : look.text,
              ),
            ),
            const SizedBox(height: 8),
            _Labels(
              look: look,
              toggle: toggle,
              color: look.text,
              size: 12,
              align: CrossAxisAlignment.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One frosted Control Centre module.
class _Module extends StatelessWidget {
  const _Module({
    required this.look,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final _Look look;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(look.cardRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: _Surface(
          color: look.surface.withValues(alpha: 0.55),
          radius: look.cardRadius,
          border: BorderSide(color: look.line),
          onTap: onTap,
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// An outlined tiling cell that fills with the accent when on.
class _CellTile extends StatelessWidget {
  const _CellTile({required this.look, required this.toggle});

  final _Look look;
  final _Toggle toggle;

  @override
  Widget build(BuildContext context) {
    final on = toggle.active;
    return _semantic(
      toggle,
      _Surface(
        color: on ? look.accent : Colors.transparent,
        radius: look.cardRadius,
        border: BorderSide(color: on ? look.accent : look.line),
        onTap: toggle.onTap,
        onLongPress: toggle.onMore,
        padding: const EdgeInsets.all(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(toggle.icon, size: 20, color: on ? look.onAccent : look.accent),
              const SizedBox(height: 10),
              _Labels(
                look: look,
                toggle: toggle,
                color: on ? look.onAccent : look.text,
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A terminal menu row: `[x] label   state`, inverse when on.
class _TuiRow extends StatelessWidget {
  const _TuiRow({required this.look, required _Toggle this.toggle})
      : label = null,
        onTap = null;

  const _TuiRow.action({
    required this.look,
    required String this.label,
    required VoidCallback this.onTap,
  }) : toggle = null;

  final _Look look;
  final _Toggle? toggle;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = toggle;
    final on = t?.active ?? false;
    final ink = on ? look.surface : look.text;
    final row = Material(
      color: on ? look.accent : Colors.transparent,
      child: InkWell(
        onTap: t?.onTap ?? onTap,
        onLongPress: t?.onMore,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t == null ? '> ' : (on ? '[x] ' : '[ ] '),
                    style: look.style(15, color: ink)),
                Expanded(
                  child: Text(
                    look.say(t?.label ?? label!),
                    style: look.style(15, color: ink),
                  ),
                ),
                if (t != null && t.state.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      look.say(t.state),
                      textAlign: TextAlign.end,
                      style: look.style(15,
                          color: on ? ink : look.text.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return t == null ? row : _semantic(t, row);
  }
}

/// A round (or, on tiling, square) icon button with a label for readers.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.look,
    required this.icon,
    required this.label,
    required this.onTap,
    this.glass = false,
  });

  final _Look look;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final radius = switch (look.family) {
      _Family.plasma => 10.0,
      _Family.tiling || _Family.tui => 6.0,
      _ => 22.0,
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 44,
          height: 44,
          child: _Surface(
            color: look.family == _Family.tiling
                ? Colors.transparent
                : glass
                    ? look.surface.withValues(alpha: 0.5)
                    : look.fill,
            radius: radius,
            border: look.family == _Family.tiling
                ? BorderSide(color: look.line)
                : null,
            onTap: onTap,
            child: Center(child: Icon(icon, size: 19, color: look.text)),
          ),
        ),
      ),
    );
  }
}

/// The time large, the date under it, actions to the right. [inline] sets
/// the date beside the time, as the tiling and terminal desktops do.
class _ClockHeader extends ConsumerWidget {
  const _ClockHeader({
    required this.look,
    required this.size,
    this.trailing = const [],
    this.inline = false,
    this.light = false,
  });

  final _Look look;
  final double size;
  final List<Widget> trailing;
  final bool inline;

  /// Drawn straight on the desktop (Aqua): weights go thin, like the lock
  /// screen it borrows from.
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).asData?.value ?? DateTime.now();
    final time = Text(
      formatTime(now),
      style: look.style(
        size,
        weight: look.mono ? FontWeight.w700 : FontWeight.w300,
      ).copyWith(height: 1, letterSpacing: light ? -1 : 0),
    );
    final date = Text(
      look.say(formatDateLong(now)),
      style: look.style(13, color: look.muted, weight: light ? FontWeight.w500 : null),
    );

    final clock = inline
        ? Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 4,
            children: [time, date],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [time, const SizedBox(height: 4), date],
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: clock),
        for (var i = 0; i < trailing.length; i++) ...[
          const SizedBox(width: 8),
          trailing[i],
        ],
      ],
    );
  }
}

/// GNOME's battery pill, from the live stats stream. Hidden until it answers.
class _Battery extends ConsumerWidget {
  const _Battery({required this.look});

  final _Look look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(systemStatsProvider).asData?.value;
    final pct = stats?.batteryPercent;
    if (pct == null) return const SizedBox.shrink();
    final charging = stats?.batteryCharging ?? false;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: look.fill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            charging ? Icons.battery_charging_full : Icons.battery_std_outlined,
            size: 16,
            color: look.text,
          ),
          const SizedBox(width: 6),
          Text('$pct%', style: look.style(13, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The panel's workspace switcher, when an upright phone left it off the bar.
class _Workspaces extends ConsumerWidget {
  const _Workspaces({required this.theme, required this.look});

  final EffectiveTheme theme;
  final _Look look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (theme.panels.isEmpty) return const SizedBox.shrink();
    final authored =
        currentPanelItems(theme).any((i) => i.kind == PanelModule.pager);
    final count = ref.watch(workspaceCountProvider);
    if (!authored || count < 2) return const SizedBox.shrink();
    final active = ref.watch(activeWorkspaceProvider);
    final radius = look.family == _Family.gnome ? 14.0 : look.cardRadius * 0.6;

    return _framed(look, Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == active,
              label: context.t('home.workspaceN', {'n': '${i + 1}'}),
              excludeSemantics: true,
              child: SizedBox(
                height: 44,
                child: _Surface(
                  color: i == active
                      ? look.accent
                      : look.family == _Family.tiling
                          ? Colors.transparent
                          : look.fill,
                  radius: radius,
                  border: look.family == _Family.tiling && i != active
                      ? BorderSide(color: look.line)
                      : null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(activeWorkspaceProvider.notifier).goTo(i);
                    ref.read(quickSettingsProvider.notifier).close();
                  },
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: look.style(
                        14,
                        weight: FontWeight.w700,
                        color: i == active ? look.onAccent : look.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ));
  }
}

/// The panel's readouts, when an upright phone left them off the bar.
class _Readouts extends StatelessWidget {
  const _Readouts({required this.theme, required this.look});

  final EffectiveTheme theme;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    if (theme.panels.isEmpty) return const SizedBox.shrink();
    final show = [
      for (final i in currentPanelItems(theme))
        if (isStatModule(i.kind)) i.kind,
    ];
    if (show.isEmpty) return const SizedBox.shrink();

    return _framed(look, Container(
      constraints: const BoxConstraints(minHeight: 44),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: look.fill,
        borderRadius: BorderRadius.circular(look.cardRadius * 0.6),
      ),
      child: PanelReadouts(
        palette: theme.palette,
        fontFamily: look.font,
        stacked: false,
        show: show,
      ),
    ));
  }
}

/// The distro's accents. Tapping the chosen one clears back to the distro's
/// own, the same contract the Appearance row has.
class _Swatches extends ConsumerWidget {
  const _Swatches({
    required this.theme,
    required this.look,
    required this.accents,
  });

  final EffectiveTheme theme;
  final _Look look;
  final List<ThemeAccent> accents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = theme.prefs.accentId;
    final notifier = ref.read(prefsProvider(theme.spec.id).notifier);
    final round = look.family == _Family.gnome || look.family == _Family.aqua;
    final swatch = round ? 34.0 : 30.0;
    final radius = switch (look.family) {
      _Family.plasma => 6.0,
      _Family.tiling => 4.0,
      _Family.tui => 0.0,
      _ => swatch / 2,
    };

    // As many fit per row as the sheet allows, the gap stretched so every row
    // lines up on the same columns. Mint ships ten; they wrap, never squeeze.
    return _framed(look, Padding(
      padding: EdgeInsets.symmetric(
        horizontal: look.family == _Family.tui ? 12 : 6,
        vertical: 6,
      ),
      child: LayoutBuilder(builder: (context, box) {
        const minGap = 10.0;
        final perRow =
            ((box.maxWidth + minGap) / (swatch + minGap)).floor().clamp(1, 99);
        final cols = perRow.clamp(1, accents.length);
        final gap = cols > 1 ? (box.maxWidth - cols * swatch) / (cols - 1) : 0.0;
        return Wrap(
          spacing: (gap - 0.5).clamp(minGap, 999.0),
          runSpacing: minGap,
          children: [
            for (final a in accents)
              Semantics(
                button: true,
                selected: a.id == chosen,
                label: a.name,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.edit(
                      (p) => a.id == chosen
                          ? p.clearing(accentId: true)
                          : p.copyWith(accentId: a.id),
                    );
                  },
                  // 44dp target around a smaller swatch.
                  child: SizedBox(
                    width: swatch,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: swatch,
                        height: swatch,
                        decoration: BoxDecoration(
                          color: a.value,
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: a.id == chosen ? look.text : look.line,
                            width: a.id == chosen ? 3 : 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    ));
  }
}

/// Now playing: artwork, title, artist, transport. Hidden with no player.
class _Media extends ConsumerWidget {
  const _Media({required this.look});

  final _Look look;

  Future<void> _send(WidgetRef ref, NowPlaying s, String command) async {
    HapticFeedback.selectionClick();
    await ref
        .read(launcherHostApiProvider)
        .sendMediaCommand(s.packageName, command);
    // Pressing a button is the one moment the state certainly changed.
    ref.invalidate(clockPanelMediaProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(clockPanelMediaProvider).asData?.value;
    if (s == null) return const SizedBox.shrink();

    if (look.family == _Family.tui) {
      return _TuiRow.action(
        look: look,
        label: '${s.playing ? '||' : '>'} ${s.title}'
            '${s.artist.isEmpty ? '' : '  ${s.artist}'}',
        onTap: () => _send(ref, s, s.playing ? 'pause' : 'play'),
      );
    }

    final big = look.family == _Family.gnome || look.family == _Family.aqua;
    final art = Container(
      width: big ? 60 : 52,
      height: big ? 60 : 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(look.family == _Family.tiling ? 4 : 14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [look.accent, look.accent.withValues(alpha: 0.35)],
        ),
      ),
      child: Icon(Icons.music_note, color: look.onAccent, size: 24),
    );

    Widget button(IconData icon, String tip, VoidCallback? onTap,
        {bool primary = false}) {
      final fill = primary
          ? (look.family == _Family.plasma ? look.accent : look.text)
          : Colors.transparent;
      final ink = primary
          ? (look.family == _Family.plasma ? look.onAccent : look.surface)
          : look.text;
      return Semantics(
        button: true,
        enabled: onTap != null,
        label: tip,
        excludeSemantics: true,
        child: SizedBox(
          width: 44,
          height: 44,
          child: _Surface(
            color: fill,
            radius: look.family == _Family.tiling ? 4 : 22,
            onTap: onTap,
            child: Center(
              child: Icon(
                icon,
                size: 22,
                color: onTap == null ? look.muted : ink,
              ),
            ),
          ),
        ),
      );
    }

    final transport = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          Icons.skip_previous,
          context.t('panel.mediaPrevious'),
          s.canSkipPrevious ? () => _send(ref, s, 'previous') : null,
        ),
        const SizedBox(width: 4),
        button(
          s.playing ? Icons.pause : Icons.play_arrow,
          context.t(s.playing ? 'panel.mediaPause' : 'panel.mediaPlay'),
          () => _send(ref, s, s.playing ? 'pause' : 'play'),
          primary: true,
        ),
        const SizedBox(width: 4),
        button(
          Icons.skip_next,
          context.t('panel.mediaNext'),
          s.canSkipNext ? () => _send(ref, s, 'next') : null,
        ),
      ],
    );

    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(look.say(s.title), style: look.style(15, weight: FontWeight.w700)),
        if (s.artist.isNotEmpty)
          Text(look.say(s.artist), style: look.style(12, color: look.muted)),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [art, const SizedBox(width: 12), Expanded(child: titles)]),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: transport),
        ],
      ),
    );

    return switch (look.family) {
      // Aqua's module already draws the glass around it.
      _Family.aqua => _framed(look, content),
      _Family.tiling => DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: look.line),
            borderRadius: BorderRadius.circular(look.cardRadius),
          ),
          child: content,
        ),
      _ => DecoratedBox(
          decoration: BoxDecoration(
            color: look.fill,
            borderRadius: BorderRadius.circular(look.cardRadius),
            border: look.family == _Family.plasma
                ? Border.all(color: look.line)
                : null,
          ),
          child: content,
        ),
    };
  }
}

/// Notifications as one row: a bell, a count, the top apps with badges.
/// Counts only, never content; the shade is one tap away.
class _Notes extends ConsumerWidget {
  const _Notes({required this.look, required this.onLeave});

  final _Look look;
  final VoidCallback onLeave;

  static const _icons = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(notificationAccessProvider).asData?.value;
    if (access == null) return const SizedBox.shrink();

    final rows = access ? notificationCounts(ref) : const <(AppEntry, int)>[];
    final total = rows.fold<int>(0, (sum, r) => sum + r.$2);
    final label = !access
        ? context.t('panel.countsOff')
        : total == 0
            ? context.t('panel.noNotifications')
            : context.t('panel.notifications');

    void open() {
      HapticFeedback.selectionClick();
      if (!access) {
        onLeave();
        openNotificationAccessSettings();
      } else {
        openNotificationShade(context, ref, onLeave);
      }
    }

    if (look.family == _Family.tui) {
      return _TuiRow.action(
        look: look,
        label: total == 0
            ? look.say(label)
            : '${look.say(label)}  ${context.t('qs.newCount', {'n': '$total'})}',
        onTap: open,
      );
    }

    final badges = [
      for (final (app, n) in rows.take(_icons))
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AppIcon(entry: app, size: 28, showBadge: false),
              Positioned(
                top: -6,
                right: -7,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: look.accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    n > 99 ? '99+' : '$n',
                    style: look.style(10,
                        weight: FontWeight.w700, color: look.onAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];

    final tile = look.family == _Family.aqua
        ? Colors.transparent
        : look.family == _Family.tiling
            ? Colors.transparent
            : look.fill;

    return _framed(look, Semantics(
      button: true,
      label: total == 0
          ? label
          : '$label, ${context.t('qs.newCount', {'n': '$total'})}',
      excludeSemantics: true,
      child: _Surface(
        color: tile,
        radius: look.cardRadius,
        border: look.family == _Family.tiling || look.family == _Family.plasma
            ? BorderSide(color: look.line)
            : null,
        onTap: open,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Icon(
                access
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                size: 20,
                color: look.text,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  look.say(label),
                  style: look.style(14, weight: FontWeight.w600),
                ),
              ),
              ...badges,
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: look.muted),
            ],
          ),
        ),
      ),
    ));
  }
}

/// The Play update, in the sheet's header, only while there is one.
///
/// The desktop and its bars never carry it (see `update_dot.dart`): this sheet
/// is a menu someone opened, which is the one kind of surface allowed to.
/// Found: an arrow, tap to download. Downloading: a turning ring, no tap.
/// Ready: filled with the accent, tap for the restart sheet. Drawn in each
/// desktop's own control shape, and as a menu row on the terminal.
class _UpdateChip extends ConsumerWidget {
  const _UpdateChip({required this.look, this.glass = false});

  final _Look look;

  /// Over the desktop rather than on the sheet (Aqua's header).
  final bool glass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    if (!update.hasUpdate) return const SizedBox.shrink();

    final notifier = ref.read(appUpdateProvider.notifier);
    final ready = update.status == UpdateStatus.readyToInstall;
    final busy = update.status == UpdateStatus.downloading;
    final label = look.say(context.t(ready
        ? 'settings.update.restart'
        : busy
            ? 'qs.updating'
            : 'qs.update'));

    void restart() {
      // The sheet closes first, so the restart sheet is asked from the
      // navigator rather than from a context that is about to unmount.
      final navigator = Navigator.of(context);
      ref.read(quickSettingsProvider.notifier).close();
      confirmUpdateRestart(navigator.context, notifier);
    }

    void download() {
      HapticFeedback.selectionClick();
      notifier.startDownload();
    }

    final VoidCallback? onTap = busy ? null : (ready ? restart : download);

    if (look.family == _Family.tui) {
      return _TuiRow.action(
        look: look,
        label: busy ? '[..] $label' : label,
        onTap: onTap ?? () {},
      );
    }

    final radius = switch (look.family) {
      _Family.plasma => 6.0,
      _Family.tiling => 4.0,
      _ => 20.0,
    };
    final fill = ready
        ? look.accent
        : busy
            ? look.fill
            : (glass
                ? look.surface.withValues(alpha: 0.5)
                : look.accent.withValues(alpha: 0.16));
    final border = ready
        ? BorderSide.none
        : BorderSide(color: busy ? look.line : look.accent);
    final ink = ready ? look.onAccent : look.text;

    final lead = busy
        ? SizedBox(
            width: 18,
            height: 18,
            // Indeterminate on purpose: Play reports no byte counts here.
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: look.accent,
              backgroundColor: look.line,
            ),
          )
        : Icon(
            ready ? Icons.restart_alt : Icons.arrow_downward,
            size: 18,
            color: ready ? look.onAccent : look.accent,
          );

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  lead,
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: look.style(13, weight: FontWeight.w700, color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
