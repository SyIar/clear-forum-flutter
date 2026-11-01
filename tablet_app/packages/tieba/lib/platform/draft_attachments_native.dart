import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class DraftAttachments {
  static Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}${Platform.pathSeparator}draft_images')
        .create(recursive: true);
  }

  static Future<String> retainImage(XFile image) async {
    if (await image.length() > 20 * 1024 * 1024) {
      throw ArgumentError('Draft image exceeds 20 MB');
    }
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw ArgumentError('Invalid draft image size');
    }
    final extension = image.name.split('.').last.toLowerCase();
    final suffix =
        {
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'heic',
          'heif',
        }.contains(extension)
        ? extension
        : 'jpg';
    final name = '${sha256.convert(bytes)}.$suffix';
    final directory = await _directory();
    final destination = File('${directory.path}${Platform.pathSeparator}$name');
    if (!await destination.exists()) {
      await destination.writeAsBytes(bytes, flush: true);
    }
    return destination.path;
  }

  static Future<XFile> restoreImage(String path) async {
    final name = path.replaceAll('\\', '/').split('/').last;
    if (!RegExp(r'^[a-f0-9]{64}\.(jpg|jpeg|png|gif|webp|heic|heif)$')
        .hasMatch(name)) {
      throw ArgumentError('Invalid retained draft image');
    }
    final directory = await _directory();
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    if (!await file.exists()) {
      throw StateError('The draft image is no longer available');
    }
    return XFile(file.path);
  }
}
