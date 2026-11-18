import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'effects.dart';
import 'theme.dart';
import 'tokens.dart';

/// Translucent, blurred surface for floating chrome.
///
/// Falls back to the solid sheet colour under [GEffects] lite, so low-memory
/// phones keep the shape without paying for the blur.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    required this.borderRadius,
    super.key,
    this.border = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final bool lite = GEffects.liteOf(context);

    final Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: lite ? g.sheet : g.glass,
        borderRadius: borderRadius,
        border: border ? Border.all(color: g.glassBorder) : null,
      ),
      child: child,
    );
    if (lite) return surface;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GDesign.glassSigma,
          sigmaY: GDesign.glassSigma,
        ),
        child: surface,
      ),
    );
  }
}

/// 48 dp round glass button carrying one icon.
class FloatIconButton extends StatelessWidget {
  const FloatIconButton({
    required this.icon,
    required this.semanticLabel,
    super.key,
    this.onTap,
    this.color,
  });

  final IconData icon;

  /// Read aloud by screen readers. Icon-only buttons have no other name.
  final String semanticLabel;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(GDesign.touch / 2),
        child: _Tap(
          onTap: onTap,
          child: SizedBox.square(
            dimension: GDesign.touch,
            child: Icon(icon, size: 22, color: color ?? g.text),
          ),
        ),
      ),
    );
  }
}

/// Round ink response used inside glass. Kept private to the package.
class _Tap extends StatelessWidget {
  const _Tap({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: child,
      ),
    );
  }
}
