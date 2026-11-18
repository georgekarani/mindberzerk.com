import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/desklet_layout.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../design/components/components.dart';
import '../../engine/effective_theme.dart';
import '../../platform/launcher_api.g.dart' as api;
import 'desklet_edit.dart';
import 'desklet_picker.dart';
import 'desklet_settings.dart';
import 'widget_stage.dart';
import 'layout_lock.dart';

/// What a held desklet offers.
///
/// ─── WHY A SHEET AND NOT STRAIGHT INTO EDIT MODE ────────────────────────────
///
/// Holding a tile used to call `edit.enter()` and `edit.select(id)` directly,
/// which put the desktop into edit mode instantly. That had two costs.
///
/// It made the desktop LIVE at the exact moment the user was deciding what to
/// do: everything on screen became draggable, so a thumb that drifted while
/// reading moved a widget. A menu should freeze the thing it is a menu about,
/// which is what a modal barrier does for free.
///
/// ─── ANCHORED, NOT A BOTTOM SHEET ───────────────────────────────────────────
///
/// This started as a `ThemedSheet`, which is what every other menu in the app
/// is, and it was the wrong primitive. A bottom sheet is for something about
/// the SCREEN. This is about one tile, most desklets sit in the upper half, and
/// a bottom sheet therefore opened as far from its subject as the display
/// allows with the tile itself behind the scrim.
///
/// So it is a panel beside the tile, on the same glass every other floating
/// surface uses, positioned below when there is room and above when there is
/// not.
///
/// And it made resize the ONLY discoverable action, because handles on the
/// selected tile were the whole vocabulary. Remove was a small badge in a
/// corner; per-widget settings and stacks had nowhere to live at all.
///
/// So the hold opens this, and only Resize enters edit mode. Everything else
/// happens without the desktop ever becoming draggable.
///
/// ─── THE ROWS DIFFER FOR A STACK ────────────────────────────────────────────
///
/// A stack offers Unstack where a plain tile offers Make a stack, because those
/// are the same action in opposite directions and showing both would leave one
/// of them inert. Everything else is shared: a stack resizes, takes settings
/// and is removed exactly like any other tile.
Future<void> showDeskletMenu(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
  Desklet desklet, {
  /// The tile's rectangle in global coordinates, so the panel opens beside the
  /// thing it is about. Null falls back to the centre of the screen, which is
  /// only reachable if a caller could not measure itself.
  Rect? anchor,
}) {
  HapticFeedback.mediumImpact();

  final isStack = desklet.kind == 'stack';

  // Built from the theme rather than looked up: the desktop is not guaranteed
  // to sit under a ChromeScope, and this route is not a descendant of it.
  final chrome = ChromeData.fromPalette(
    theme.palette,
    typography: theme.typography,
    textScale: theme.textScale,
    family: theme.chromeFamily,
    opacity: theme.surfaceOpacity,
    // The panel material, so this menu is cut and blurred like every other
    // floating surface. Built here rather than read from a scope because the
    // desktop is not guaranteed to sit under one and this route is not a
    // descendant of it, which is also why it is the one place that can forget.
    panelBlur: theme.panelBlur,
    panelTint: theme.panelTint,
    panelRadius: theme.panelRadius,
  );

  // ─── POSITIONING LIVES IN AnchoredMenu NOW ────────────────────────────
  //
  // This file used to compute its own: a width constant, a height GUESSED from
  // the row count times 56 plus a 44 header, a clamp and a flip. Two other
  // menus had written the same arithmetic with different constants, and two
  // more still needed it, so it moved to one primitive.
  //
  // The guessed height was the part worth losing. It was a claim about a widget
  // that had not been built, so a row that wrapped, a longer translation or a
  // larger system font positioned the panel against a height it did not have.
  // AnchoredMenu measures the child instead.
  return AnchoredMenu.show(
    context: context,
    chrome: chrome,
    anchor: anchor,
    // ─── NO TITLE, NO DESCRIPTIONS, ONE ROW ───────────────────────────────
    //
    // This was a headed list: the widget's name, then four rows each with a
    // sentence under it. The menu opens beside the widget it is about, so the
    // name was repeating what the finger was already on, and the sentences
    // turned a quick gesture into something to read.
    //
    // `actions` is the menu's own icon strip, the one an app's menu uses, so
    // each distro still draws it its own way and a list-shaped menu gets plain
    // rows without subtitles.
    width: 272,
    actions: _actions(context, ref, theme, desklet, isStack),
    // `context`, the CALLER's, is what the actions close over. Anything that
    // opens a second surface must push from a context that OUTLIVES this
    // panel: the menu's own is dead the instant an action pops it.
    rows: (_) => const [],
  );
}

