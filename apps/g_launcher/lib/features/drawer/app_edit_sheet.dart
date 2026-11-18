import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/single_flight_picker.dart';
import '../../data/prefs/hidden_apps.dart';
import '../../data/prefs/app_identity.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../data/repositories/app_repository.dart';
import '../../design/components/components.dart';
import '../../design/settings_look.dart';
import '../../engine/effective_theme.dart';
import '../../platform/launcher_api.g.dart';
import '../icons/icon_theme_screen.dart' show installedIconThemesProvider;
import '../palette/fuzzy.dart';
import 'app_icon.dart';

/// Edit an app's identity: its name, its icon, and whether its count shows.
/// PHASES G2 and G2b.
///
/// Reached from the app menu's Edit row, which every drawer and the desktop
/// share, so it exists on every distro. [ThemedSheet] draws it in the
/// distro's own idiom: a sheet that slides up on GNOME, Plasma and Pocket, a
/// window on the desktops whose settings are windows.
///
/// ─── THE ORIGINAL NAME IS THE HINT, NOT A LINE OF TEXT ──────────────────────
///
/// Clearing the field shows the app's own name as the hint, and saving an
/// empty field gives that name back. So "what was it called" and "put it
/// back" need no extra sentence on the sheet.
///
/// ─── NATIVE FIRST, THEN PREFS ───────────────────────────────────────────────
///
/// Save pushes the new icon map to native and waits for it before writing
/// prefs. The prefs write is what changes the icon's request key, so by the
/// time anything asks for the icon again, native already draws the choice.
/// The app `edit <query>` means, for the terminal shells, which have no
/// long-press to reach this sheet from.
///
/// The same admission `open` uses: a hidden app answers only to its whole
/// name, so the command cannot be used to find what was hidden.
AppEntry? appForEdit(WidgetRef ref, EffectiveTheme theme, String query) {
  final q = query.trim();
  if (q.isEmpty) return null;
  final all = ref.read(appListProvider).asData?.value ?? const <AppEntry>[];
  final ranked = Fuzzy.rank(
    HiddenApps.forSearch(all, theme.prefs, q),
    q,
    label: (a) => a.label,
  );
  return ranked.isEmpty ? null : ranked.first.item;
}

Future<void> showAppEditSheet(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
  AppEntry entry,
) {
  // Captured before the sheet opens: the menu that launched it is gone by the
  // time Save is pressed, and its `ref` with it.
  final prefs = ref.read(prefsProvider(theme.spec.id).notifier);
  final api = ref.read(launcherHostApiProvider);
  final key = entry.componentKey;
  final original =
      ref.read(appListProvider.notifier).originalLabel(key) ?? entry.label;

  // Built from the theme, as the app menu builds its own: the drawer that
  // opened this is not guaranteed to sit under a ChromeScope.
  final chrome = ChromeData.fromPalette(
    theme.palette,
    typography: theme.typography,
    textScale: theme.textScale,
    family: theme.chromeFamily,
    opacity: theme.surfaceOpacity,
    panelBlur: theme.panelBlur,
    panelTint: theme.panelTint,
    panelRadius: theme.panelRadius,
  );

  return ThemedSheet.show<void>(
    context,
    title: context.t('appEdit.title'),
    isScrollControlled: true,
    chrome: chrome,
    builder: (sheet) => _EditBody(
      entry: entry,
      original: original,
      muted: theme.prefs.badgeMuted.contains(key),
      icon: theme.prefs.iconOverrides[key],
      onSave: (name, muted, icon) async {
        final icons = {...theme.prefs.iconOverrides};
        if (icon == null) {
          icons.remove(key);
        } else {
          icons[key] = icon;
        }
        await api.setIconOverrides(icons);
        await prefs.edit((p) {
          final named = AppIdentity.rename(p, key, name, original: original);
          final counted = AppIdentity.muteBadge(named, key, muted: muted);
          return AppIdentity.setIcon(counted, key, icon);
        });
      },
    ),
  );
}

class _EditBody extends ConsumerStatefulWidget {
  const _EditBody({
    required this.entry,
    required this.original,
    required this.muted,
    required this.icon,
    required this.onSave,
  });

  final AppEntry entry;
  final String original;
  final bool muted;

  /// The current icon choice, or null for the distro's.
  final String? icon;

  final Future<void> Function(String name, bool muted, String? icon) onSave;

