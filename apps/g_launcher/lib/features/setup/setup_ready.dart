import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/prefs/folder_suggestions.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../data/repositories/shell_apps.dart';
import '../../engine/effective_theme.dart';
import '../../i18n/i18n.dart';
import '../../platform/launcher_api.g.dart' show AppEntry;
import '../drawer/folder_glyph.dart';
import 'setup_live_preview.dart';
import 'setup_sheet.dart';

/// Which sheet is open over the Ready rows, if any.
enum _Open { none, icons, dock, drawer, folders }

/// The drawer layouts setup offers, as stored in prefs.
enum _DrawerLayout { pages, list, az }

/// Boards 3 and 3a to 3d: Make it yours.
///
/// The live desktop on top, four rows below. A row opens its sheet in place of
/// the rows, and every choice writes straight to this distro's prefs, so the
/// real desktop above changes as the finger lifts. There is no "apply": the
/// preview IS the applied state.
///
/// The two answers this screen cannot write immediately (icon choice needs a
/// download decision, folders need creating) are owned by the setup screen
/// and handed in, the same state the old wizard kept.
class SetupReady extends ConsumerStatefulWidget {
  const SetupReady({
    super.key,
    required this.theme,
    required this.distroIcons,
    required this.onDistroIcons,
    required this.skippedFolders,
    required this.onToggleFolder,
    required this.onContinue,
    required this.onBack,
  });

  final EffectiveTheme theme;

  /// True for the distro's own icon set, false for each app's own artwork.
  final bool distroIcons;
  final ValueChanged<bool> onDistroIcons;

  /// Suggested folder names the user switched off.
  final Set<String> skippedFolders;
  final ValueChanged<String> onToggleFolder;

  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  ConsumerState<SetupReady> createState() => _SetupReadyState();
}

class _SetupReadyState extends ConsumerState<SetupReady> {
  _Open _open = _Open.none;

  EffectiveTheme get _theme => widget.theme;

  /// Writes one change to the chosen distro's prefs bucket.
  void _edit(LauncherPrefs Function(LauncherPrefs p) change) =>
      ref.read(prefsProvider(_theme.spec.id).notifier).edit(change);

  _DrawerLayout get _layout {
    if (_theme.drawerScrollStyle != 'vertical') return _DrawerLayout.pages;
    return _theme.drawerGrouping == 'az'
        ? _DrawerLayout.az
        : _DrawerLayout.list;
  }

  /// The drawer layout, written the way Settings writes it.
  ///
  /// Grouping only means something on the list, so leaving the list clears
  /// it. A custom sort is cleared on entering the list, matching the old setup
  /// step: a hand-arranged order has no meaning without pages to arrange on.
  void _setLayout(_DrawerLayout v) => _edit((p) {
        final toList = switch (v) {
          _DrawerLayout.pages => null,
          _DrawerLayout.list => 'none',
          _DrawerLayout.az => 'az',
        };
        if (toList == null) {
          return p
              .copyWith(drawerScrollStyle: 'pages')
              .clearing(drawerGrouping: true);
        }
        final listed =
            p.copyWith(drawerScrollStyle: 'vertical', drawerGrouping: toList);
        return (p.drawerSortMode ?? 'custom') == 'custom'
            ? listed.clearing(drawerSortMode: true)
            : listed;
      });

  List<FolderSuggestion> _suggestions() => FolderSuggestions.propose(
        ref.watch(shellAppsProvider(_theme)),
        _theme.prefs,
      );

  String _layoutLabel(_DrawerLayout v) => switch (v) {
        _DrawerLayout.pages => ref.t('setup.ready.drawerPages'),
        _DrawerLayout.list => ref.t('setup.ready.drawerList'),
        _DrawerLayout.az => ref.t('setup.ready.drawerAz'),
      };

  String _dockLabel(String side) => switch (side) {
        'bottom' => ref.t('setup.ready.dockBottom'),
        'off' => ref.t('setup.ready.dockOff'),
        'right' => ref.t('setup.ready.dockRight'),
        _ => ref.t('setup.ready.dockLeft'),
      };

