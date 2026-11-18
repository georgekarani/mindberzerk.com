import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../../core/visibility_gate.dart';
import '../../../data/prefs/launcher_prefs.dart';
import '../../../data/prefs/prefs_repository.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../engine/desklet_skin.dart';
import '../../../engine/effective_theme.dart';
import '../../../platform/launcher_api.g.dart' show AppEntry, NowPlaying;
import '../../../system/notification_badges.dart'
    show
        badgeCountsProvider,
        notificationAccessProvider,
        openNotificationAccessSettings;
import '../../drawer/app_icon.dart';
import '../../panel/applets/clock_panel_sections.dart'
    show clockPanelMediaProvider;
import '../desklet_frame.dart';

/// Whatever is playing, with its transport. PHASE G1.
///
/// ─── NO LOOK OF ITS OWN ─────────────────────────────────────────────────────
///
/// Like the clock and the VPN tile, the distro draws it. The terminal prints
/// `playerctl metadata` through [DeskletFrame]'s own rows; card, panel and bare
/// get the player's icon, the track and the buttons in the theme's font and
/// palette. NO COLOUR CONSTANTS: the accent marks the primary button, and the
/// glyphs carry the state, so it reads in any palette.
///
/// ─── WHICH SESSION ──────────────────────────────────────────────────────────
///
/// The clock panel's policy, by reusing its provider: the one that is playing,
/// else the most recent. One answer, so the panel and the desktop never show
/// two different players at once.
///
/// ─── NO ARTWORK, NO POSITION ────────────────────────────────────────────────
///
/// The bridge carries neither, on purpose (see `NowPlaying`). The player's own
/// icon says which app this is, which is the question a launcher answers, and
/// no progress bar is drawn because there is nothing true to fill it with.
///
/// ─── REFRESHED WHILE SEEN, AND NOT OTHERWISE ────────────────────────────────
///
/// There is no session listener, deliberately: one registered callback lives
/// for the whole process and fires on every track change on the phone. So the
/// tile re-reads on a [GatedTicker], which runs only while the launcher is on
/// screen, and immediately after a button press, the one moment the state
/// certainly changed.
///
/// ─── FOUR STATES, ONE SIZE ──────────────────────────────────────────────────
///
/// Playing, paused, nothing playing and no access all keep the footprint, so
/// starting a song never makes the desktop jump. Without notification access
/// the tile offers one Allow button: it is the grant the badges already use,
/// so nothing new is asked of the person and nothing changes in Data Safety.
class NowPlayingDesklet extends ConsumerStatefulWidget {
  const NowPlayingDesklet({
    super.key,
    required this.theme,
    required this.desklet,
    required this.skin,
  });

  final EffectiveTheme theme;
  final Desklet desklet;
  final DeskletSkin skin;

  @override
  ConsumerState<NowPlayingDesklet> createState() => _NowPlayingDeskletState();
}

class _NowPlayingDeskletState extends ConsumerState<NowPlayingDesklet> {
  /// Long enough that an idle desktop costs nothing worth measuring, short
  /// enough that a track change shows before anyone wonders.
  static const _refresh = Duration(seconds: 6);

  GatedTicker? _tick;

