import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/prefs/desklet_layout.dart';
import '../../data/prefs/launcher_prefs.dart';
import '../../data/prefs/prefs_repository.dart';
import '../../design/components/components.dart';
import '../../engine/desklet_skin.dart';
import '../../engine/effective_theme.dart';
import '../../system/wallpaper_accent.dart';
import 'kinds/clock_faces.dart';
import 'kinds/folder_desklet.dart';
// parseColor, for the accent swatches.
import '../../engine/theme_spec.dart' show parseColor;

/// Per-widget appearance: corners, background, accent.
///
/// ─── THESE ARE SKIN OVERRIDES, NOT A NEW MECHANISM ──────────────────────────
///
/// [DeskletSkin.props] is already free-form, already merged rather than
/// replaced, and [DeskletFrame] already reads `radius` and `opacity` out of it
/// because that is how a distro tunes its own card. So a user's per-widget
/// settings are the same three keys written to [Desklet.config], merged over
/// the distro's skin at render time in `desklet_surface`.
///
/// That ordering is the whole point and it matches every other preference in
/// the app: the distro provides the default, the person beats it. It also means
/// a widget with nothing set renders EXACTLY as it did before this screen
/// existed, because an absent key inherits.
///
/// ─── WHY THE ACCENT SWATCHES ARE A SHORT LIST ───────────────────────────────
///
/// A full colour picker was the obvious thing and it is the wrong one here.
/// This launcher's argument is that a distro owns its colour; handing every
/// tile an arbitrary hex turns a GNOME desktop into a dashboard. The list is
/// the distro's own accent, a handful that read on any wallpaper, and "follow
/// the distro", which CLEARS the key rather than writing today's accent, so a
/// tile set to follow keeps following when the distro changes.
/// KEYS, not sentences. These are top-level `const`, so they cannot call
/// `context.t` at all: a const list is built before any widget exists. The
/// labels resolve where they are drawn, which is the same shape `_taglineKeyFor`
/// takes in setup and for the same reason.
const _cornerChoices = <({String labelKey, double radius})>[
  (labelKey: 'settings.square', radius: 0),
  (labelKey: 'settings.rounded', radius: 10),
  (labelKey: 'desklets.pill', radius: 22),
];

const _backgroundChoices = <({String labelKey, double opacity})>[
  (labelKey: 'desklets.none', opacity: 0),
  (labelKey: 'settings.light', opacity: 0.35),
  (labelKey: 'settings.medium', opacity: 0.62),
  (labelKey: 'desklets.solid', opacity: 0.92),
];

/// Content scale, as offered. 100% is the widget as drawn; see
/// content_scale.dart for why this is a layout change and not a zoom.
const _scaleChoices = <double>[0.8, 0.9, 1.0, 1.1, 1.2];

/// The background colours a widget's card can take, by the id stored in
/// config `bgColor`. Null follows the distro's own card colour.
const deskletBackgroundIds = <String?>[
  null,
  'accent',
  'dark',
  'light',
  'wallpaper',
];

/// The colour background [id] paints, or null to follow the distro.
///
/// Named choices rather than free colours, because each has to stay readable
/// under ink the widget does not control: dark and the accent carry light text
/// at any strength, and light is capped to a tint where it is drawn.
Color? deskletBackgroundColour(
  String? id, {
  required Color accent,
  Color? wallpaper,
}) =>
    switch (id) {
      'accent' => accent,
      'dark' => const Color(0xFF0E0E12), // theme-exempt: a colour the person chose
      'light' => const Color(0xFFFFFFFF), // theme-exempt: a colour the person chose
      'wallpaper' => wallpaper ?? accent,
      _ => null,
    };

/// `#RRGGBB` for [c], the form [parseColor] reads back.
String _hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// theme-exempt: a per-widget accent is by definition not the theme's, and this
/// is the fixed set offered beside it. The first entry is null, meaning follow.
const _accentChoices = <String?>[
  null,
  '#22D3EE',
  '#4ADE80',
  '#FBBF24',
  '#F472B6',
  '#A78BFA',
];

