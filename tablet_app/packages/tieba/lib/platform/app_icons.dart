import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS alternate icon names are bundled assets, never downloaded paths.
class AppIcons {
  static const _channel = MethodChannel('org.tblite.flutter/app_icons');
  static const choices = ['default', 'blue', 'dark'];
  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> supported() async {
    if (!_isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String> current() async {
    if (!_isIOS) return 'default';
    final value = await _channel.invokeMethod<String>('current');
    return choices.contains(value) ? value! : 'default';
  }

  static Future<void> set(String choice) async {
    if (!choices.contains(choice)) throw ArgumentError('Unknown icon choice');
    if (!await supported()) {
      throw UnsupportedError('Alternate icons require iOS');
    }
    await _channel.invokeMethod<void>('set', choice);
  }
}