  @override
  void initState() {
    super.initState();
    // ─── STARTED AFTER THE FIRST FRAME, NOT HERE ───────────────────────────
    //
    // The ticker fires once as it attaches (`fireOnResume`), and that tick
    // invalidates a provider. In initState the tree is still building, so the
    // invalidation marked the ProviderScope dirty mid-build and threw: first
    // seen in the desktop menu's workspace preview, which builds this tile
    // inside a LayoutBuilder. The first frame already reads fresh values, so
    // waiting for it loses nothing.
    _tick = GatedTicker(_refresh, _reread);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tick?.start();
    });
  }

  @override
  void dispose() {
    _tick?.dispose();
    super.dispose();
  }

  /// Without access there is no session to read, so ask about the grant
  /// instead: it is the one thing that can change while the tile waits, and
  /// the ticker fires on resume, which is when someone returns from granting.
  void _reread() {
    if (!mounted) return;
    final granted = ref.read(notificationAccessProvider).value ?? false;
    if (granted) {
      ref.invalidate(clockPanelMediaProvider);
    } else {
      ref.invalidate(notificationAccessProvider);
    }
  }

  Future<void> _send(NowPlaying s, String command) async {
    HapticFeedback.selectionClick();
    await ref
        .read(launcherHostApiProvider)
        .sendMediaCommand(s.packageName, command);
    if (mounted) ref.invalidate(clockPanelMediaProvider);
  }

  Future<void> _allow() async {
    HapticFeedback.selectionClick();
    // Captured first: the settings screen covers the launcher, and the tile
    // may be rebuilt before the person comes back.
    final badges = ref.read(badgeCountsProvider.notifier);
    await openNotificationAccessSettings();
    if (!mounted) return;
    // Nothing reports a grant, so both answers are asked again on return.
    ref.invalidate(notificationAccessProvider);
    ref.invalidate(clockPanelMediaProvider);
    await badges.refresh();
  }

  @override
  Widget build(BuildContext context) {
    // `.value`, not `asData`: a re-read keeps the previous answer on screen
    // instead of flashing the idle face every six seconds.
    final granted = ref.watch(notificationAccessProvider).value;
    final session =
        granted == true ? ref.watch(clockPanelMediaProvider).value : null;

    final state = granted == false
        ? _State.noAccess
        : session == null
            ? _State.idle
            : session.playing
                ? _State.playing
                : _State.paused;

    final entry = session == null ? null : _entryFor(session.packageName);

    // A player can publish its session before its metadata, so an empty
    // title falls back to the player's own name rather than a blank line.
    final String title;
    final String detail;
    if (state == _State.noAccess) {
      title = context.t('desklet_spec.nowPlaying');
      detail = context.t('nowPlaying.needsAccess');
    } else if (session == null) {
      title = context.t('nowPlaying.nothingPlaying');
      detail = '';
    } else {
      title = session.title.isNotEmpty
          ? session.title
          : (entry?.label ?? context.t('desklet_spec.nowPlaying'));
      detail = session.artist;
    }

    final view = _View(
      state: state,
      session: session,
      entry: entry,
      title: title,
      detail: detail,
    );

    final terminal = widget.skin.surface == DeskletSurface.terminal;
    return DeskletFrame(
      theme: widget.theme,
      skin: widget.skin,
      body: terminal
          ? _terminalBody(view)
          : DeskletBody(
              custom: _Player(
                theme: widget.theme,
                skin: widget.skin,
                view: view,
                compact: widget.desklet.spanY <= 1,
                onSend: _send,
                onAllow: _allow,
              ),
            ),
    );
  }

  /// The player's launcher entry, or null when it is hidden or unknown.
  ///
  /// A hidden player keeps its music on the desktop and loses its face: the
  /// hidden set is a promise that the app does not appear, and its icon on a
  /// tile would break it.
  AppEntry? _entryFor(String packageName) {
    final apps = ref.watch(appListProvider).value;
    if (apps == null) return null;
    final hidden =
        ref.watch(globalPrefsProvider).value?.hiddenApps ?? const <String>{};
    for (final a in apps) {
      if (a.packageName == packageName && !hidden.contains(a.componentKey)) {
        return a;
      }
    }
    return null;
  }

  /// On the shell the tile IS a command's output. The words are command
  /// output and stay English, like `df -h`: `playerctl` prints in English, and
  /// "No players found" is its own message when nothing is playing.
  ///
  /// Nothing playing prints that line as stderr and nothing else, which is
  /// why there is no transport then: the frame only prints [emptyNote] when
  /// a body has neither rows nor a custom widget.
  DeskletBody _terminalBody(_View v) {
    final s = v.session;
    final noAccess = v.state == _State.noAccess;
    return DeskletBody(
      command: 'playerctl metadata',
      rows: [
        if (noAccess) const DeskletRow('status', value: 'no access'),
        if (s != null && s.title.isNotEmpty) DeskletRow('title', value: s.title),
        if (s != null && s.artist.isNotEmpty)
          DeskletRow('artist', value: s.artist),
        if (s != null)
          DeskletRow(
            'status',
            value: s.playing ? 'Playing' : 'Paused',
            accent: s.playing,
          ),
      ],
      emptyNote: 'No players found',
      custom: (s == null && !noAccess)
          ? null
          : _ShellTransport(
              theme: widget.theme,
              view: v,
              onSend: _send,
              onAllow: _allow,
            ),
    );
  }
}

