import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/desklet_layout.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../design/branded_message.dart';
import '../../engine/effective_theme.dart';
import '../home/workspaces/workspace_controller.dart';
import 'desklet_edit.dart';
import 'desklet_picker.dart';
import 'layout_lock.dart';

/// The bar that says the desktop is being edited. PHASE D4, floated in 3b,
/// given multi-select in 3c.
///
/// ─── WHY THERE IS A VISIBLE EXIT AT ALL ─────────────────────────────────────
///
/// Edit mode disables workspace swiping (the PageView takes
/// NeverScrollableScrollPhysics so a move drag is uncontested). A mode that
/// silently breaks the desktop's main gesture and offers no way out is how a
/// launcher gets uninstalled, so it says what it is and how to leave, and back
/// leaves it too.
///
/// ─── A PILL, NOT A BAR ──────────────────────────────────────────────────────
///
/// It was a full-width strip pinned to the bottom edge, which covered the dock
/// and the bottom row of the very grid being arranged. A pill that floats over
/// the wallpaper keeps the desktop full-bleed and reads as a tool laid on the
/// work rather than as a frame around it.
///
/// ─── FOUR POSTURES, ONE PILL ────────────────────────────────────────────────
///
///  arranging   Add, Select, Lock, Done
///  one tile    "Editing widget", Done. The tile's own handles do the rest.
///  selecting   the pick count, Align, Group or Ungroup, Done
///  tools       back, then align and spacing glyphs, opened from Align
///
/// The pill grows and shrinks between them rather than swapping for a second
/// toolbar, so the thing under the thumb is always the same object.
class DeskletEditBar extends ConsumerStatefulWidget {
  const DeskletEditBar({super.key, required this.theme});

  final EffectiveTheme theme;

  @override
  ConsumerState<DeskletEditBar> createState() => _DeskletEditBarState();
}

class _DeskletEditBarState extends ConsumerState<DeskletEditBar> {
  /// The align and spacing tools are showing in place of the selecting row.
  bool _tools = false;

  EffectiveTheme get _theme => widget.theme;

  /// Writes [change] to the active theme's prefs, or says why it could not.
  ///
  /// Every arrange operation returns the SAME prefs when it refuses, so a
  /// refusal is one identity check, the same contract the drag uses.
  bool _apply(LauncherPrefs Function(LauncherPrefs) change) {
    final before = ref.read(prefsProvider(_theme.spec.id)).value;
    if (before == null) return false;
    final after = change(before);
    if (identical(after, before)) {
      HapticFeedback.heavyImpact();
      context.showMessage(context.t('desklets.noRoomArrange'));
      return false;
    }
    HapticFeedback.selectionClick();
    ref.read(prefsProvider(_theme.spec.id).notifier).edit((_) => after);
    return true;
  }

  /// The group id every picked tile shares, when the pick is exactly one
  /// whole group. That is the case where Group becomes Ungroup.
  String? _pickedGroup(Set<String> picked) {
    final prefs = ref.read(prefsProvider(_theme.spec.id)).value;
    if (prefs == null || picked.length < 2) return null;
    String? g;
    for (final id in picked) {
      final d = DeskletLayout.byId(prefs, id);
      if (d == null || d.group == null) return null;
      if (g != null && d.group != g) return null;
      g = d.group;
    }
    if (g == null) return null;
    return DeskletLayout.groupOf(prefs, picked.first).length == picked.length
        ? g
        : null;
  }

  void _lock() {
    HapticFeedback.mediumImpact();
    final container = ProviderScope.containerOf(context, listen: false);
    ref.read(deskletEditProvider.notifier).exit();
    writeLayoutLocked(container, true);
    context.showMessage(context.t('home.layoutLocked'));
  }

  void _group(Set<String> picked) {
    final id = 'g${DateTime.now().microsecondsSinceEpoch}';
    if (_apply((p) => DeskletLayout.group(p, picked, groupId: id))) {
      context.showMessage(context.t('desklets.grouped'));
    }
  }

  void _ungroup(Set<String> picked) {
    if (_apply((p) => DeskletLayout.ungroup(p, picked))) {
      // The pick stays on the same tiles, now separate, so the next tap
      // drops one tile instead of the whole former group.
      context.showMessage(context.t('desklets.ungrouped'));
    }
  }

  void _align(Set<String> picked, DeskletAlign how) => _apply(
        (p) => DeskletLayout.align(
          p,
          picked,
          how,
          cols: _theme.deskletCols,
          rows: _theme.deskletRows,
        ),
      );

