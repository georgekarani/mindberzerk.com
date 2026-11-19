import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../bridge/messages_api.g.dart';
import '../../core/format.dart';
import '../../core/i18n/g_strings.dart';
import 'state/messages_providers.dart';
import 'thread_page.dart';

/// The message archive as a list of chats, newest first, the way a phone's
/// own messages app shows them. Pills along the top filter by app once more
/// than one app has been kept. A chat opens into its thread.
///
/// Only received messages exist here: they were copied from notifications as
/// they arrived. A removed notification is not proof of deletion, so only an
/// edited message (the sender replaced it) is ever called deleted.
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key, this.backLabel});

  final String? backLabel;

  static Route<void> route({String? backLabel}) => MaterialPageRoute<void>(
    builder: (BuildContext context) => MessagesPage(backLabel: backLabel),
  );

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  /// The app filter, by package name. Null shows every app.
  String? _app;

  @override
  Widget build(BuildContext context) {
    final MessageCapture? capture = ref.watch(messageCaptureProvider).value;
    final List<ArchivedMessage> all =
        ref.watch(archivedMessagesProvider).value ?? const <ArchivedMessage>[];

    final Map<String, String> apps = <String, String>{
      for (final ArchivedMessage m in all) m.packageName: m.appLabel,
    };
    final String? app = apps.containsKey(_app) ? _app : null;
    final List<ArchivedMessage> shown = app == null
        ? all
        : all.where((ArchivedMessage m) => m.packageName == app).toList();
    final List<Chat> chats = Chat.group(shown);

    return LargeTitlePage(
      title: context.s('Messages'),
      onBack: () => Navigator.of(context).maybePop(),
      backLabel: widget.backLabel,
      actions: <Widget>[
        NavAction.icon(
          icon: GIcons.more,
          semanticLabel: context.s('More options'),
          onTap: () => _options(context, capture, all.isNotEmpty),
        ),
      ],
      pinned: apps.length > 1
          ? ChoicePills<String?>(
              options: <(String?, String)>[
                (null, context.s('All')),
                for (final MapEntry<String, String> e in apps.entries)
                  (e.key, e.value),
              ],
              value: app,
              onChanged: (String? next) => setState(() => _app = next),
            )
          : null,
      pinnedExtent: apps.length > 1 ? ChoicePills.extent : 0,
      onRefresh: () async {
        ref.invalidate(messageCaptureProvider);
        ref.invalidate(archivedMessagesProvider);
        await ref.read(archivedMessagesProvider.future);
      },
      slivers: <Widget>[
        if (all.isEmpty)
          SliverToBoxAdapter(child: _Intro(capture: capture))
        else ...<Widget>[
          SliverToBoxAdapter(
            child: _Summary(messages: shown, chats: chats),
          ),
          SliverList.builder(
            itemCount: chats.length,
            itemBuilder: (BuildContext context, int i) => _ChatRow(
              chat: chats[i],
              last: i == chats.length - 1,
              onTap: () => Navigator.of(context).push(
                ThreadPage.route(
                  chat: chats[i],
                  backLabel: context.s('Messages'),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Capture on or off, how it works, and deleting the archive.
  Future<void> _options(
    BuildContext context,
    MessageCapture? capture,
    bool hasArchive,
  ) {
    return presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final MessageCapture? now =
              ref.watch(messageCaptureProvider).value ?? capture;
          final bool listener = now?.listenerEnabled ?? false;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: GDesign.space16),
            children: <Widget>[
              GroupedSection(
                children: <Widget>[
                  if (listener)
                    ListRow(
                      icon: GIcons.messages,
                      title: context.s('Keep new messages'),
                      trailing: ToggleSwitch(
                        value: now?.capturing ?? false,
                        semanticLabel: context.s('Keep new messages'),
                        onChanged: (bool value) async {
                          await ref
                              .read(messagesBridgeProvider)
                              .setCapturing(value: value);
                          ref.invalidate(messageCaptureProvider);
                        },
                      ),
                    )
                  else
                    ListRow(
                      icon: GIcons.bell,
                      title: context.s('Allow notification access'),
                      onTap: () => _allow(ref),
                    ),
                  ListRow(
                    icon: GIcons.info,
                    title: context.s('How this works'),
                    onTap: () {
                      Navigator.of(sheet).pop();
                      _howItWorks(context);
                    },
                  ),
                ],
              ),
              if (hasArchive) ...<Widget>[
                const SizedBox(height: GDesign.space24),
                GroupedSection(
                  children: <Widget>[
                    ListRow(
                      icon: GIcons.trash,
                      title: context.s('Delete the archive'),
                      destructive: true,
                      onTap: () {
                        Navigator.of(sheet).pop();
                        _confirmClear(context);
                      },
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Future<void> _allow(WidgetRef ref) async {
    await ref.read(messagesBridgeProvider).openListenerSettings();
    ref.invalidate(messageCaptureProvider);
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bool go = await showConfirmSheet(
      context: context,
      title: context.s('Delete the archive'),
      message: context.s(
        'Everything kept so far leaves this phone for good. Capture stays on, '
        'so new messages begin a fresh archive.',
      ),
      confirmLabel: context.s('Delete'),
      cancelLabel: context.s('Keep'),
    );
    if (!go) return;
    Haptics.destroy();
    await ref.read(messagesBridgeProvider).clear();
    ref.invalidate(archivedMessagesProvider);
    ref.invalidate(messageCaptureProvider);
  }

  void _howItWorks(BuildContext context) {
    presentSheet<void>(
      context: context,
      builder: (BuildContext sheet) {
        final GDesignTheme g = GDesignTheme.of(sheet);
        Widget para(String text, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space12),
          child: Text(
            text,
            style: strong ? g.headline() : g.body(color: g.muted),
          ),
        );
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            GDesign.gutter,
            GDesign.space8,
            GDesign.gutter,
            GDesign.space24,
          ),
          children: <Widget>[
            Text(context.s('How this works'), style: g.title2()),
            const SizedBox(height: GDesign.space12),
            para(
              context.s(
                'Android hands every arriving message to this app as a '
                'notification. G Recovery writes that text down. If the sender '
                'deletes the message afterwards, your copy is still here.',
              ),
            ),
            para(context.s('What it cannot do'), strong: true),
            para(
              context.s(
                'Nothing from before you switch it on. No copy of those '
                'messages exists anywhere for this app to find.',
              ),
            ),
            para(
              context.s(
                'Text only. A photo arrives as the word Photo, so a view '
                'once image cannot be kept this way.',
              ),
            ),
            para(
              context.s(
                'Nothing from a muted chat, because a muted chat posts no '
                'notification at all.',
              ),
            ),
            para(context.s('Messaging apps only'), strong: true),
            para(
              context.s(
                'WhatsApp, Telegram, Instagram, Messenger and Messages. Every '
                'other notification, including bank alerts and sign in codes, '
                'is discarded before it is written down.',
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One chat: every kept message from one conversation in one app.
@immutable
class Chat {
  const Chat({
    required this.title,
    required this.app,
    required this.package,
    required this.conversation,
    required this.messages,
  });

  /// Splits an archive (newest first) into chats, newest chat first.
  static List<Chat> group(List<ArchivedMessage> messages) {
    final Map<String, List<ArchivedMessage>> byChat =
        <String, List<ArchivedMessage>>{};
    for (final ArchivedMessage m in messages) {
      final String title = m.conversation ?? m.sender ?? m.appLabel;
      byChat
          .putIfAbsent(
            '${m.packageName}\u0000$title',
            () => <ArchivedMessage>[],
          )
          .add(m);
    }
    final List<Chat> chats = <Chat>[
      for (final List<ArchivedMessage> list in byChat.values)
        Chat(
          title:
              list.first.conversation ??
              list.first.sender ??
              list.first.appLabel,
          app: list.first.appLabel,
          package: list.first.packageName,
          conversation: list.first.conversation,
          messages: List<ArchivedMessage>.unmodifiable(list),
        ),
    ];
    chats.sort(
      (Chat a, Chat b) =>
          b.latest.postedAtMillis.compareTo(a.latest.postedAtMillis),
    );
    return chats;
  }

  final String title;
  final String app;
  final String package;

  /// The title the notification carried, for asking the archive for more.
  final String? conversation;

  /// Newest first.
  final List<ArchivedMessage> messages;

  ArchivedMessage get latest => messages.first;

  /// Messages the sender replaced after they arrived.
  int get deleted => messages.where((ArchivedMessage m) => m.edited).length;
}

/// "Today 14:32" for today, the day otherwise.
String messageTime(BuildContext context, int millis) {
  final DateTime at = DateTime.fromMillisecondsSinceEpoch(millis);
  final DateTime now = DateTime.now();
  final bool today =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return today
      ? MaterialLocalizations.of(
          context,
        ).formatTimeOfDay(TimeOfDay.fromDateTime(at))
      : GFormat.relativeDay(at, now);
}

/// How much is kept, and how much of it the senders took back.
class _Summary extends StatelessWidget {
  const _Summary({required this.messages, required this.chats});

  final List<ArchivedMessage> messages;
  final List<Chat> chats;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int deleted = messages.where((ArchivedMessage m) => m.edited).length;
    final String kept = context.s1('{} kept', GFormat.count(messages.length));
    final String from = chats.length == 1
        ? context.s('from 1 chat')
        : context.s1('from {} chats', GFormat.count(chats.length));
    final String line = deleted == 0
        ? '$kept $from'
        : '$kept $from. ${context.s1('{} deleted by sender', GFormat.count(deleted))}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space4,
        GDesign.gutter,
        GDesign.space12,
      ),
      child: Text(line, style: g.figures(g.footnote())),
    );
  }
}

/// A chat in the list: initial, name, the newest message and when.
class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.last, required this.onTap});

  final Chat chat;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final int deleted = chat.deleted;
    final String initial = chat.title.trim().isEmpty
        ? '?'
        : chat.title.trim().characters.first.toUpperCase();

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: GDesign.gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: GDesign.space12),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: g.fill,
                    shape: BoxShape.circle,
                  ),
                  child: Text(initial, style: g.headline(color: g.muted)),
                ),
              ),
              const SizedBox(width: GDesign.space12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    GDesign.space12,
                    GDesign.gutter,
                    GDesign.space12,
                  ),
                  decoration: BoxDecoration(
                    border: last
                        ? null
                        : Border(
                            bottom: BorderSide(color: g.hairline, width: 0.5),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: g.headline(),
                            ),
                          ),
                          const SizedBox(width: GDesign.space8),
                          Text(
                            messageTime(context, chat.latest.postedAtMillis),
                            style: g.footnote(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        chat.latest.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: g.footnote(),
                      ),
                      const SizedBox(height: GDesign.space4),
                      Text(
                        deleted == 0
                            ? chat.app
                            : '${chat.app}, ${context.s1('{} deleted by sender', GFormat.count(deleted))}',
                        style: g.footnote(
                          color: deleted == 0 ? g.muted : g.text,
                          weight: deleted == 0
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Before anything is kept: what this does, and the one action that starts
/// it.
class _Intro extends ConsumerWidget {
  const _Intro({required this.capture});

  final MessageCapture? capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool listener = capture?.listenerEnabled ?? false;
    final bool capturing = capture?.capturing ?? false;
    final bool running = listener && capturing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space8,
        GDesign.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            running
                ? context.s('Listening. Nothing yet.')
                : context.s('Keep deleted messages'),
            style: g.headline(),
          ),
          if (!running) ...<Widget>[
            const SizedBox(height: GDesign.space16),
            PrimaryButton(
              label: listener
                  ? context.s('Start keeping messages')
                  : context.s('Allow notification access'),
              onTap: () async {
                if (listener) {
                  await ref
                      .read(messagesBridgeProvider)
                      .setCapturing(value: true);
                } else {
                  await ref.read(messagesBridgeProvider).openListenerSettings();
                }
                ref.invalidate(messageCaptureProvider);
              },
            ),
          ],
        ],
      ),
    );
  }
}
