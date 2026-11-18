import 'package:flutter/widgets.dart';

/// Whether heavy effects should give way to cheap ones.
///
/// Blur behind floating chrome redraws whatever scrolls beneath it on every
/// frame. On a phone under 4 GB of RAM that is the difference between smooth
/// and stuttering, so the app wraps its tree in `GEffects(lite: true)` there
/// and every glass surface becomes solid. Absent means full effects.
class GEffects extends InheritedWidget {
  const GEffects({required this.lite, required super.child, super.key});

  final bool lite;

  static bool liteOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GEffects>()?.lite ?? false;

  @override
  bool updateShouldNotify(GEffects oldWidget) => oldWidget.lite != lite;
}
