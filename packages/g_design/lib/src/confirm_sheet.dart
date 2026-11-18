import 'package:flutter/material.dart';

import 'content_sheet.dart';
import 'theme.dart';
import 'tokens.dart';

/// Asks before something that cannot be undone. Replaces AlertDialog.
///
/// Rises from the bottom like every other sheet, with the safe choice on the
/// leading side and the action on the trailing side, both full height. Resolves
/// to true only when the action was tapped; dismissing by drag, back or the
/// scrim means no.
///
/// Every string is passed in so the caller can translate it.
Future<bool> showConfirmSheet({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = true,
}) async {
  final GDesignTheme g = GDesignTheme.of(context);
  final bool? answer = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: g.sheet,
    barrierColor: g.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(GDesign.sheetRadius),
      ),
    ),
    builder: (BuildContext sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GDesign.gutter,
          0,
          GDesign.gutter,
          GDesign.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SheetHandle(),
            const SizedBox(height: GDesign.space4),
            Semantics(
              header: true,
              child: Text(
                title,
                style: g.sans.copyWith(
                  fontSize: GDesign.title,
                  height: 28 / 22,
                  fontWeight: FontWeight.w700,
                  color: g.text,
                ),
              ),
            ),
            const SizedBox(height: GDesign.space8),
            Text(
              message,
              style: g.sans.copyWith(
                fontSize: GDesign.body,
                height: 22 / 15,
                color: g.text,
              ),
            ),
            const SizedBox(height: GDesign.space24),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SheetButton(
                    label: cancelLabel,
                    background: g.raised,
                    foreground: g.text,
                    onTap: () => Navigator.of(sheetContext).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    label: confirmLabel,
                    background: destructive ? g.danger : g.accent,
                    foreground: destructive ? g.onDanger : g.onAccent,
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return answer ?? false;
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return SizedBox(
      height: GDesign.buttonHeight,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(GDesign.buttonRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: g.sans.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