/// What a held tile can do. The menu pops itself before calling `onTap`.
///
/// A stack trades Stack for Add and Unstack, the same action in the other
/// direction plus the one a stack exists for.
List<MenuAction> _actions(
  BuildContext host,
  WidgetRef ref,
  EffectiveTheme theme,
  Desklet desklet,
  bool isStack,
) {
  return [
    MenuAction(
      icon: Icons.open_with,
      label: host.t('desklets.actMove'),
      onTap: () {
        if (layoutLockRefuses(host)) return;
        final edit = ref.read(deskletEditProvider.notifier);
        edit.enter();
        edit.select(desklet.id);
      },
    ),
    if (isStack) ...[
      MenuAction(
        icon: Icons.add,
        label: host.t('common.add'),
        onTap: () {
          if (layoutLockRefuses(host)) return;
          showDeskletPicker(
            host,
            ref,
            theme,
            page: desklet.page,
            intoStack: desklet.id,
          );
        },
      ),
      MenuAction(
        icon: Icons.layers_clear_outlined,
        label: host.t('desklets.unstack'),
        onTap: () {
          if (layoutLockRefuses(host)) return;
          ref.read(prefsProvider(theme.spec.id).notifier).edit(
                (p) => DeskletLayout.unstack(
                  p,
                  desklet.id,
                  cols: theme.deskletCols,
                  rows: theme.deskletRows,
                ),
              );
        },
      ),
    ] else
      MenuAction(
        icon: Icons.layers_outlined,
        label: host.t('desklet_spec.stack'),
        onTap: () {
          if (layoutLockRefuses(host)) return;
          ref.read(prefsProvider(theme.spec.id).notifier).edit(
                (p) => DeskletLayout.makeStack(
                  p,
                  desklet.id,
                  newId: () => 'st${DateTime.now().microsecondsSinceEpoch}',
                ),
              );
        },
      ),
    MenuAction(
      icon: Icons.tune,
      label: host.t('desklets.actStyle'),
      onTap: () => showDeskletSettings(host, ref, theme, desklet),
    ),
    MenuAction(
      icon: Icons.delete_outline,
      label: host.t('desklets.remove'),
      danger: true,
      // Removing is the most final change to a layout, and it was the one a
      // lock let through. Style stays open: it is how a tile looks, not where.
      onTap: () {
        if (layoutLockRefuses(host)) return;
        removeDesklet(ref, theme, desklet);
      },
    ),
  ];
}

/// Take a desklet off the desktop, releasing anything native it owns.
///
/// ─── WHY THIS IS A FUNCTION AND NOT TWO COPIES ──────────────────────────────
///
/// A hosted AppWidget holds a device-local id allocated by `AppWidgetHost`. Drop
/// the placement without releasing it and the allocation leaks for the life of
/// the install: the host keeps listening for a widget nothing draws, and the id
/// is never reused.
///
/// That knowledge lived inside the editor's close badge, which was the only way
/// to remove a desklet at the time. It is now reachable from two places, and
/// two copies of "remember to free the native thing" is how one of them ends up
/// forgetting.
void removeDesklet(
  WidgetRef ref,
  EffectiveTheme theme,
  Desklet desklet,
) {
  HapticFeedback.mediumImpact();

  // Nothing selected any more; leaving a stale id selected would draw handles
  // around a tile that no longer exists.
  ref.read(deskletEditProvider.notifier).select(null);

  // ── A STACK TAKES ITS MEMBERS WITH IT ────────────────────────────────
  //
  // Members are parked on a page nothing renders, so deleting the stack alone
  // would leave them stored, invisible and unreachable forever, each hosted one
  // still holding a native allocation. Collected BEFORE the edit, while the
  // stack still exists to be read.
  final doomed = <Desklet>[
    desklet,
    if (desklet.kind == 'stack')
      ...DeskletLayout.stackContents(theme.prefs, desklet.id),
  ];

  for (final d in doomed) {
    if (d.kind != 'appwidget') continue;
    final id = d.config['widgetId'];
    if (id is int) {
      // TWO calls, and both are required.
      //
      // `releaseStageWidget` destroys the AppWidgetHostView in the native
      // stage. Without it the view stays in the layer forever, still listening,
      // still holding the provider's whole RemoteViews tree, simply positioned
      // nowhere. Nothing else destroys a stage view: a widget that merely
      // scrolls off a page is HIDDEN and keeps its view, which is the whole
      // reason page swipes stopped re-inflating widgets.
      //
      // `removeWidget` frees the host id itself, which is the leak documented
      // at length in the old WidgetHost notes: an allocation not matched by a
      // delete survives an app data clear on several OEM skins.
      releaseStageWidget(id);
      api.LauncherHostApi().removeWidget(id);
    }
  }

  ref.read(prefsProvider(theme.spec.id).notifier).edit((p) {
    var out = p;
    for (final d in doomed) {
      out = DeskletLayout.remove(out, d.id);
    }
    return out;
  });
}
