import 'package:flutter/material.dart';
import 'package:g_design/g_design.dart';

import '../state/learn_model.dart';

/// One block of a guide chapter: heading, paragraph, folder path, bullet
/// list, or a note or warning. Reading type, generous line height.
class ContentBlockView extends StatelessWidget {
  const ContentBlockView({required this.block, super.key});

  final ContentBlock block;

  @override
  Widget build(BuildContext context) {
    final GDesignTheme g = GDesignTheme.of(context);
    final TextStyle reading = g.body().copyWith(height: 1.55);

    switch (block.type) {
      case 'h':
        return Padding(
          padding: const EdgeInsets.only(
            top: GDesign.space24,
            bottom: GDesign.space8,
          ),
          child: Text(block.text ?? '', style: g.headline()),
        );

      case 'p':
        return Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space16),
          child: Text(block.text ?? '', style: reading),
        );

      case 'path':
        return Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: g.fill,
              borderRadius: BorderRadius.circular(GDesign.tileRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(GDesign.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(GIcons.folder, size: 18, color: g.accentText),
                      const SizedBox(width: GDesign.space8),
                      Expanded(
                        child: Text(
                          block.name ?? '',
                          style: g.figures(
                            g.body(
                              color: g.accentText,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((block.text ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: GDesign.space4),
                    Text(block.text!, style: g.footnote()),
                  ],
                ],
              ),
            ),
          ),
        );

      case 'list':
        return Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String item in block.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: GDesign.space8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 9,
                          right: GDesign.space12,
                        ),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: g.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(child: Text(item, style: reading)),
                    ],
                  ),
                ),
            ],
          ),
        );

      case 'note':
      case 'warn':
        final bool warn = block.type == 'warn';
        return Padding(
          padding: const EdgeInsets.only(bottom: GDesign.space16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: (warn ? g.danger : g.accent).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(GDesign.tileRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(GDesign.space16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    warn ? GIcons.info : GIcons.sparkles,
                    size: 20,
                    color: warn ? g.danger : g.accentText,
                  ),
                  const SizedBox(width: GDesign.space12),
                  Expanded(child: Text(block.text ?? '', style: reading)),
                ],
              ),
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
