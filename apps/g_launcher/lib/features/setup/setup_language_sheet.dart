import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/i18n.dart';
import 'setup_sheet.dart';

/// Board 1a, the language sheet over Hello.
///
/// A sheet, not a page, so the wallpaper stays in view and choosing a language
/// is visibly a detail of this screen rather than a step of the flow.
Future<void> showSetupLanguageSheet(
  BuildContext context, {
  required SetupInk ink,
}) {
  // A modal route sits outside the screen's text style, so the distro's face
  // is carried across explicitly rather than falling back to the app default.
  final family = DefaultTextStyle.of(context).style.fontFamily;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x33000000),
    builder: (_) => DefaultTextStyle.merge(
      style: TextStyle(fontFamily: family),
      child: _LanguageSheet(ink: ink, family: family),
    ),
  );
}

class _LanguageSheet extends ConsumerStatefulWidget {
  const _LanguageSheet({required this.ink, this.family});

  final SetupInk ink;

  /// The distro's typeface, for the search field, which does not inherit it.
  final String? family;

  @override
  ConsumerState<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends ConsumerState<_LanguageSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Matches either name, so "Swahili" finds Kiswahili and "Kiswahili" does too.
  bool _matches(AppLocale l, String q) =>
      q.isEmpty ||
      l.nativeName.toLowerCase().contains(q) ||
      l.englishName.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final ink = widget.ink;
    final i18n = ref.watch(i18nProvider);
    final active = i18n.selectedCode ?? i18n.translations.code;
    final all = localesForDisplay();

    // The active language first, so it is always on screen when the sheet
    // opens, then the rest in their display order.
    final ordered = [
      ...all.where((l) => l.code == active),
      ...all.where((l) => l.code != active),
    ];
    final q = _query.text.trim().toLowerCase();
    final shown = [
      for (final l in ordered)
        if (_matches(l, q)) l,
    ];

    final height = MediaQuery.sizeOf(context).height * 0.82;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: ink.scrim.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SetupGrip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: SetupHeading(
                ink: ink,
                kicker: ref.t('setup.language.kicker'),
                title: ref.t('setup.language.title'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: ink.text,
                  fontSize: 15,
                  fontFamily: widget.family,
                ),
                cursorColor: ink.accent,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0x14FFFFFF),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 18, color: ink.textMuted),
                  hintText: ref.t(
                    'setup.language.search',
                    {'n': '${all.length}'},
                  ),
                  hintStyle: TextStyle(color: ink.textMuted, fontSize: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        ref.t('setup.language.none'),
                        style: TextStyle(color: ink.textMuted, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 12,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final l = shown[i];
                        return SetupChoiceRow(
                          ink: ink,
                          title: l.nativeName,
                          subtitle: l.englishName == l.nativeName
                              ? null
                              : l.englishName,
                          selected: l.code == active,
                          onTap: () {
                            ref.read(i18nProvider.notifier).select(l);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