Future<void> showDeskletSettings(
  BuildContext context,
  WidgetRef ref,
  EffectiveTheme theme,
  Desklet desklet,
) {
  return ThemedSheet.show<void>(
    context,
    title: context.t('desklets.widgetSettings'),
    // Scrolls, because a clock's or folder's own rows come above the shared
    // ones and the whole set is taller than a short phone's sheet.
    builder: (sheet) => SingleChildScrollView(
      child: _Body(theme: theme, deskletId: desklet.id),
    ),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.theme, required this.deskletId});

  final EffectiveTheme theme;
  final String deskletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // LIVE, not the snapshot handed in. Every control below writes and the
    // sheet stays open, so reading the desklet off the push-time value would
    // show the old selection until it was closed and reopened.
    final live = ref.watch(prefsProvider(theme.spec.id)).hasValue
        ? ref.watch(prefsProvider(theme.spec.id)).requireValue
        : theme.prefs;

    final desklet = DeskletLayout.byId(live, deskletId);
    if (desklet == null) return const SizedBox.shrink();

    final config = desklet.config;

    void write(Map<String, Object?> patch) {
      HapticFeedback.selectionClick();
      // configure MERGES, so writing corners cannot drop the accent, and a key
      // written by a newer build survives being edited here.
      ref.read(prefsProvider(theme.spec.id).notifier).edit(
            (p) => DeskletLayout.configure(p, deskletId, patch),
          );
    }

    // A hosted third-party widget draws its own contents and colours. Its
    // corners, size and backing are applied natively around it (PHASE 4);
    // its accent is the app's, so that control is not offered.
    final hosted = desklet.kind == 'appwidget';
    final bare =
        theme.spec.desklets.skinFor(theme.shell, desklet.kind).surface ==
            DeskletSurface.bare;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // What the widget shows comes before how it looks. PHASE 7.
          if (desklet.kind == 'clock')
            ..._clockRows(context, theme, config, write),
          if (desklet.kind == 'folder')
            ..._folderRows(context, live, config, write),
          _Label(text: context.t('desklets.corners')),
          _Choices(
            labels: [for (final c in _cornerChoices) context.t(c.labelKey)],
            // A hosted widget untouched keeps the app's own corners, which
            // is Square here; a drawn card's default is the distro's rounding.
            selected: _nearestCorner(config['radius'], fallback: hosted ? 0 : 10),
            onPick: (i) => write({'radius': _cornerChoices[i].radius}),
          ),
          _Label(text: context.t('desklets.contentSize')),
          _Choices(
            labels: [
              for (final v in _scaleChoices) '${(v * 100).round()}%',
            ],
            selected: _nearestScale(config['scale']),
            // 100% clears the key, so the widget follows any future default
            // rather than holding a value nobody chose.
            onPick: (i) => write(
              {'scale': _scaleChoices[i] == 1.0 ? null : _scaleChoices[i]},
            ),
          ),
          _Label(text: context.t('desklets.background')),
          _Choices(
            labels: [for (final b in _backgroundChoices) context.t(b.labelKey)],
            // What is actually drawn when nothing is set: no backing on a
            // hosted widget or on a bare distro (GNOME), a card otherwise.
            selected: _nearestBackground(
              config['opacity'],
              fallback: hosted || bare ? 0 : 0.72,
            ),
            onPick: (i) => write({'opacity': _backgroundChoices[i].opacity}),
          ),
          _Label(text: context.t('desklets.backgroundColour')),
          _FillSwatches(
            accent: theme.palette.accent,
            distro: theme.palette.bar,
            wallpaper: wallpaperAccentFor(
              ref.watch(wallpaperColorsProvider).asData?.value ?? const [],
              theme.palette.bar,
            ),
            selected: config['bgColor'] as String?,
            onPick: (id) => write({
              'bgColor': id,
              // A colour on a tile with no backing would change nothing, so
              // picking one on a bare or hosted tile gives it a backing too.
              if (id != null && config['opacity'] is! num && (hosted || bare))
                'opacity': 0.62,
            }),
          ),
          // A hosted widget's accent is the app's own, so it has no row.
          if (!hosted) ...[
            _Label(text: context.t('desklets.accent')),
            _Swatches(
              themeAccent: theme.palette.accent,
              selected: config['accentHex'] as String?,
              onPick: (hex) => write({'accentHex': hex}),
            ),
          ],
        ],
      ),
    );
  }

  /// Which corner choice a stored radius corresponds to. Nearest rather than
  /// exact, so a value authored by a theme's skin still lights a button up
  /// instead of leaving all three dark.
  static int _nearestCorner(Object? raw, {double fallback = 10}) {
    final v = raw is num ? raw.toDouble() : fallback;
    var best = 0;
    for (var i = 1; i < _cornerChoices.length; i++) {
      if ((_cornerChoices[i].radius - v).abs() <
          (_cornerChoices[best].radius - v).abs()) {
        best = i;
      }
    }
    return best;
  }

  static int _nearestScale(Object? raw) {
    final v = raw is num ? raw.toDouble() : 1.0;
    var best = 0;
    for (var i = 1; i < _scaleChoices.length; i++) {
      if ((_scaleChoices[i] - v).abs() < (_scaleChoices[best] - v).abs()) {
        best = i;
      }
    }
    return best;
  }

  static int _nearestBackground(Object? raw, {double fallback = 0.72}) {
    final v = raw is num ? raw.toDouble() : fallback;
    var best = 0;
    for (var i = 1; i < _backgroundChoices.length; i++) {
      if ((_backgroundChoices[i].opacity - v).abs() <
          (_backgroundChoices[best].opacity - v).abs()) {
        best = i;
      }
    }
    return best;
  }
}

