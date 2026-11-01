import '../tablet_bridge.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

class MediaActions {
  static bool get canSaveToPhotos =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Saves only after a user action and the system photo permission dialog.
  static Future<void> saveImage(String url) async {
    if (TabletBridge.download != null) {
      await TabletBridge.download!(url);
      return;
    }
    if (!canSaveToPhotos) {
      throw UnsupportedError('Photo library saving requires a native app');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('An HTTPS image URL is required');
    }
    if (!await Gal.requestAccess()) {
      throw StateError('Photo library access was not granted');
    }
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
        responseType: ResponseType.bytes,
      ),
    );
    final cancelToken = CancelToken();
    try {
      final response = await client.get<List<int>>(
        uri.toString(),
        options: Options(
          headers: {'Referer': 'https://tieba.baidu.com/'},
          followRedirects: true,
          maxRedirects: 4,
        ),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (received > 50 * 1024 * 1024 || total > 50 * 1024 * 1024) {
            cancelToken.cancel('Image exceeds the download size limit');
          }
        },
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw StateError('The image response is empty');
      }
      final type = response.headers.value('content-type')?.toLowerCase() ?? '';
      if (!type.startsWith('image/') && type != 'application/octet-stream') {
        throw StateError('The response is not an image');
      }
      await Gal.putImageBytes(
        Uint8List.fromList(data),
        name: 'tieba_${DateTime.now().millisecondsSinceEpoch}',
      );
    } finally {
      client.close(force: true);
    }
  }
}
