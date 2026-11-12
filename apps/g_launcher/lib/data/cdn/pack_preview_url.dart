/// Where a pack's display-only files can be read from.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/pack_api.g.dart';
import 'pack_repository.dart';

/// One native handle for the lookup: a new Pigeon wrapper per card is a new
/// codec instance for no reason.
final _api = PackHostApi();

/// Where a pack's preview.png can be drawn from, or null when it has none.
///
/// Installed copies win (`file://`), otherwise the CDN copy beside the pack's
/// signed files. Watches the catalogue so the URL flips to the installed copy
/// the moment an install lands. A channel failure is "no preview", never an
/// error: a store card must render something whatever the bridge is doing.
final packPreviewUrlProvider =
    FutureProvider.family<String?, String>((ref, packId) async {
  ref.watch(catalogueProvider);
  try {
    return await _api.packPreviewUrl(packId);
  } catch (_) {
    return null;
  }
});

/// The CDN folder a pack's files live in, with a trailing slash, or null.
///
/// Derived from [packPreviewUrlProvider], which already knows the pack's
/// versioned path, so the store can show other display-only files (the store
/// screenshots) without another platform method. Null when the answer is a
/// local file, because then the caller should read the installed copy.
final packCdnFolderProvider =
    FutureProvider.family<String?, String>((ref, packId) async {
  final url = await ref.watch(packPreviewUrlProvider(packId).future);
  if (url == null || url.startsWith('file://')) return null;
  final slash = url.lastIndexOf('/');
  return slash < 0 ? null : url.substring(0, slash + 1);
});