/// Turn a desklet's config into the skin overrides [DeskletFrame] reads.
///
/// Lives here rather than in the surface so the writer and the reader of these
/// three keys sit in one file. An absent key stays absent, which is what makes
/// [DeskletSkin.mergedWith] inherit the distro's value rather than overwrite it
/// with a manufactured default; that is the exact bug the skin's own doc
/// describes at length.
///
/// [accent] is the distro's accent and [wallpaper] the colour taken from the
/// wallpaper; they resolve a background colour that follows either.
DeskletSkin skinOverridesFor(
  Desklet desklet, {
  required Color accent,
  Color? wallpaper,
}) {
  final c = desklet.config;
  final bgId = c['bgColor'] is String ? c['bgColor'] as String : null;
  final bg = deskletBackgroundColour(
    bgId,
    accent: (c['accentHex'] is String ? parseColor(c['accentHex'] as String) : null) ??
        accent,
    wallpaper: wallpaper,
  );

  return DeskletSkin(
    props: {
      if (c['radius'] is num) 'radius': c['radius'],
      if (c['opacity'] is num) 'opacity': c['opacity'],
      if (c['accentHex'] is String) 'accentHex': c['accentHex'],
      if (bg != null) 'bgHex': _hexOf(bg),
      if (bgId == 'light') 'bgLight': true,
    },
  );
}

/// The clock's face. The selection shows what is DRAWN: the user's choice,
/// else the distro's default from its skin, so a distro that ships Analog
/// shows Analog picked rather than nothing.
List<Widget> _clockRows(
  BuildContext context,
  EffectiveTheme theme,
  Map<String, Object?> config,
  void Function(Map<String, Object?>) write,
) {
  final skinFace = theme.spec.desklets
      .skinFor(theme.shell, 'clock')
      .text('face', ClockFace.digital.id);
  final current = ClockFace.parse(
    config.containsKey('face') ? config['face'] as String? : skinFace,
  );
  return [
    _Label(text: context.t('desklets.face')),
    _WrapChoices(
      labels: [for (final f in ClockFace.values) context.t(f.labelKey)],
      selected: ClockFace.values.indexOf(current),
      // Picking the distro's own default clears the key, so the clock keeps
      // following the distro if its default ever changes.
      onPick: (i) => write({
        'face': ClockFace.values[i].id == skinFace
            ? null
            : ClockFace.values[i].id,
      }),
    ),
  ];
}

/// The large folder's source and size. The user's folders are listed by name
/// after the two lists the launcher keeps, home folders first.
List<Widget> _folderRows(
  BuildContext context,
  LauncherPrefs prefs,
  Map<String, Object?> config,
  void Function(Map<String, Object?>) write,
) {
  final choices = <({String label, Map<String, Object?> patch})>[
    (
      label: context.t('desklets.folder.recent'),
      patch: {'source': FolderSource.recent.id, 'folderId': null},
    ),
    (
      label: context.t('desklets.folder.frequent'),
      patch: {'source': FolderSource.frequent.id, 'folderId': null},
    ),
    for (final f in prefs.folders)
      (
        label: f.name,
        patch: {
          'source': FolderSource.folder.id,
          'folderId': f.id,
          'folderStore': 'home',
        },
      ),
    for (final f in prefs.drawerFolders)
      (
        label: f.name,
        patch: {
          'source': FolderSource.folder.id,
          'folderId': f.id,
          'folderStore': 'drawer',
        },
      ),
  ];
  final source = FolderSource.parse(config['source']);
  var selected = source == FolderSource.frequent ? 1 : 0;
  if (source == FolderSource.folder) {
    final store = config['folderStore'] == 'drawer' ? 'drawer' : 'home';
    final at = choices.indexWhere(
      (c) =>
          c.patch['folderId'] == config['folderId'] &&
          c.patch['folderStore'] == store,
    );
    // A folder deleted since keeps nothing lit rather than lighting a wrong
    // one; picking any choice repoints it.
    selected = at;
  }
  final grid = config['grid'] == 3 ? 3 : 2;
  return [
    _Label(text: context.t('desklets.folder.show')),
    _WrapChoices(
      labels: [for (final c in choices) c.label],
      selected: selected,
      onPick: (i) => write(choices[i].patch),
    ),
    _Label(text: context.t('desklets.folder.size')),
    _WrapChoices(
      labels: const ['2 x 2', '3 x 3'],
      selected: grid == 3 ? 1 : 0,
      onPick: (i) => write({'grid': i == 1 ? 3 : null}),
    ),
  ];
}

