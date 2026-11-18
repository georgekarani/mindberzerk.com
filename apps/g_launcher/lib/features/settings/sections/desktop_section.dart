/// Desktop: the dock, the bar, the grid and the workspaces.
///
/// A section builder. See `appearance_section.dart` for why these are functions
/// returning widget lists rather than pages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/features/settings/settings_sheets.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../../data/prefs/prefs_repository.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../design/device_preview.dart';
import '../../../design/setting_previews.dart';
import '../../../engine/capabilities.dart';
import '../../../engine/effective_theme.dart';
import '../../../engine/theme_spec.dart'
    show DockSide, PanelModule, ShellKind, TopBarSide;
import '../../dock/dock_animations.dart';
import '../../home/workspaces/workspace_controller.dart';
import '../../panel/modules/panel_cosmic_modules.dart' show setTiledHome;
import '../../panel/panel_edit.dart';
import '../../panel/panel_module_names.dart';
import '../../panel/panel_editor_sheet.dart';
import '../../panel/panel_modules.dart' show statusModules;
import '../settings_rows.dart';

/// `FilterRow` keywords and their order are byte-identical to what shipped;
/// only where they are mounted changed.
List<Widget> desktopSection(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
  int workspaces,
  String q,
) {
  // Derived here rather than passed, so the signature never has to name the
  // Pigeon host API type, which this file does not import.
  final notifier = ref.read(prefsProvider(theme.spec.id).notifier);
  ref.read(launcherHostApiProvider);

  // "Top bar" on the top edge, "Panel" on any other. See the Top bar group.
  final panelWord =
      theme.panelSide == TopBarSide.top ? 'settings.topBar' : 'settings.panel';

  // A section page folds Motion and Modules into one row each; search and
  // the legacy page keep every row flat.
  final look = SettingsLookScope.of(context);
  final drillIn = look != null && q.isEmpty;
  final moduleRows = _moduleRows(context, ref, theme);

  return [
    SettingPreview(
      query: q,
      caption: context.t('settings.dockBarAndDrawer'),
      child: LayoutPreview(theme: theme),
    ),

    // ── Dock ───────────────────────────────────────────────────────
    //
    // Groups follow the distro's own settings: what sits on the screen edge,
    // the bar along the top or bottom, then the desktop itself. Rows a
    // distro cannot do are hidden on a section page, so a dockless distro
    // shows no Dock group at all.
    SettingsGroup(
      key: const ValueKey('desk.dock'),
      label: context.t('setup.step.dock'),
      query: q,
      rows: [
        // ── THE PICTURE IS THE CONTROL ─────────────────────────────
        //
        // A three-word segmented control told you "Left", "Bottom" or "Off"
        // and left you to imagine the desktop each produces. Dock side is the
        // single most visible thing on this page and the one people switch
        // back and forth on, so it is the row that pays most for being shown
        // rather than named.
        //
        // Unframed previews inside the tiles: the tile already has a border,
        // and a phone drawn inside a phone is a picture of the thing instead
        // of the thing.
        FilterRow(
          const ['dock', 'position', 'left', 'bottom', 'off', 'side'],
          PreviewChoice<String>(
            title: context.t('settings.dockPosition'),
            // ── AND WHETHER THIS DESKTOP HAS ONE TO POSITION ───────────
            //
            // Four tiles, live, on a tiling WM that draws no dock and on the
            // terminal that draws nothing. Aqua answers differently again: it
            // HAS a dock and refuses to move it, which is a different sentence
            // and gets its own reason. See [ThemeCapabilities.canPositionDock].
            enabled: theme.canPositionDock.available,
            subtitle: theme.canPositionDock.available
                ? null
                : context.t(theme.canPositionDock.why!),
            // theme.dock is already the effective value (pref or default).
            value: theme.dock.name,
            onSelect: (v) => notifier.edit((p) => p.copyWith(dockSide: v)),
            // ── AND THE WAY BACK TO THE DISTRO ────────────────────────
            //
            // Every tile here writes a pref, so the first tap pinned the dock
            // on EVERY distro forever. Mint authors `dock: "off"` and showed
            // one anyway, and so would Arch, EndeavourOS, Pop and Zorin: five
            // dockless distros wearing a dock because of one tap on a sixth.
            //
            // `dockOpacity` two rows down has had this pair since it shipped.
            following: theme.prefs.dockSide == null,
            onFollow: () => notifier.edit((p) => p.clearing(dockSide: true)),
            options: [
              // FOUR TILES IN ONE ROW, not a wrap to 2x2. At 360dp that is
              // about 75dp each, which is a legible phone at the 10:15 the
              // chooser draws them; a second row would put "Off" on a line of
              // its own and read as a different question.
              for (final o in [
                ('left', tr('settings.left')),
                ('bottom', tr('settings.bottom')),
                ('right', tr('shell.edgeRight')),
                ('off', tr('settings.backup.off')),
              ])
                // Only the sides this distro can draw: see
                // `ThemeCapabilities.dockPositions`.
                if (theme.dockPositions.any((side) => side.name == o.$1))
                  PreviewOption(
                    value: o.$1,
                    label: o.$2,
                    child: DevicePreview(
                      palette: theme.palette,
                      mode: DevicePreviewMode.desktop,
                      dock: switch (o.$1) {
                        'bottom' => DockSide.bottom,
                        'off' => DockSide.off,
                        'right' => DockSide.right,
                        _ => DockSide.left,
                      },
                      gridButton: theme.prefs.dockGridButton ?? 'end',
                      framed: false,
                    ),
                  ),
            ],
          ),
        ),
        // ── PHASE L5: BAR OR LIST ──────────────────────────────────────
        //
        // Directly under position, because it is the same question one level
        // down: position says which edge, this says what sits on it. Above
        // opacity, which is about the surface rather than its contents.
        //
        // Greyed rather than hidden on the four shells that refuse it, and the
        // reasons differ: Aqua HAS a dock and a labelled column is not a thing
        // macOS does, Plasma keeps its launchers on the panel, and the other
        // two draw no dock at all. `canListDock` says which.
        //
        // Literals, like the L1 and L3 rows: `DrawerTransition.copy` sets the
        // precedent and the sweep picks all of them up together.
        FilterRow(
          const ['dock', 'list', 'names', 'labels', 'favourites', 'pinned'],
          SettingsRow(
            icon: Icons.view_list_outlined,
            title: context.t('settings.dockLayout'),
            subtitle: theme.canListDock.available
                ? tr('settings.iconsOnABar')
                : context.t(theme.canListDock.why!),
            subtitleTint: theme.canListDock.available
                ? null
                : SettingsSkin.of(context).warn,
            trailing: Seg(
              enabled: theme.canListDock.available,
              value: theme.dockLayout,
              // No `following` pair. No distro authors this: see
              // `LauncherPrefs.dockLayout` for why it stops at the user.
              options: {'bar': tr('settings.bar'), 'list': tr('settings.list')},
              onChanged: (v) => notifier.edit((p) => p.copyWith(dockLayout: v)),
            ),
          ),
        ),

        // Beside the dock's position, because it is the dock's own look. The
        // main slider under Surfaces still governs it until this is moved.
        FilterRow(
          const ['opacity', 'dock', 'transparency', 'panel'],
          OpacityRow(
            label: context.t('settings.dockOpacity'),
            // A dash that lives in the overview has no surface on the desktop
            // to fade, and a `dock: off` distro has none at all. Separate from
            // `canPositionDock` because aqua answers the two differently: it
            // has a dock and refuses to MOVE it.
            enabled: theme.canFadeDock.available,
            sub: theme.canFadeDock.available
                ? context.t('settings.dockOpacitySub')
                : context.t(theme.canFadeDock.why!),
            value: theme.dockOpacity,
            following: theme.prefs.dockOpacity == null,
            onChanged: (v) => notifier.edit((p) => p.copyWith(dockOpacity: v)),
            onFollow: () => notifier.edit((p) => p.clearing(dockOpacity: true)),
          ),
        ),
        // ─── MOTION: ONE ROW ON A SECTION PAGE ───────────────────────
        //
        // Three animation rows read as three settings about the same
        // thing. On a section page they fold into one row that opens them
        // together; search and the legacy page still list them flat so
        // each stays findable by name.
        if (drillIn && theme.dock != DockSide.off)
          FilterRow(
            const ['motion', 'animation', 'hover', 'press', 'entrance'],
            SettingsRow(
              icon: Icons.animation,
              title: context.t('settings.motion'),
              subtitle: context.t(
                dockAnimationFor(dockHoverModes, theme.dockHover)
                    .labelKey('dockHover'),
              ),
              keepSubtitle: true,
              trailing: const Chevron(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsSubPage(
                    title: context.t('settings.motion'),
                    look: look,
                    builder: (context, ref, theme) => [
                      SettingsGroup(
                        label: context.t('setup.step.dock'),
                        rows: _motionRows(context, ref, theme),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          ..._motionRows(context, ref, theme),
        // Shown only where a dock actually draws the button. Anywhere else it
        // was a control that changed nothing, which reviewers noticed.
        if (theme.hasActivitiesButton.available)
        FilterRow(
          const ['activities', 'grid button', 'app button', 'dock'],
          SettingsRow(
            icon: Icons.apps_outlined,
            accent: true,
            title: context.t('settings.activitiesButton'),
            trailing: Seg(
              enabled: true,
              value: theme.prefs.dockGridButton ?? 'end', // Ubuntu default
              options: {
                'start': tr('settings.start'),
                'end': tr('settings.end'),
                'off': tr('settings.backup.off'),
              },
              onChanged: (v) =>
                  notifier.edit((p) => p.copyWith(dockGridButton: v)),
            ),
          ),
        ),
      ],
    ),

    // ── Motion ─────────────────────────────────────────────────────
    //
    // How apps open gets a group of its own, not a place among the dock's
    // motions: every distro launches apps, including the ones with no dock,
    // which show no Dock group at all. PHASE 6.
    SettingsGroup(
      key: const ValueKey('desk.motion'),
      label: context.t('settings.motion'),
      query: q,
      rows: [
        _launchRow(context, ref, theme),
        // Panned by the pager; see wallpaper_pan.dart for the phones where
        // it correctly does nothing. PHASE 8.
        FilterRow(
          const ['wallpaper', 'parallax', 'pages', 'scroll', 'motion'],
          SettingsToggleRow(
            icon: Icons.panorama_horizontal_outlined,
            title: context.t('settings.wallpaperFollowsPages'),
            value: theme.wallpaperFollowsPages,
            onChanged: (v) => ref
                .read(prefsProvider(theme.spec.id).notifier)
                .edit((p) => p.copyWith(wallpaperFollowsPages: v)),
          ),
        ),
      ],
    ),

    // ── Top bar or panel ───────────────────────────────────────────
    //
    // "Top bar" only when it is on top: Mint, Zorin and Kali put their
    // panel along the bottom, and the word follows the resolved edge.
    SettingsGroup(
      key: const ValueKey('desk.panel'),
      label: context.t(panelWord),
      query: q,
      rows: [
        FilterRow(
          const ['top bar', 'status bar', 'gnome bar'],
          SettingsToggleRow(
            icon: Icons.web_asset_outlined,
            accent: true,
            title: context.t(panelWord),
            // NOT gated on hasTopBar: this switch is what CREATES one, so
            // greying it where there is none would be the row disabling
            // itself. The rows that consume a bar are the ones that follow it.
            value: theme.topBar,
            onChanged: (v) => notifier.edit((p) => p.copyWith(topBar: v)),
          ),
        ),
        // ─── THE OTHER BAR, DIRECTLY UNDER THE FIRST ─────────────────
        //
        // Two bars share one row of pixels on this phone, and until this row
        // existed only one of them was ours to decide. Putting it anywhere
        // else on the page asks the same question twice in two places.
        //
        // NOT gated on a capability, for the reason the switch above is not:
        // a bar the system owns is not something a theme can lack. What the
        // theme supplies is the default, which is what the subtitle names.
        FilterRow(
          const [
            'status bar',
            'system bar',
            'android bar',
            'fullscreen',
            'immersive',
            'notch',
            'clock',
            'battery icon',
          ],
          // ─── ON A DISTRO WITH A PANEL, THE QUESTION IS WHO OWNS THE ROW ───
          //
          // Asked the panel's way round: "status icons on the panel". On puts
          // Wi-Fi, sound, battery and the clock on the panel and hides
          // Android's status bar in the same write, because both at once is
          // the same row twice. Off, the default, leaves the row to Android and
          // the panel keeps one quick-settings button. It is the same stored
          // `statusBar` pref, inverted, so nothing migrates.
          //
          // A distro with no panel keeps the plain status bar switch: there is
          // nothing to hand the row to, and its own top row is the theme's.
          // A dock with its own tray (Deepin) owns the row like a panel.
          theme.panels.isEmpty && !theme.dockTray
              ? SettingsToggleRow(
                  icon: Icons.smartphone_outlined,
                  accent: true,
                  title: context.t('settings.statusBar'),
                  subtitle: theme.spec.layout.statusBar
                      ? context.t('settings.statusBarShownSub')
                      : context.t('settings.statusBarHiddenSub', {
                          'name': theme.spec.name,
                        }),
                  value: theme.statusBar,
                  onChanged: (v) =>
                      notifier.edit((p) => p.copyWith(statusBar: v)),
                )
              : SettingsToggleRow(
                  icon: Icons.signal_wifi_4_bar,
                  accent: true,
                  title: context.t(theme.panels.isEmpty
                      ? 'settings.dockStatusIcons'
                      : 'settings.panelStatusIcons'),
                  subtitle: context.t('settings.panelStatusIconsSub'),
                  value: !theme.statusBar,
                  onChanged: (v) =>
                      notifier.edit((p) => p.copyWith(statusBar: !v)),
                ),
        ),
        // ─── THE PANEL HAD NO ENTRY POINT AT ALL ───────────────────
        //
        // The editor opened from a long press on the panel and nowhere else,
        // which is a gesture nobody is told about on a surface most people
        // will not think to hold. Every other part of the desktop is reachable
        // from this page, and a user who moved the panel to an edge they did
        // not want then had to find the hold to get it back.
        //
        // The row OPENS the editor rather than restating it. Modules, order,
        // edge and thickness are four controls that already live together in
        // one place, and splitting them across a settings page would be two
        // ways to say the same thing that could disagree.
        if (theme.panelEdit && theme.panels.isNotEmpty)
          FilterRow(
            const ['panel', 'taskbar', 'bar', 'modules', 'tray', 'edge'],
            SettingsRow(
              icon: Icons.space_dashboard_outlined,
              accent: true,
              title: context.t('settings.panel'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => showPanelEditor(context, theme),
            ),
          ),
        // ─── MODULES: ONE ROW ON A SECTION PAGE ──────────────────────
        //
        // One switch per authored module grew the group by up to four
        // rows. They now sit one level down, behind a single row.
        if (drillIn && moduleRows.isNotEmpty)
          FilterRow(
            const ['modules', 'clock', 'wifi', 'battery', 'sound'],
            SettingsRow(
              icon: Icons.widgets_outlined,
              title: context.t('settings.modules'),
              trailing: const Chevron(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsSubPage(
                    title: context.t('settings.modules'),
                    look: look,
                    builder: (context, ref, theme) => [
                      SettingsGroup(
                        label: context.t(
                          theme.panelSide == TopBarSide.top
                              ? 'settings.topBar'
                              : 'settings.panel',
                        ),
                        rows: _moduleRows(context, ref, theme),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          ...moduleRows,
        // Directly under the switch that turns the bar on, which is where
        // someone deciding how the bar should look already is.
        FilterRow(
          const ['opacity', 'bar', 'panel', 'transparency', 'top'],
          OpacityRow(
            label: context.t('settings.barOpacity'),
            // A slider that moves and changes nothing, on every distro without
            // a bar. `hasTopBar` asks `panels` rather than the shell, so a
            // distro that turns its bar off greys this by saying one thing.
            enabled: theme.hasTopBar.available,
            sub: theme.hasTopBar.available
                ? context.t('settings.barOpacitySub')
                : context.t(theme.hasTopBar.why!),
            subWhenInert: true,
            value: theme.barOpacity,
            following: theme.prefs.barOpacity == null,
            onChanged: (v) => notifier.edit((p) => p.copyWith(barOpacity: v)),
            onFollow: () => notifier.edit((p) => p.clearing(barOpacity: true)),
          ),
        ),
      ],
    ),

    // ── Desktop ────────────────────────────────────────────────────
    SettingsGroup(
      key: const ValueKey('desk.desktop'),
      label: context.t('setup.step.distro'),
      query: q,
      rows: [
        // ── DESKTOP ICONS ──────────────────────────────────────────
        //
        // DIMMED AND INERT ON A DISTRO WITH NO GRID, which is the rule
        // `SettingsToggleRow.enabled` already states: a setting that applies
        // only elsewhere is greyed with the reason in its subtitle rather than
        // hidden, because hiding it makes someone who has read about the
        // feature conclude this build does not have it.
        //
        // The override is one-way and `LayoutResolver` enforces it, so this
        // switch can only ever turn icons OFF. A Ubuntu user cannot turn them
        // on, because a bare desktop is what GNOME IS rather than a setting
        // somebody forgot to expose. The subtitle says exactly that: it
        // describes the distro instead of withholding a feature.
        FilterRow(
          const [
            'desktop icons',
            'icons on desktop',
            'folder view',
            'apps on home',
          ],
          SettingsToggleRow(
            icon: Icons.apps_outlined,
            accent: true,
            title: context.t('settings.desktopIcons'),
            subtitle: theme.spec.layout.desktopIcons
                ? context.t('settings.appsOnTheWorkspace')
                : context.t('settings.bareDesktop', {'name': theme.spec.name}),
            value: theme.desktopIcons,
            enabled: theme.spec.layout.desktopIcons,
            onChanged: (v) => notifier.edit((p) => p.copyWith(desktopIcons: v)),
          ),
        ),
        // ─── TILED OR A GRID, THE PANEL TOGGLE'S OTHER HALF ──────────
        //
        // The same write as COSMIC's tiling toggle on the panel, so a distro
        // without that module still offers the choice. Only while there are
        // icons on the desktop: with none, there is nothing to tile.
        if (theme.desktopIcons)
          FilterRow(
            const ['tiled', 'tiling', 'tiles', 'auto tile', 'grid'],
            SettingsToggleRow(
              icon: Icons.space_dashboard_outlined,
              title: context.t('settings.tiledHome'),
              value: theme.homeLayout == 'tiled',
              onChanged: (v) => setTiledHome(ref, theme, tiled: v),
            ),
          ),
        FilterRow(
          // Relabeled from "Home grid". The authentic-desktop decision
          // removed home-screen app icons everywhere, so "Home grid"
          // implied an icon grid that did not exist. They are back on the
          // distros that authentically have one, and this grid now shapes
          // BOTH: it is the placement grid for icons where a distro carries
          // them, and the desklet grid everywhere. This rows × columns is the
          // desktop's placement grid — where widgets / conky tiles snap
          // once WidgetHost lands. The old "home grid" search term is kept
          // so anyone looking for the previous name still finds this.
          const [
            'desktop grid',
            'home grid',
            'rows',
            'columns',
            'grid size',
            'widgets',
          ],
          SettingsRow(
            icon: Icons.grid_view_outlined,
            accent: true,
            title: context.t('settings.desktopGrid'),
            // Follows the icons. Shaping a grid nothing draws is arithmetic
            // with no picture at the end of it.
            subtitle: theme.hasDesktopGrid.available
                ? context.t('settings.rowsColumns')
                : context.t(
                    theme.hasDesktopGrid.why!,
                    {'name': theme.spec.name},
                  ),
            trailing: ChipValue(
              label: '${theme.rows} × ${theme.cols}',
              preview: DevicePreview(
                palette: theme.palette,
                mode: DevicePreviewMode.desktop,
                dock: theme.dock,
                gridButton: theme.prefs.dockGridButton ?? 'end',
              ),
            ),
            onTap: theme.hasDesktopGrid.available
                ? () => showGridSheet(context, notifier, theme)
                : null,
          ),
        ),
        FilterRow(
          const ['workspaces', 'pages', 'desktops', 'swipe'],
          SettingsRow(
            icon: Icons.dashboard_customize_outlined,
            accent: true,
            title: context.t('settings.workspaces'),
            subtitle: theme.hasWorkspaces.available
                ? context.t('settings.verticalDesktopsYouSwipe')
                : context.t(theme.hasWorkspaces.why!),
            trailing: ValueLabel('$workspaces'),
            onTap: !theme.hasWorkspaces.available
                ? null
                : () => showStepperSheet(
                      context,
                      title: context.t('settings.workspaces'),
                      value: workspaces,
                      min: WorkspaceCount.min,
                      max: WorkspaceCount.max,
                      onChanged: (v) =>
                          ref.read(workspaceCountProvider.notifier).set(v),
                    ),
          ),
        ),
        // ─── ONE PAGE INDICATOR SWITCH, EVERY DISTRO (PHASE 9) ────────────
        //
        // GNOME draws dots beside its desktop; every paged app grid draws dots
        // under its pages. One switch for both, so a person who wants no dots
        // asks once. A drawer's "+" stays: it grows the drawer, it does not
        // indicate anything.
        if (theme.shell != ShellKind.tui)
          FilterRow(
            const [
              'workspace indicator',
              'page indicator',
              'dots',
              'page dots',
              'workspaces',
            ],
            SettingsToggleRow(
              icon: Icons.more_vert,
              title: context.t('settings.pageIndicator'),
              value: theme.workspaceDots,
              onChanged: (v) =>
                  notifier.edit((p) => p.copyWith(workspaceDots: v)),
            ),
          ),
        // ─── ONE LOCK FOR EVERY DISTRO ───────────────────────────────────
        //
        // Global, like the hidden set, so it reads the same on every desktop.
        // See layout_lock.dart for what it holds still and what it leaves.
        FilterRow(
          const ['lock', 'lock layout', 'lock home', 'freeze', 'arrange'],
          SettingsToggleRow(
            icon: (theme.prefs.layoutLocked ?? false)
                ? Icons.lock_outline
                : Icons.lock_open_outlined,
            accent: true,
            title: context.t('settings.lockLayout'),
            subtitle: context.t('settings.lockLayoutSub'),
            value: theme.prefs.layoutLocked ?? false,
            onChanged: (v) =>
                notifier.edit((p) => p.copyWith(layoutLocked: v)),
          ),
        ),
      ],
    ),
  ];
}

/// How apps open from this distro. PHASE 6.
FilterRow _launchRow(BuildContext context, WidgetRef ref, EffectiveTheme theme) {
  final notifier = ref.read(prefsProvider(theme.spec.id).notifier);
  return _animationRow(
    context: context,
    ref: ref,
    theme: theme,
    axis: 'launchAnimation',
    icon: Icons.open_in_new,
    modes: launchAnimationModes,
    value: theme.launchAnimation,
    terms: const ['launch', 'open', 'app', 'animation', 'zoom', 'motion'],
    write: (v) => notifier.edit((p) => p.copyWith(launchAnimation: v)),
    follow: theme.prefs.launchAnimation == null,
    clear: () => notifier.edit((p) => p.clearing(launchAnimation: true)),
  );
}

/// The three dock-animation rows, flat on the legacy page and in search,
/// one level down behind Motion on a section page.
List<FilterRow> _motionRows(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
) {
  final notifier = ref.read(prefsProvider(theme.spec.id).notifier);
  return [
    _animationRow(
      context: context,
      ref: ref,
      theme: theme,
      axis: 'dockHover',
      icon: Icons.touch_app_outlined,
      modes: dockHoverModes,
      value: theme.dockHover,
      terms: const ['dock', 'hover', 'magnify', 'animation', 'motion'],
      write: (v) => notifier.edit((p) => p.copyWith(dockHover: v)),
      follow: theme.prefs.dockHover == null,
      clear: () => notifier.edit((p) => p.clearing(dockHover: true)),
    ),
    _animationRow(
      context: context,
      ref: ref,
      theme: theme,
      axis: 'dockPress',
      icon: Icons.ads_click,
      modes: dockPressModes,
      value: theme.dockPress,
      terms: const ['dock', 'press', 'tap', 'bounce', 'animation'],
      write: (v) => notifier.edit((p) => p.copyWith(dockPress: v)),
      follow: theme.prefs.dockPress == null,
      clear: () => notifier.edit((p) => p.clearing(dockPress: true)),
    ),
    _animationRow(
      context: context,
      ref: ref,
      theme: theme,
      axis: 'dockEntrance',
      icon: Icons.animation,
      modes: dockEntranceModes,
      value: theme.dockEntrance,
      terms: const ['dock', 'entrance', 'appear', 'slide', 'animation'],
      write: (v) => notifier.edit((p) => p.copyWith(dockEntrance: v)),
      follow: theme.prefs.dockEntrance == null,
      clear: () => notifier.edit((p) => p.clearing(dockEntrance: true)),
    ),

  ];
}

/// The per-module switches for modules the distro authored on its panel.
List<FilterRow> _moduleRows(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
) {
  return [
    for (final m in silenceableModules)
      if (theme.panels.isNotEmpty &&
          _authoredOnPanel(theme, m) &&
          (!theme.statusBar || !statusModules.contains(m)))
        FilterRow(
          ['top bar', panelModuleLabel(context, m).toLowerCase()],
          SettingsToggleRow(
            icon: panelModuleIcon(m),
            title: panelModuleLabel(context, m),
            subtitle:
                theme.statusBar ? context.t('settings.alsoInStatusBar') : null,
            value: currentPanelItems(theme).any((e) => e.kind == m),
            onChanged: (v) => setPanelModuleEnabled(ref, theme, m, enabled: v),
          ),
        ),
  ];
}

/// One dock-animation row: the current mode's name, and a sheet to change it.
///
/// ─── A FUNCTION, BECAUSE THREE ROWS DIFFER ONLY IN THEIR LIST ──────────────
///
/// Written out three times this would be sixty lines saying the same thing
/// three ways, and the third would be the one that forgot the Follow arm. The
/// axis name is the only thing that varies structurally, and it is also the
/// i18n key prefix, so it does both jobs.
FilterRow _animationRow({
  required BuildContext context,
  required WidgetRef ref,
  required EffectiveTheme theme,
  required String axis,
  required IconData icon,
  required List<DockAnimation> modes,
  required String value,
  required List<String> terms,
  required void Function(String) write,
  required bool follow,
  required VoidCallback clear,
}) {
  final current = dockAnimationFor(modes, value);

  return FilterRow(
    terms,
    SettingsRow(
      icon: icon,
      accent: true,
      title: context.t('settings.$axis'),
      // The mode's NAME as the subtitle, not its description. The row has to
      // answer "what is this set to" at a glance; the description belongs in
      // the sheet, beside the alternatives it is being compared with.
      subtitle: context.t(current.labelKey(axis)),
      keepSubtitle: true,
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: follow ? null : theme.palette.accent,
      ),
      onTap: () => settingsSheet<void>(
        context,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            settingsSheetHead(context, context.t('settings.$axis')),
            for (final m in modes)
              SheetOption(
                icon: m.icon,
                label: context.t(m.labelKey(axis)),
                description: context.t(m.hintKey(axis)),
                selected: m.id == value,
                onTap: () {
                  Navigator.pop(context);
                  write(m.id);
                },
              ),
            // Back to the distro's own choice. Same affordance every other
            // themed setting carries, and the only way back once a user has
            // picked: without it the pref is set forever and a pack update that
            // changes its default is silently ignored.
            if (!follow)
              SheetOption(
                icon: Icons.settings_backup_restore,
                label: context.t('settings.followTheDistro'),
                onTap: () {
                  Navigator.pop(context);
                  clear();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
        scrollControlled: true,
      ),
    ),
  );
}

/// Did the DISTRO author this module on the panel we are editing?
///
/// Read off the pack rather than off the live panel, so a switch the user has
/// just turned off does not vanish along with the module and strand them with
/// no way to turn it back on.
bool _authoredOnPanel(EffectiveTheme theme, PanelModule kind) {
  for (final p in theme.spec.layout.panels) {
    if (p.side != theme.panelSide) continue;
    if (p.items.any((e) => e.kind == kind)) return true;
  }
  return false;
}
