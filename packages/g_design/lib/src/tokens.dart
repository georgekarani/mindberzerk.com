import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

/// Layout, shape, type and motion constants for every Mindberzerk app.
///
/// Values are in logical pixels and were drawn on a 360 x 800 dp board, the
/// budget phone this direction is designed for first.
abstract final class GDesign {
  // Spacing.
  static const double gutter = 20;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  /// The smallest thing a thumb is asked to hit.
  static const double touch = 48;

  // Floating chrome.
  static const double navHeight = 56;

  /// Gap between the nav pill and the system gesture area.
  static const double navInset = 12;
  static const double headerHeight = 48;

  /// Gap between the status bar and the header row.
  static const double headerGap = 8;

  // Surfaces.
  static const double sheetRadius = 28;
  static const double glassSigma = 11;
  static const double rowMinHeight = 56;
  static const double buttonHeight = 52;
  static const double buttonRadius = 16;

  // Sheet stops, as fractions of the screen. The full stop is capped at the
  // bottom of the header so the sheet never slides under the back button.
  static const double sheetPeek = 0.22;
  static const double sheetHalf = 0.5;
  static const double sheetFull = 0.92;

  // Type sizes. Weights and colours come from GDesignTheme's base styles.
  static const double displayLarge = 64;
  static const double display = 56;
  static const double compact = 36;
  static const double title = 22;
  static const double headerTitle = 20;
  static const double body = 15;
  static const double caption = 13;
  static const double label = 11;

  /// 0.09 em on an 11 dp label.
  static const double labelTracking = 0.99;

  // Motion.
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 280);
  static const Curve enter = Curves.easeOutCubic;

  /// A duration that collapses to zero when the system asks for less motion.
  static Duration motion(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