  void _space(Set<String> picked, {required bool horizontal}) => _apply(
        (p) => DeskletLayout.distribute(
          p,
          picked,
          horizontal: horizontal,
          cols: _theme.deskletCols,
          rows: _theme.deskletRows,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final edit = ref.watch(deskletEditProvider);
    if (!edit.active) {
      _tools = false;
      return const SizedBox.shrink();
    }
    // Tools belong to a pick; leaving the selecting posture closes them.
    if (!edit.selecting) _tools = false;

    final p = _theme.palette;
    final ink = p.onDark;
    final insets = MediaQuery.viewPaddingOf(context);
    final picked = edit.picked;

    final List<Widget> children;
    if (edit.selecting && _tools) {
      children = _toolRow(picked);
    } else if (edit.selecting) {
      children = _selectingRow(picked);
    } else if (edit.selected != null) {
      children = [
        _Status(
          theme: _theme,
          icon: Icons.open_with,
          text: context.t('desklets.editingWidget'),
        ),
        _done(() => ref.read(deskletEditProvider.notifier).exit()),
      ];
    } else {
      children = [
        _Action(
          theme: _theme,
          icon: Icons.add,
          label: context.t('common.add'),
          // No col/row: the Add button means "somewhere", and the packer
          // finds the first free rectangle. Tapping a specific empty cell is
          // the way to say WHERE.
          onTap: () => showDeskletPicker(
            context,
            ref,
            _theme,
            page: ref.read(activeWorkspaceProvider),
          ),
        ),
        // Only where there are desklets to pick: the apps' jiggle mode
        // shares this pill and has nothing for Select to act on.
        if (edit.editingDesklets)
          _Action(
            theme: _theme,
            icon: Icons.library_add_check_outlined,
            label: context.t('desklets.select'),
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(deskletEditProvider.notifier).startSelecting();
            },
          ),
        _Action(
          theme: _theme,
          icon: Icons.lock_outline,
          label: context.t('home.lock'),
          onTap: _lock,
        ),
        _done(() => ref.read(deskletEditProvider.notifier).exit()),
      ];
    }

    return Positioned(
      left: 12,
      right: 12,
      bottom: insets.bottom + 18,
      child: Center(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.bar.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: ink.withValues(alpha: 0.08)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }

  Widget _done(VoidCallback onTap) => _Action(
        theme: _theme,
        icon: Icons.check,
        label: context.t('common.done'),
        color: _theme.palette.accent,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      );

  List<Widget> _selectingRow(Set<String> picked) {
    final group = _pickedGroup(picked);
    return [
      _Status(
        theme: _theme,
        icon: Icons.library_add_check_outlined,
        text: picked.isEmpty
            ? context.t('desklets.pickHint')
            : context.t('desklets.picked', {'count': '${picked.length}'}),
      ),
      if (picked.length >= 2) ...[
        _Action(
          theme: _theme,
          icon: Icons.align_horizontal_left,
          label: context.t('desklets.align'),
          onTap: () => setState(() => _tools = true),
        ),
        if (group != null)
          _Action(
            theme: _theme,
            icon: Icons.link_off,
            label: context.t('desklets.ungroup'),
            onTap: () => _ungroup(picked),
          )
        else
          _Action(
            theme: _theme,
            icon: Icons.link,
            label: context.t('desklets.group'),
            onTap: () => _group(picked),
          ),
      ],
      _done(() => ref.read(deskletEditProvider.notifier).stopSelecting()),
    ];
  }

  List<Widget> _toolRow(Set<String> picked) {
    final three = picked.length >= 3;
    Widget tool(IconData icon, String key, VoidCallback onTap,
            {bool enabled = true}) =>
        _Glyph(
          theme: _theme,
          icon: icon,
          label: context.t(key),
          onTap: enabled ? onTap : null,
        );

    return [
      tool(Icons.chevron_left, 'common.back',
          () => setState(() => _tools = false)),
      tool(Icons.align_horizontal_left, 'desklets.alignLeft',
          () => _align(picked, DeskletAlign.left)),
      tool(Icons.align_horizontal_center, 'desklets.alignCenterX',
          () => _align(picked, DeskletAlign.centerX)),
      tool(Icons.align_horizontal_right, 'desklets.alignRight',
          () => _align(picked, DeskletAlign.right)),
      tool(Icons.align_vertical_top, 'desklets.alignTop',
          () => _align(picked, DeskletAlign.top)),
      tool(Icons.align_vertical_center, 'desklets.alignMiddle',
          () => _align(picked, DeskletAlign.middle)),
      tool(Icons.align_vertical_bottom, 'desklets.alignBottom',
          () => _align(picked, DeskletAlign.bottom)),
      // Spacing needs a tile between two others; dimmed until there is one.
      tool(Icons.horizontal_distribute, 'desklets.spaceAcross',
          () => _space(picked, horizontal: true),
          enabled: three),
      tool(Icons.vertical_distribute, 'desklets.spaceDown',
          () => _space(picked, horizontal: false),
          enabled: three),
    ];
  }
}

/// A labelled action: glyph over a short word.
class _Action extends StatelessWidget {
  const _Action({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final EffectiveTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? theme.palette.onDark;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: tint),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: theme.typography.display,
                  fontSize: 11 * theme.textScale,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon-only tool. Nine words would not fit one pill on a phone, and these
/// glyphs are the ones every design tool uses, so the words live in the
/// tooltip and the screen reader instead.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final EffectiveTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: on,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(
            width: 38,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: theme.palette.onDark.withValues(alpha: on ? 1 : 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of status in the pill: what is being edited, or what is picked.
class _Status extends StatelessWidget {
  const _Status({required this.theme, required this.icon, required this.text});

  final EffectiveTheme theme;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = theme.palette.onDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ink.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              style: TextStyle(
                fontFamily: theme.typography.display,
                fontSize: 13 * theme.textScale,
                color: ink.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
