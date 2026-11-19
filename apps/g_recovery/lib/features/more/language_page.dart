import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_design/g_design.dart';

import '../../core/i18n/g_strings.dart';

/// Every language the app speaks, each in its own name, with the phone's
/// own languages offered first.
class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (BuildContext context) => const LanguagePage(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String current = ref.watch(gLocaleProvider);
    final List<GLanguage> suggested = GLanguage.suggested(
      View.of(context).platformDispatcher.locales,
    );

    void select(GLanguage language) {
      Haptics.select();
      ref.read(gLocaleProvider.notifier).select(language.code);
    }

    Widget row(GLanguage language) => _LanguageRow(
      language: language,
      selected: language.code == current,
      onTap: () => select(language),
    );

    return LargeTitlePage(
      title: context.s('Language'),
      backLabel: context.s('More'),
      onBack: () => Navigator.of(context).pop(),
      grouped: true,
      slivers: <Widget>[
        if (suggested.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: GDesign.space24),
              child: GroupedSection(
                header: context.s('From your phone settings'),
                children: <Widget>[for (final GLanguage l in suggested) row(l)],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: GDesign.space32),
            child: GroupedSection(
              header: context.s('All languages'),
              children: <Widget>[
                for (final GLanguage l in GLanguage.all) row(l),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A language in its own name, its English name under it when different,
/// and a check on the one in use.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final GLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return ListRow(
      title: language.nativeName,
      subtitle: language.nativeName == language.englishName
          ? null
          : language.englishName,
      trailing: selected
          ? Icon(GIcons.check, size: 20, color: g.accentText)
          : const SizedBox(width: 20),
      onTap: onTap,
    );
  }
}