/// Chips that wrap onto more lines rather than truncating, for choices whose
/// labels are words: a face name in German or a folder the user named can be
/// longer than a segmented row has room for.
class _WrapChoices extends StatelessWidget {
  const _WrapChoices({
    required this.labels,
    required this.selected,
    required this.onPick,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final c = d.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              button: true,
              selected: i == selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(i),
                // No alignment here: an aligned Container fills its parent,
                // and in a Wrap that is the whole row.
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: i == selected ? c.accent : Colors.transparent,
                    border: Border.all(
                      color: i == selected ? c.accent : c.line,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labels[i],
                    style: d.text.caption.copyWith(
                      color: i == selected ? c.onAccent : c.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Text(
        text,
        style: d.text.label.copyWith(color: d.colors.textMuted),
      ),
    );
  }
}

/// A segmented row. Built here rather than reaching for a primitive, the same
/// call `_SuggestionRow` in folders_screen makes: it is a few tokens and a Row,
/// and it needs no configuration surface of its own.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.labels,
    required this.selected,
    required this.onPick,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final c = d.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: i == selected ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: d.text.caption.copyWith(
                        color: i == selected ? c.onAccent : c.text,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The background colour row: distro, accent, dark, light, wallpaper.
class _FillSwatches extends StatelessWidget {
  const _FillSwatches({
    required this.accent,
    required this.distro,
    required this.wallpaper,
    required this.selected,
    required this.onPick,
  });

  final Color accent;

  /// The distro's own card colour, shown on the first swatch.
  final Color distro;

  /// The wallpaper's colour, or null when it has none to offer.
  final Color? wallpaper;

  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    String labelOf(String? id) => switch (id) {
          'accent' => context.t('settings.accent'),
          'dark' => context.t('settings.dark'),
          'light' => context.t('settings.light'),
          'wallpaper' => context.t('settings.wallpaperAccent'),
          _ => context.t('settings.distro'),
        };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          for (final id in deskletBackgroundIds)
            if (id != 'wallpaper' || wallpaper != null)
              Semantics(
                button: true,
                selected: id == selected,
                label: labelOf(id),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(id),
                  child: Builder(builder: (context) {
                    final colour = deskletBackgroundColour(
                          id,
                          accent: accent,
                          wallpaper: wallpaper,
                        ) ??
                        distro;
                    return Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: id == selected ? c.text : c.line,
                          width: id == selected ? 2.5 : 1,
                        ),
                      ),
                      child: switch (id) {
                        null => Icon(Icons.auto_awesome,
                            size: 14, color: c.onAccent),
                        'wallpaper' => WallpaperAccentMark(colour: colour),
                        _ => null,
                      },
                    );
                  }),
                ),
              ),
        ],
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.themeAccent,
    required this.selected,
    required this.onPick,
  });

  final Color themeAccent;
  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          for (final hex in _accentChoices)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(hex),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    // The first swatch shows the distro's own accent, but picks
                    // NULL, so a tile set to follow keeps following when the
                    // distro changes rather than freezing today's colour.
                    color: hex == null
                        ? themeAccent
                        : (parseColor(hex) ?? themeAccent),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hex == selected ? c.text : c.line,
                      width: hex == selected ? 2.5 : 1,
                    ),
                  ),
                  child: hex == null
                      ? Icon(Icons.auto_awesome, size: 14, color: c.onAccent)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
