import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../app/theme/tokens.dart';
import '../../bridge/recovery_api.g.dart';
import '../../core/format.dart';
import '../../core/messenger/g_message.dart';
import '../../core/messenger/g_messenger.dart';
import '../../ui/g_button.dart';
import '../../ui/g_thumbnail.dart';
import '../../ui/media/media_stage.dart';
import '../../ui/media/playable_media.dart';
import '../recovery/state/recovery_providers.dart';
import '../../core/i18n/g_strings.dart';

/// ONE RECOVERED ITEM, FULL SCREEN.
///
/// The recovery twin of the storage frame, and it had to be written rather than
/// shared because the two carry different types and reach the platform through
/// different bridges. Everything a user can tell apart is identical: images
/// pinch, video plays, text and CSV render, PDF renders, and anything else is
/// handed to an app that can open it.
///
/// ─── TWO THINGS THE STORAGE SIDE NEVER FACED ─────────────────────────────────
///
/// A trashed MediaStore row is hidden by IS_TRASHED, so its URI is real but some
/// OEM builds refuse to decode from it. The player is therefore allowed to fail
/// and falls through to the preview rather than sitting black.
///
/// A loose file in an app trash folder has no URI at all. It cannot be played
/// and it cannot be handed to another app without FileProvider, but it CAN be
/// read, so text and PDF still work where video does not.
class RecoveredFrame extends ConsumerWidget {
  const RecoveredFrame({required this.item, super.key});

  final RecoverableItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String mime = item.mimeType ?? '';
    final String name = item.name.toLowerCase();

    if (item.kind == 'image') return _Image(item: item);
    if (item.kind == 'video' || item.kind == 'audio') {
      return _Play(item: item);
    }

    // Mime type first where MediaStore recorded one. Extensions are the
    // fallback, because a file rescued from a trash folder frequently has no
    // recorded type at all.
    if (mime.startsWith('text/') ||
        name.endsWith('.txt') ||
        name.endsWith('.log') ||
        name.endsWith('.md') ||
        name.endsWith('.json')) {
      return _Text(item: item, table: false);
    }
    if (mime.contains('csv') || name.endsWith('.csv')) {
      return _Text(item: item, table: true);
    }
    if (mime.contains('pdf') || name.endsWith('.pdf')) {
      return _Pdf(item: item);
    }

    return _HandOff(item: item);
  }
}

class _Image extends ConsumerWidget {
  const _Image({required this.item});

  final RecoverableItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 6,
      child: Center(
        child: GThumbnail(
          itemId: item.itemId,
          bridge: ref.watch(recoveryBridgeProvider),
          kind: item.kind,
          // 2048, the largest the native thumbnailer produces. Full resolution
          // would be the original file, which for a 108 megapixel photo is a
          // decode nobody asked for.
          maxPixels: 2048,
          fit: BoxFit.contain,
          radius: 0,
        ),
      ),
    );
  }
}

/// Video and audio, played in place with the shared player.
class _Play extends ConsumerWidget {
  const _Play({required this.item});

  final RecoverableItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MediaStage(
    media: PlayableMedia.recoverable(item, ref.watch(recoveryBridgeProvider)),
    fallback: _Unplayable(item: item),
    // Clears the viewer's filmstrip and action bar.
    bottomInset: 150,
  );
}

class _Text extends ConsumerWidget {
  const _Text({required this.item, required this.table});

  final RecoverableItem item;
  final bool table;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GTokens t = context.g;
    final AsyncValue<Uint8List?> bytes = ref.watch(
      recoveredBytesProvider(item.itemId),
    );

