import 'package:flutter/widgets.dart';

import '../../bridge/recovery_api.g.dart';
import '../../bridge/recovery_bridge.dart';
import '../../bridge/storage_api.g.dart';
import '../../bridge/storage_bridge.dart';
import '../file_thumbnail.dart';
import '../g_thumbnail.dart';

/// Something that can be played: a deleted item or a file still on the
/// phone, with a way to find its content URI only when playback starts.
@immutable
class PlayableMedia {
  const PlayableMedia({
    required this.id,
    required this.kind,
    required this.title,
    required this.resolve,
    this.art,
    this.durationMillis,
  });

  /// A recoverable item, played from wherever the phone keeps it.
  factory PlayableMedia.recoverable(
    RecoverableItem item,
    RecoveryBridge bridge,
  ) => PlayableMedia(
    id: 'item:${item.itemId}',
    kind: item.kind == 'video' ? 'video' : 'audio',
    title: item.name,
    resolve: () => bridge.itemUri(item.itemId),
    art: ItemThumbnail(itemId: item.itemId, bridge: bridge, maxPixels: 720),
    durationMillis: item.durationMillis,
  );

  /// A file still on the phone.
  factory PlayableMedia.storageFile(StorageFile file, StorageBridge bridge) =>
      PlayableMedia(
        id: 'file:${file.fileId}',
        kind: _isVideo(file.kind, file.mimeType) ? 'video' : 'audio',
        title: file.name,
        resolve: () => bridge.contentUri(file.fileId),
        art: FileThumbnail(
          fileId: file.fileId,
          bridge: bridge,
          kind: file.kind,
          name: file.name,
          mimeType: file.mimeType,
          maxPixels: 720,
        ),
        durationMillis: file.durationMillis,
      );

  /// Stable across rebuilds; one id plays at a time app-wide.
  final String id;

  /// 'video' or 'audio'.
  final String kind;
  final String title;

  /// Looks up the content URI; null when the phone will not hand one out.
  final Future<String?> Function() resolve;

  /// A still to show before playing, and as the cover for audio.
  final ImageProvider? art;
  final int? durationMillis;

  bool get isVideo => kind == 'video';

  /// Whether a kind and mime type describe something this player handles.
  static bool canPlay(String kind, String? mime) =>
      kind == 'video' ||
      kind == 'audio' ||
      (mime ?? '').startsWith('video/') ||
      (mime ?? '').startsWith('audio/');

  static bool _isVideo(String kind, String? mime) =>
      kind == 'video' || (mime ?? '').startsWith('video/');

  @override
  bool operator ==(Object other) => other is PlayableMedia && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