  @override
  Widget build(BuildContext context) {
    final ink = SetupInk.forSpec(_theme.spec);
    final body = switch (_open) {
      _Open.none => _rows(ink),
      _Open.icons => _iconsSheet(ink),
      _Open.dock => _dockSheet(ink),
      _Open.drawer => _drawerSheet(ink),
      _Open.folders => _foldersSheet(ink),
    };

    return PopScope(
      // An open sheet closes on back before the screen does.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_open != _Open.none) {
          setState(() => _open = _Open.none);
        } else {
          widget.onBack();
        }
      },
      child: SetupStageScaffold(
        theme: _theme,
        ink: ink,
        liveLabel: ref.t('setup.ready.live'),
        mode: _open == _Open.drawer
            ? SetupPreviewMode.drawer
            : SetupPreviewMode.desktop,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(_open), child: body),
        ),
      ),
    );
  }

  /// The sheet frame: grip, heading, scrolling content, pinned actions.
  Widget _frame(
    SetupInk ink, {
    required String kicker,
    required String title,
    String? subtitle,
    required List<Widget> children,
    required List<Widget> actions,
  }) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetupGrip(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: SetupHeading(
            ink: ink,
            kicker: kicker,
            title: title,
            subtitle: subtitle,
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ...children,
              Container(height: 1, color: ink.line),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: actions,
          ),
        ),
      ],
    );
  }

  Widget _done(SetupInk ink) => SetupPrimaryButton(
        ink: ink,
        label: ref.t('common.done'),
        onPressed: () => setState(() => _open = _Open.none),
      );

  Widget _rows(SetupInk ink) {
    final folders = _suggestions();
    final chosen =
        folders.where((f) => !widget.skippedFolders.contains(f.name)).length;
    return _frame(
      ink,
      kicker: ref.t('setup.ready.kicker'),
      title: ref.t('setup.ready.title', {'name': _theme.spec.name}),
      subtitle: ref.t('setup.ready.subtitle'),
      children: [
        SetupValueRow(
          ink: ink,
          title: ref.t('setup.ready.icons'),
          value: widget.distroIcons
              ? ref.t('setup.ready.iconsDistro', {'name': _theme.spec.name})
              : ref.t('setup.ready.iconsPhone'),
          onTap: () => setState(() => _open = _Open.icons),
        ),
        if (!_theme.phoneHome)
          SetupValueRow(
            ink: ink,
            title: ref.t('setup.ready.dock'),
            value: _dockLabel(_theme.dock.name),
            onTap: () => setState(() => _open = _Open.dock),
          ),
        SetupValueRow(
          ink: ink,
          title: ref.t('setup.ready.drawer'),
          value: ref.t('setup.ready.drawerValue', {
            'layout': _layoutLabel(_layout),
            'n': '${_theme.drawerCols}',
          }),
          onTap: () => setState(() => _open = _Open.drawer),
        ),
        SetupValueRow(
          ink: ink,
          title: ref.t('setup.ready.folders'),
          value: switch (chosen) {
            0 => ref.t('setup.ready.foldersNone'),
            1 => ref.t('setup.ready.foldersOne'),
            final n => ref.t('setup.ready.foldersCount', {'n': '$n'}),
          },
          onTap: () => setState(() => _open = _Open.folders),
        ),
      ],
      actions: [
        SetupPrimaryButton(
          ink: ink,
          label: ref.t('setup.next.continue'),
          onPressed: widget.onContinue,
        ),
        const SizedBox(height: 4),
        Center(
          child: SetupLink(
            ink: ink,
            label: ref.t('common.back'),
            onPressed: widget.onBack,
          ),
        ),
      ],
    );
  }

  Widget _iconsSheet(SetupInk ink) => _frame(
        ink,
        kicker: ref.t('setup.ready.icons'),
        title: ref.t('setup.ready.iconsTitle'),
        children: [
          SetupChoiceRow(
            ink: ink,
            title: ref.t('setup.ready.iconsDistro', {'name': _theme.spec.name}),
            subtitle: ref.t('setup.ready.iconsDistroSub'),
            selected: widget.distroIcons,
            onTap: () => widget.onDistroIcons(true),
          ),
          SetupChoiceRow(
            ink: ink,
            title: ref.t('setup.ready.iconsPhone'),
            subtitle: ref.t('setup.ready.iconsPhoneSub'),
            selected: !widget.distroIcons,
            onTap: () => widget.onDistroIcons(false),
          ),
        ],
        actions: [_done(ink)],
      );

  Widget _dockSheet(SetupInk ink) {
    final side = _theme.dock.name;
    Widget row(String value, String sub) => SetupChoiceRow(
          ink: ink,
          title: _dockLabel(value),
          subtitle: sub,
          selected: side == value,
          onTap: () => _edit((p) => p.copyWith(dockSide: value)),
        );
    return _frame(
      ink,
      kicker: ref.t('setup.ready.dock'),
      title: ref.t('setup.ready.dockTitle'),
      children: [
        row('left', ref.t('setup.ready.dockLeftSub')),
        row('bottom', ref.t('setup.ready.dockBottomSub')),
        row('off', ref.t('setup.ready.dockOffSub')),
      ],
      actions: [_done(ink)],
    );
  }

  Widget _drawerSheet(SetupInk ink) {
    final layout = _layout;
    Widget row(_DrawerLayout v, String sub) => SetupChoiceRow(
          ink: ink,
          title: _layoutLabel(v),
          subtitle: sub,
          selected: layout == v,
          onTap: () => _setLayout(v),
        );
    return _frame(
      ink,
      kicker: ref.t('setup.ready.drawer'),
      title: ref.t('setup.ready.drawerTitle'),
      children: [
        row(_DrawerLayout.pages, ref.t('setup.ready.drawerPagesSub')),
        row(_DrawerLayout.list, ref.t('setup.ready.drawerListSub')),
        row(_DrawerLayout.az, ref.t('setup.ready.drawerAzSub')),
        Container(height: 1, color: ink.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            ref.t('setup.ready.columns'),
            style: TextStyle(fontSize: 13, color: ink.textMuted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: SetupSegmented<int>(
            ink: ink,
            options: const {3: '3', 4: '4', 5: '5', 6: '6'},
            selected: _theme.drawerCols,
            onChanged: (n) => _edit((p) => p.copyWith(drawerCols: n)),
          ),
        ),
      ],
      actions: [_done(ink)],
    );
  }

  Widget _foldersSheet(SetupInk ink) {
    final apps = ref.watch(shellAppsProvider(_theme));
    final byKey = {for (final a in apps) a.componentKey: a};
    final folders = _suggestions();
    // Games first, the folder people most want made for them.
    final ordered = [
      ...folders.where((s) => s.kind == SuggestionKind.games),
      ...folders.where((s) => s.kind != SuggestionKind.games),
    ];

    return _frame(
      ink,
      kicker: ref.t('setup.ready.folders'),
      title: ref.t('setup.ready.foldersTitle'),
      subtitle: ordered.isEmpty
          ? ref.t('setup.nothingWorthGroupingYet')
          : ref.t('setup.ready.foldersSub'),
      children: [
        for (final sg in ordered)
          Builder(
            builder: (context) {
              final members = [
                for (final k in sg.componentKeys)
                  if (byKey[k] != null) byKey[k]!,
              ];
              return SetupSwitchRow(
                ink: ink,
                title: sg.name,
                subtitle: _memberLine(members),
                value: !widget.skippedFolders.contains(sg.name),
                onChanged: (_) => widget.onToggleFolder(sg.name),
                leading: FolderGlyph(
                  theme: _theme,
                  size: 40,
                  members: members,
                ),
              );
            },
          ),
      ],
      actions: [_done(ink)],
    );
  }

  /// "Chrome, Gmail, Maps and 4 more": the members, by name.
  String _memberLine(List<AppEntry> members) {
    final names = [for (final m in members.take(3)) m.label];
    final rest = members.length - names.length;
    return rest > 0
        ? ref.t('setup.ready.membersMore', {
            'names': names.join(', '),
            'n': '$rest',
          })
        : names.join(', ');
  }
}