enum _State { playing, paused, idle, noAccess }

/// Everything one state shows, worked out once.
class _View {
  const _View({
    required this.state,
    required this.session,
    required this.entry,
    required this.title,
    required this.detail,
  });

  final _State state;
  final NowPlaying? session;
  final AppEntry? entry;
  final String title;
  final String detail;

  bool get live => session != null;
}

/// Icon, track and transport in the theme's font and palette, for the card,
/// panel and bare surfaces.
class _Player extends StatelessWidget {
  const _Player({
    required this.theme,
    required this.skin,
    required this.view,
    required this.compact,
    required this.onSend,
    required this.onAllow,
  });

  final EffectiveTheme theme;
  final DeskletSkin skin;
  final _View view;

  /// One row tall: icon, track and play or pause only.
  final bool compact;

  final Future<void> Function(NowPlaying s, String command) onSend;
  final Future<void> Function() onAllow;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final mono = skin.font == DeskletFont.mono;
    final family = mono ? theme.typography.mono : theme.typography.display;
    final bare = skin.surface == DeskletSurface.bare;
    final shadows = bare
        ? [
            Shadow(
              color: p.bgBottom.withValues(alpha: 0.55),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ]
        : null;
    final iconSize = compact ? 32.0 : 40.0;
    final titleSize = skin.num_('nowPlayingTitleSize', bare ? 17 : 15);
    final detailSize = skin.num_('rowSize', bare ? 13 : 12.5);

    final titles = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          view.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: family,
            fontSize: titleSize,
            fontWeight: FontWeight.w600,
            color: view.state == _State.idle
                ? p.onDark.withValues(alpha: 0.7)
                : p.onDark,
            shadows: shadows,
          ),
        ),
        if (!compact && view.detail.isNotEmpty)
          Text(
            view.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: family,
              fontSize: detailSize,
              color: p.onDark.withValues(alpha: 0.8),
              shadows: shadows,
            ),
          ),
      ],
    );

    final head = Row(
      children: [
        _PlayerIcon(theme: theme, skin: skin, entry: view.entry, size: iconSize),
        const SizedBox(width: 10),
        Expanded(child: titles),
        if (compact) ...[
          const SizedBox(width: 8),
          if (view.state == _State.noAccess)
            _AllowButton(theme: theme, skin: skin, onTap: onAllow)
          else
            _primary(context),
        ],
      ],
    );

    if (compact) return head;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        const SizedBox(height: 10),
        if (view.state == _State.noAccess)
          _AllowButton(theme: theme, skin: skin, onTap: onAllow)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TransportButton(
                theme: theme,
                skin: skin,
                icon: Icons.skip_previous,
                label: context.t('panel.mediaPrevious'),
                onTap: view.live && view.session!.canSkipPrevious
                    ? () => onSend(view.session!, 'previous')
                    : null,
              ),
              const SizedBox(width: 12),
              _primary(context),
              const SizedBox(width: 12),
              _TransportButton(
                theme: theme,
                skin: skin,
                icon: Icons.skip_next,
                label: context.t('panel.mediaNext'),
                onTap: view.live && view.session!.canSkipNext
                    ? () => onSend(view.session!, 'next')
                    : null,
              ),
            ],
          ),
      ],
    );
  }

  /// Play or pause, filled with the accent. Disabled with nothing playing:
  /// there is no session to resume, and a button that silently does nothing
  /// is the failure people describe as the launcher freezing.
  Widget _primary(BuildContext context) {
    final s = view.session;
    final playing = view.state == _State.playing;
    return _TransportButton(
      theme: theme,
      skin: skin,
      primary: true,
      icon: playing ? Icons.pause : Icons.play_arrow,
      label: context.t(playing ? 'panel.mediaPause' : 'panel.mediaPlay'),
      onTap: s == null ? null : () => onSend(s, playing ? 'pause' : 'play'),
    );
  }
}

/// The player's own icon, from the distro's icon pack, or a music glyph when
/// there is no player to show (idle, no access, or a hidden app).
class _PlayerIcon extends StatelessWidget {
  const _PlayerIcon({
    required this.theme,
    required this.skin,
    required this.entry,
    required this.size,
  });