    return bytes.when(
      loading: () => _Waiting(t: t),
      error: (Object e, StackTrace s) => _HandOff(item: item),
      data: (Uint8List? data) {
        if (data == null) return _TooBig(item: item, t: t);

        // allowMalformed, because a recovered log with one bad byte should
        // still be readable rather than thrown away whole.
        final String text = utf8.decode(data, allowMalformed: true);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GSpace.gutter,
              72,
              GSpace.gutter,
              120,
            ),
            child: table
                ? _Csv(text: text)
                : SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: GType.monoSmall.copyWith(color: t.text),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// CSV as columns.
///
/// A deliberately simple split. Quoted fields containing commas will break, and
/// that is accepted: this is a preview so someone can recognise a file, not a
/// spreadsheet engine.
class _Csv extends StatelessWidget {
  const _Csv({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final GTokens t = context.g;
    final List<String> lines = const LineSplitter()
        .convert(text)
        .where((String line) => line.trim().isNotEmpty)
        .take(200)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final List<String> header = lines.first.split(',');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 40,
          columns: <DataColumn>[
            for (final String cell in header)
              DataColumn(
                label: Text(
                  cell.trim(),
                  style: GType.micro.copyWith(color: t.text),
                ),
              ),
          ],
          rows: <DataRow>[
            for (final String line in lines.skip(1))
              DataRow(
                cells: <DataCell>[
                  for (int i = 0; i < header.length; i++)
                    DataCell(
                      Text(
                        i < line.split(',').length
                            ? line.split(',')[i].trim()
                            : '',
                        style: GType.monoSmall.copyWith(color: t.muted),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Pdf extends ConsumerStatefulWidget {
  const _Pdf({required this.item});

  final RecoverableItem item;

  @override
  ConsumerState<_Pdf> createState() => _PdfState();
}

class _PdfState extends ConsumerState<_Pdf> {
  PdfControllerPinch? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Uint8List? bytes = await ref
        .read(recoveryBridgeProvider)
        .itemBytes(widget.item.itemId, maxBytes: 10 * 1024 * 1024);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _controller = PdfControllerPinch(document: PdfDocument.openData(bytes));
    });
  }

  @override
  Widget build(BuildContext context) {
    final GTokens t = context.g;
    if (_failed) return _HandOff(item: widget.item);

    final PdfControllerPinch? controller = _controller;
    if (controller == null) return _Waiting(t: t);

    return Padding(
      padding: const EdgeInsets.only(top: 64, bottom: 96),
      child: PdfViewPinch(controller: controller),
    );
  }
}

/// A video or track that will not play here.
///
/// Distinct from the general hand-off because the reason is specific and the
/// user deserves it. A trashed file is not corrupt, and saying so stops someone
/// concluding the recovery failed when it did not.
class _Unplayable extends ConsumerWidget {
  const _Unplayable({required this.item});

  final RecoverableItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GTokens t = context.g;

    return Stack(
      children: <Widget>[
        Center(
          child: SizedBox(
            width: 240,
            height: 240,
            child: GThumbnail(
              itemId: item.itemId,
              bridge: ref.watch(recoveryBridgeProvider),
              kind: item.kind,
              maxPixels: 512,
              radius: GRadius.card,
            ),
          ),
        ),
        Positioned(
          left: GSpace.gutter,
          right: GSpace.gutter,
          bottom: 110,
          child: Text(
            context.s('Restore to play'),
            textAlign: TextAlign.center,
            style: GType.bodySmall.copyWith(color: t.muted),
          ),
        ),
      ],
    );
  }
}

class _HandOff extends ConsumerWidget {
  const _HandOff({required this.item});

  final RecoverableItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GTokens t = context.g;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.description_outlined, size: 40, color: t.dim),
            const SizedBox(height: GSpace.lg),
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GType.title.copyWith(color: t.text),
            ),
            const SizedBox(height: GSpace.sm),
            Text(
              context.s('Opens in another app'),
              textAlign: TextAlign.center,
              style: GType.bodySmall.copyWith(color: t.muted),
            ),
            const SizedBox(height: GSpace.lg),
            GButton(
              label: context.s('Open with another app'),
              icon: Icons.open_in_new_rounded,
              expand: false,
              onPressed: () async {
                final bool ok = await ref
                    .read(recoveryBridgeProvider)
                    .openItemExternally(item.itemId);
                if (!context.mounted || ok) return;
                GMessenger.show(
                  context,
                  GMessage.warning(
                    'Nothing on this phone can open that, and a file still in '
                    'the trash cannot be shared. Restore it first.',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TooBig extends StatelessWidget {
  const _TooBig({required this.item, required this.t});

  final RecoverableItem item;
  final GTokens t;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.xl),
      child: Text(
        'This file is ${GFormat.bytes(item.sizeBytes)}, too large to '
        'preview here.',
        textAlign: TextAlign.center,
        style: GType.bodySmall.copyWith(color: t.muted),
      ),
    ),
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.t});

  final GTokens t;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      context.s('Loading'),
      style: GType.monoSmall.copyWith(color: t.dim),
    ),
  );
}

/// The file itself, for text, CSV and PDF.
final recoveredBytesProvider = FutureProvider.family<Uint8List?, String>(
  (Ref ref, String itemId) =>
      ref.watch(recoveryBridgeProvider).itemBytes(itemId),
);