  @override
  ConsumerState<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends ConsumerState<_EditBody> {
  late final TextEditingController _name;
  late bool _countOn;
  String? _icon;

  /// Previews already asked for, by choice ('' for the distro's icon), so a
  /// rebuild does not ask native to draw the same icon again.
  final Map<String, Future<Uint8List?>> _previews = {};

  /// The icon as the current, unsaved choice draws it.
  ///
  /// ─── THE PREVIEW SHOWS THE CHOICE, NOT THE SAVED ICON ─────────────────
  ///
  /// [AppIcon] draws what is saved, so picking a pack or a photo changed the
  /// check mark and nothing else, and the only way to see a choice was to
  /// save it. Native draws the unsaved choice off to the side, uncached.
  Widget _preview(double size) {
    final saved = AppIcon(entry: widget.entry, size: size, showBadge: false);
    if (_icon == widget.icon) return saved;
    final choice = _icon ?? '';
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final future = _previews.putIfAbsent(
      choice,
      () => ref
          .read(launcherHostApiProvider)
          .previewIconChoice(widget.entry.componentKey, choice, px),
    );
    return FutureBuilder<Uint8List?>(
      key: ValueKey(choice),
      future: future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return saved;
        return Image.memory(
          bytes,
          width: size,
          height: size,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Preselected, so the first keystroke replaces rather than appends.
    final current = widget.entry.label;
    _name = TextEditingController(text: current)
      ..selection = TextSelection(baseOffset: 0, extentOffset: current.length);
    _countOn = !widget.muted;
    _icon = widget.icon;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.selectionClick();
    final navigator = Navigator.of(context);
    await widget.onSave(_name.text, !_countOn, _icon);
    navigator.pop();
  }

  /// Copy a picked photo into this app's own files, under a name that is new
  /// every time. The name is in the icon's cache key, so reusing one would
  /// keep showing the previous photo.
  Future<void> _pickPhoto() async {
    final picked = await SingleFlightPicker.pickImage();
    if (picked == null) return;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/app_icons');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = widget.entry.componentKey.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
    final path = '${dir.path}/${safe}_${DateTime.now().millisecondsSinceEpoch}';
    await picked.saveTo(path);
    if (mounted) setState(() => _icon = '${AppIdentity.iconImagePrefix}$path');
  }

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    final changed = _name.text.trim() != widget.original;
    final packs = ref.watch(installedIconThemesProvider).value ?? const {};

    Widget choice(IconData glyph, String title, String? value) {
      final on = value == null ? _icon == null : _icon == value;
      return ThemedListRow(
        icon: glyph,
        title: title,
        trailing: on ? Icon(Icons.check, color: c.accent, size: 20) : null,
        onTap: () => setState(() => _icon = value),
      );
    }

    final photo = _icon != null &&
        _icon!.startsWith(AppIdentity.iconImagePrefix);

    // ─── iOS: THE OPTIONS ON CARDS, NOT ON THE GLASS ──────────────────────
    //
    // Pocket's sheet is frosted glass over the home screen, and bare rows on
    // it read as faint text floating over icons. iOS puts a sheet's choices
    // on inset grouped cards with a solid fill, which is what makes them
    // read as controls; the other distros keep their own flat rows.
    final grouped = (SheetLookScope.of(context) ??
            SettingsLook.resolve(context)) ==
        SettingsLook.grouped;
    Widget section(List<Widget> rows) {
      if (grouped) return ThemedListCard(children: rows);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, color: c.line),
            rows[i],
          ],
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _preview(44),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: c.text, fontSize: 17),
                  cursorColor: c.accent,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: widget.original,
                    hintStyle: TextStyle(color: c.textFaint),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: c.line),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: c.accent),
                    ),
                    // The way back to the app's own name, only while the
                    // field holds something else.
                    suffixIcon: changed
                        ? IconButton(
                            tooltip: context.t('appEdit.reset'),
                            icon: Icon(Icons.undo, color: c.textMuted),
                            onPressed: () => setState(() {
                              _name.text = widget.original;
                              _name.selection = TextSelection.collapsed(
                                offset: widget.original.length,
                              );
                            }),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section([
                    ThemedListRow(
                      icon: Icons.notifications_outlined,
                      title: context.t('appEdit.count'),
                      trailing: ThemedToggle(
                        value: _countOn,
                        onChanged: (v) => setState(() => _countOn = v),
                      ),
                      onTap: () => setState(() => _countOn = !_countOn),
                    ),
                  ]),
                  if (grouped)
                    const SizedBox(height: 12)
                  else
                    Divider(height: 0.5, thickness: 0.5, color: c.line),
                  // ── THE ICON: THE DISTRO'S, THE APP'S OWN, A PACK'S, A PHOTO
                  section([
                    choice(Icons.palette_outlined,
                        context.t('appEdit.iconDistro'), null),
                    choice(Icons.android, context.t('appEdit.iconApp'),
                        AppIdentity.iconApp),
                    for (final pack in packs.entries)
                      choice(Icons.style_outlined, pack.value,
                          '${AppIdentity.iconPackPrefix}${pack.key}'),
                    ThemedListRow(
                      icon: Icons.photo_outlined,
                      title: context.t('appEdit.iconPhoto'),
                      trailing: photo
                          ? Icon(Icons.check, color: c.accent, size: 20)
                          : null,
                      onTap: _pickPhoto,
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ThemedButton(
            label: context.t('common.save'),
            expand: true,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
