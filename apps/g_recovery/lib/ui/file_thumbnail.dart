import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bridge/storage_bridge.dart';

/// An ImageProvider for a file still on the phone, drawn by the native
/// thumbnailer at [maxPixels] on its longest side.
///
/// The storage twin of ItemThumbnail, so storage screens can use the same
/// photo widgets (cards, grid tiles, the shared zoom) as recovery screens.
@immutable
class FileThumbnail extends ImageProvider<FileThumbnail> {
  const FileThumbnail({
    required this.fileId,
    required this.bridge,
    this.kind = 'image',
    this.maxPixels = 360,
    this.name,
    this.mimeType,
  });

  final String fileId;
  final StorageBridge bridge;
  final String kind;
  final int maxPixels;
  final String? name;
  final String? mimeType;

  @override
  Future<FileThumbnail> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FileThumbnail>(this);

  @override
  ImageStreamCompleter loadImage(
    FileThumbnail key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: key.fileId,
  );

  Future<ui.Codec> _load(FileThumbnail key, ImageDecoderCallback decode) async {
    final Uint8List? bytes = await key.bridge.thumbnail(
      key.fileId,
      key.maxPixels,
      kind: key.kind,
      name: key.name,
      mimeType: key.mimeType,
    );
    if (bytes == null || bytes.isEmpty) {
      // Not cached as a failure: the file may gain a preview later.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      throw StateError('no preview for ${key.fileId}');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is FileThumbnail &&
      other.fileId == fileId &&
      other.maxPixels == maxPixels;

  @override
  int get hashCode => Object.hash(fileId, maxPixels);
}
