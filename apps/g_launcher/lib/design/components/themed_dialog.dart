import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import 'chrome_theme.dart';
import 'glass_panel.dart';
import 'themed_button.dart';
import 'package:g_launcher/i18n/i18n.dart';

/// A themed dialog. Same route-boundary rule as [ThemedSheet]: the chrome is
/// captured before `showDialog` and re-provided inside, so the dialog matches
/// the screen behind it.
///
/// Two ways to call it: [confirm] for the common title + message + two-button
/// case, or [show] for arbitrary content.
class ThemedDialog {
  const ThemedDialog._();

  /// Arbitrary dialog content.
  ///
  /// Pass EITHER [actions] (built by the caller) OR [actionsBuilder], which
  /// receives the dialog's own [BuildContext] — use it so `Navigator.of(...)`
  /// targets THIS dialog's route, not a nested navigator the caller might sit
  /// under. [confirm] relies on this.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    Widget? content,
    List<Widget> actions = const [],
    List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
  }) {
    final data = ChromeScope.of(context);

    // ─── A SHEET, NOT A DIALOG, ON EVERY DISTRO ───────────────────────────
    //
    // Every confirm in the app comes through here, and a centred box with two
    // small buttons in its corner was the least considered surface in it: the
    // answer sat far from the thumb and the decision read as an error. A sheet
    // rises from where the hand already is, and its actions run the full
    // width, the one that goes ahead on top.
    //
    // Deliberately the same on every distro. `ThemedSheet` draws a window on
    // the desktops whose own dialogs are windows, which is right for a
    // settings page and wrong for a question that wants one tap.
    final c = data.colors;
    final top = BorderRadius.vertical(top: Radius.circular(data.panelRadius));

    return showModalBottomSheet<T>(
      context: context,
      // So a sheet holding a text field can rise with the keyboard.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      shape: RoundedRectangleBorder(borderRadius: top),
      builder: (ctx) {
        final resolvedActions = actionsBuilder?.call(ctx) ?? actions;
        return ChromeScope(
          data: data,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: GlassPanel(
              borderRadius: top,
              border: Border(top: BorderSide(color: c.lineStrong)),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GSpace.xl,
                    GSpace.md,
                    GSpace.xl,
                    GSpace.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.lineStrong,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: GSpace.lg),
                      Text(title, style: data.text.title),
                      if (content != null) ...[
                        const SizedBox(height: GSpace.md),
                        Flexible(
                          child: SingleChildScrollView(
                            child: DefaultTextStyle(
                              style: data.text.body,
                              child: content,
                            ),
                          ),
                        ),
                      ],
                      if (resolvedActions.isNotEmpty) ...[
                        const SizedBox(height: GSpace.xl),
                        // Callers list actions cancel first, the way a dialog
                        // row reads. Stacked, the one that goes ahead leads.
                        for (final (i, action)
                            in resolvedActions.reversed.indexed) ...[
                          if (i > 0) const SizedBox(height: GSpace.sm),
                          action,
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The common case: title, message, cancel + confirm. Resolves to true if
  /// confirmed, false/null otherwise. [danger] paints confirm as destructive.
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool danger = false,
  }) {
    return show<bool>(
      context,
      title: title,
      content: Text(message),
      // Built against the DIALOG context so pops hit this route.
      actionsBuilder: (dialogCtx) => [
        ThemedButton(
          label: cancelLabel ?? tr('common.cancel'),
          kind: ThemedButtonKind.text,
          expand: true,
          onPressed: () => Navigator.of(dialogCtx).pop(false),
        ),
        ThemedButton(
          label: confirmLabel ?? tr('design.confirm'),
          kind: danger ? ThemedButtonKind.danger : ThemedButtonKind.primary,
          expand: true,
          onPressed: () => Navigator.of(dialogCtx).pop(true),
        ),
      ],
    );
  }
}
