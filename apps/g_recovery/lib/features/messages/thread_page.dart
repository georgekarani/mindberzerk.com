import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

import '../../bridge/messages_api.g.dart';
import '../../core/i18n/g_strings.dart';
import 'messages_page.dart';

/// One chat's kept messages as a thread, oldest at the top and the newest at
/// the bottom where the eye expects it.
///
/// Every bubble sits on the left: only received messages can be kept. A
/// message the sender replaced keeps its original text with a quiet note
/// under it. The design is this app's own, not a copy of any chat app.
class ThreadPage extends StatefulWidget {
  const ThreadPage({required this.chat, super.key, this.backLabel});

  final Chat chat;
  final String? backLabel;

  static Route<void> route({required Chat chat, String? backLabel}) =>
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ThreadPage(chat: chat, backLabel: backLabel),
      );

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Opens at the newest message, like any thread.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<ArchivedMessage> oldestFirst = widget.chat.messages.reversed
        .toList();
    final List<Widget> rows = <Widget>[];
    DateTime? day;
    for (int i = 0; i < oldestFirst.length; i++) {
      final ArchivedMessage m = oldestFirst[i];
      final DateTime at = DateTime.fromMillisecondsSinceEpoch(m.postedAtMillis);
      final DateTime thisDay = DateTime(at.year, at.month, at.day);
      if (day != thisDay) {
        rows.add(_DayMark(at: at));
        day = thisDay;
      }
      final ArchivedMessage? previous = i == 0 ? null : oldestFirst[i - 1];
      // A name over the first of a run from one person, in group chats only.
      final bool showSender =
          m.sender != null &&
          m.sender != widget.chat.title &&
          (previous == null ||
              previous.sender != m.sender ||
              rows.last is _DayMark);
      rows.add(_Bubble(message: m, showSender: showSender));
    }

    return LargeTitlePage(
      title: widget.chat.title,
      onBack: () => Navigator.of(context).maybePop(),
      backLabel: widget.backLabel,
      controller: _scroll,
      slivers: <Widget>[
        SliverToBoxAdapter(child: _AppLine(app: widget.chat.app)),
        SliverList.list(children: rows),
      ],
    );
  }
}

/// Which app this chat was kept from.
class _AppLine extends StatelessWidget {
  const _AppLine({required this.app});

  final String app;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        0,
        GDesign.gutter,
        GDesign.space8,
      ),
      child: Text(app, style: g.footnote()),
    );
  }
}

/// The day, centred between messages from different days.
class _DayMark extends StatelessWidget {
  const _DayMark({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space16,
        GDesign.gutter,
        GDesign.space8,
      ),
      child: Text(
        messageTime(context, at.millisecondsSinceEpoch),
        textAlign: TextAlign.center,
        style: g.footnote(weight: FontWeight.w600),
      ),
    );
  }
}

/// One received message: grey bubble on the left, the time under it, and
/// the note when the sender replaced it.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.showSender});

  final ArchivedMessage message;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final double max = MediaQuery.sizeOf(context).width * 0.76;
    final String time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(
        DateTime.fromMillisecondsSinceEpoch(message.postedAtMillis),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GDesign.gutter,
        GDesign.space4,
        GDesign.gutter,
        GDesign.space4,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 2),
                  child: Text(message.sender!, style: g.footnote()),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: g.fill,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: SelectableText(message.text, style: g.body()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 2),
                child: Text(
                  message.edited
                      ? '$time, ${context.s('deleted by sender, kept here')}'
                      : time,
                  style: g.footnote(
                    color: message.edited ? g.text : g.muted,
                    weight: message.edited ? FontWeight.w600 : FontWeight.w400,
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