  final EffectiveTheme theme;
  final DeskletSkin skin;
  final AppEntry? entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e != null) return AppIcon(entry: e, size: size, showBadge: false);

    final p = theme.palette;
    final panel = skin.surface == DeskletSurface.panel;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.onDark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(panel ? 4 : size * 0.28),
      ),
      child: Icon(
        Icons.music_note,
        size: size * 0.5,
        color: p.onDark.withValues(alpha: 0.75),
      ),
    );
  }
}

/// One transport control at a 44dp target. Primary is filled with the accent
/// on card and bare, outlined on panel the way a waybar button is.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.theme,
    required this.skin,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final EffectiveTheme theme;
  final DeskletSkin skin;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final panel = skin.surface == DeskletSurface.panel;
    final enabled = onTap != null;
    final filled = primary && !panel;
    final ink = filled ? p.bgBottom : (primary ? p.accent : p.onDark);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: filled ? p.accent : null,
              border: primary && panel ? Border.all(color: p.accent) : null,
              borderRadius:
                  BorderRadius.circular(panel ? skin.num_('radius', 4) : 22),
            ),
            child: Icon(icon, size: 22, color: ink),
          ),
        ),
      ),
    );
  }
}

/// The one action without access: open Android's notification access page.
class _AllowButton extends StatelessWidget {
  const _AllowButton({
    required this.theme,
    required this.skin,
    required this.onTap,
  });

  final EffectiveTheme theme;
  final DeskletSkin skin;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final panel = skin.surface == DeskletSurface.panel;
    final label = context.t('nowPlaying.allow');
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: panel ? null : p.accent,
            border: panel ? Border.all(color: p.accent) : null,
            borderRadius: BorderRadius.circular(
              panel ? 0 : skin.num_('radius', 10) * 0.7,
            ),
          ),
          child: Text(
            panel ? label.toLowerCase() : label,
            style: TextStyle(
              fontFamily:
                  panel ? theme.typography.mono : theme.typography.display,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: panel ? p.accent : p.bgBottom,
            ),
          ),
        ),
      ),
    );
  }
}

/// `[ prev ] [ pause ] [ next ]` under the shell output, or `[ allow ]`.
class _ShellTransport extends StatelessWidget {
  const _ShellTransport({
    required this.theme,
    required this.view,
    required this.onSend,
    required this.onAllow,
  });

  final EffectiveTheme theme;
  final _View view;
  final Future<void> Function(NowPlaying s, String command) onSend;
  final Future<void> Function() onAllow;

  @override
  Widget build(BuildContext context) {
    if (view.state == _State.noAccess) {
      return _ShellButton(
        theme: theme,
        word: 'allow',
        label: context.t('nowPlaying.allow'),
        onTap: onAllow,
      );
    }

    final s = view.session;
    if (s == null) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      children: [
        if (s.canSkipPrevious)
          _ShellButton(
            theme: theme,
            word: 'prev',
            label: context.t('panel.mediaPrevious'),
            onTap: () => onSend(s, 'previous'),
          ),
        _ShellButton(
          theme: theme,
          word: s.playing ? 'pause' : 'play',
          label: context.t(s.playing ? 'panel.mediaPause' : 'panel.mediaPlay'),
          accent: true,
          onTap: () => onSend(s, s.playing ? 'pause' : 'play'),
        ),
        if (s.canSkipNext)
          _ShellButton(
            theme: theme,
            word: 'next',
            label: context.t('panel.mediaNext'),
            onTap: () => onSend(s, 'next'),
          ),
      ],
    );
  }
}

/// One bracketed word at a 44dp target. [word] is the command, in English;
/// [label] is what a screen reader says, in the reader's language.
class _ShellButton extends StatelessWidget {
  const _ShellButton({
    required this.theme,
    required this.word,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final EffectiveTheme theme;
  final String word;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(
                '[ $word ]',
                style: TextStyle(
                  fontFamily: theme.typography.mono,
                  fontSize: 13,
                  color: accent
                      ? theme.palette.accent
                      : theme.palette.onDark.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ),
      );
}
