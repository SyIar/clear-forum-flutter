import 'package:image_picker/image_picker.dart';

class DraftAttachments {
  static Future<String> retainImage(XFile image) =>
      Future.error(UnsupportedError('Draft images require a native app'));
  static Future<XFile> restoreImage(String path) =>
      Future.error(UnsupportedError('Draft images require a native app'));
}
