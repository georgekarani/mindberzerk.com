import 'package:flutter/material.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';

/// The only top chrome a screen has: back and title in one glass capsule,
/// actions as separate round buttons on the trailing side.
///
/// Sits [GDesign.headerGap] under the status bar. The capsule hugs its title,
/// never runs under the actions, and shrinks a long title to fit rather than
/// cutting it off.
class FloatHeader extends StatelessWidget {
  const FloatHeader({
    required this.title,
    super.key,
    this.onBack,
    this.backLabel = 'Back',
    this.tag,
    this.actions = const <Widget>[],
  });

  final String title;

  /// Shows the back button when set. Tab roots leave it null.
  final VoidCallback? onBack;

  /// Screen reader name for the back button. Pass the translated word.
  final String backLabel;

  /// Optional small marker after the title, such as a NEW pill.
  final Widget? tag;

  /// Usually [FloatIconButton]s. Kept to two so the title has room.
  final List<Widget> actions;

  /// Distance from the top of the screen to the bottom of the header row.
  /// Content that must not sit under the header starts here.
  static double extent(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      GDesign.headerGap +
      GDesign.headerHeight;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool back = onBack != null;

    final Widget capsule = GlassSurface(
      borderRadius: BorderRadius.circular(GDesign.headerHeight / 2),
      child: SizedBox(
        height: GDesign.headerHeight,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: back ? 0 : 18,
            end: 18,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (back)
                Semantics(
                  button: true,
                  label: backLabel,
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onBack,
                      child: SizedBox.square(
                        dimension: GDesign.touch,
                        // arrow_back mirrors itself in right to left layouts.
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 22,
                          color: g.text,
                        ),
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: g.sans.copyWith(
                        fontSize: GDesign.headerTitle,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: g.text,
                      ),
                    ),
                  ),
                ),
              ),
              if (tag != null) ...<Widget>[
                const SizedBox(width: GDesign.space8),
                tag!,
              ],
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + GDesign.headerGap,
        left: 12,
        right: 12,
      ),
      child: SizedBox(
        height: GDesign.headerHeight,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: capsule,
              ),
            ),
            for (final Widget action in actions) ...<Widget>[
              const SizedBox(width: GDesign.space8),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// Small NEW-style marker for [FloatHeader.tag] and hero labels.
class HeaderTag extends StatelessWidget {
  const HeaderTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: g.sans.copyWith(
            fontSize: GDesign.label,
            fontWeight: FontWeight.w700,
            color: g.accent,
          ),
        ),
      ),
    );
  }
}
