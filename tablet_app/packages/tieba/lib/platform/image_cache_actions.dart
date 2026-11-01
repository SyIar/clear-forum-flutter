import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ImageCacheActions {
  /// Bytes in indexed image files, excluding documents and reply drafts.
  /// Browser-managed storage cannot be inspected by the preview.
  static Future<int?> sizeBytes() async {
    if (kIsWeb) return null;
    final manager = CachedNetworkImageProvider.defaultCacheManager;
    if (manager is! CacheManager) return null;
    // Wait for the repository already owned and initialized by this manager.
    await manager.store.getCacheSize();
    final entries = await manager.config.repo.getAllObjects();
    final paths = <String>{};
    var size = 0;
    for (final entry in entries) {
      if (!paths.add(entry.relativePath)) continue;
      final file = await manager.config.fileSystem.createFile(
        entry.relativePath,
      );
      try {
        if (await file.exists()) size += await file.length();
      } on Exception {
        // A cache eviction may remove an image while the size is being read.
        if (await file.exists()) rethrow;
      }
    }
    return size;
  }

  static Future<void> clear() async {
    if (!kIsWeb) {
      await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
    }
    final memory = PaintingBinding.instance.imageCache;
    memory.clear();
    memory.clearLiveImages();
  }
}
