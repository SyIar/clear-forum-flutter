import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret application preferences; credentials belong to SessionStore.
class SettingsStore extends ChangeNotifier {
  static const _prefix = 'tieba_lite.settings.';
  SharedPreferences? _preferences;
  Future<void> _pending = Future<void>.value();

  static const defaults = <String, Object>{
    'themeMode': 'system',
    'fontFamily': 'system',
    'darkPalette': 'amoled_dark',
    'customPrimaryColor': 0xFF007AFF,
    'fontScale': 1.0,
    'hideMedia': false,
    'hideReply': false,
    'blockVideo': false,
    'hideExplore': false,
    'hideBlockedContent': false,
    'hideForumIntroAndStat': false,
    'homePageShowHistoryForum': true,
    'imageDarkenWhenNightMode': true,
    'imageLoadType': '0',
    'loadPictureWhenScroll': true,
    'listSingle': false,
    'listItemsBackgroundIntermixed': true,
    'showBothUsernameAndNickname': false,
    'showTopForumInNormalList': true,
    'showBlockTip': true,
    'showShortcutInThread': true,
    'defaultSortType': 'reply',
    'collectThreadSeeLz': true,
    'collectThreadDescSort': false,
    'autoSign': false,
    'autoSignTime': '09:00',
    'signSlowMode': true,
    'littleTail': '',
    'picWatermarkType': '2',
    'postOrReplyWarning': true,
    'originalImages': false,
    'readerMode': false,
    'notificationRefreshOnOpen': true,
  };

  Future<void> init() async {
    _preferences ??= await SharedPreferences.getInstance();
    if (!getBool('monochromeAppearanceV1')) {
      await setString('themeMode', 'system');
      await setString('darkPalette', 'amoled_dark');
      await setInt('customPrimaryColor', 0xFF007AFF);
      await setBool('monochromeAppearanceV1', true);
    }
    notifyListeners();
  }

  Object? _value(String key) =>
      _preferences?.get('$_prefix$key') ?? defaults[key];
  bool getBool(String key, {bool fallback = false}) =>
      _value(key) is bool ? _value(key)! as bool : fallback;
  String getString(String key, {String fallback = ''}) =>
      _value(key) is String ? _value(key)! as String : fallback;
  int getInt(String key, {int fallback = 0}) =>
      _value(key) is num ? (_value(key)! as num).toInt() : fallback;
  double getDouble(String key, {double fallback = 0}) =>
      _value(key) is num ? (_value(key)! as num).toDouble() : fallback;

  String get themeMode => getString('themeMode', fallback: 'system');
  String get fontFamily {
    final value = getString('fontFamily');
    return const {'system', 'notoSans'}.contains(value) ? value : 'system';
  }

  double get fontScale => getDouble('fontScale', fallback: 1).clamp(0.75, 2.0);
  bool get hideMedia => getBool('hideMedia');
  bool get hideReply => getBool('hideReply');
  bool get blockVideo => getBool('blockVideo');
  bool get hideExplore => getBool('hideExplore');
  bool get autoSign => getBool('autoSign');

  Future<void> setBool(String key, bool value) => _set(key, value);
  Future<void> setString(String key, String value) => _set(key, value);
  Future<void> setInt(String key, int value) => _set(key, value);
  Future<void> setDouble(String key, double value) => _set(key, value);

  Future<void> _set(String key, Object value) => _enqueue(() async {
    if (key.isEmpty ||
        RegExp(
          r'bduss|stoken|cookie|password|token',
          caseSensitive: false,
        ).hasMatch(key)) {
      throw ArgumentError('Invalid preference key');
    }
    final preferences = _preferences!;
    final storedKey = '$_prefix$key';
    final bool success;
    if (value is bool) {
      success = await preferences.setBool(storedKey, value);
    } else if (value is String) {
      success = await preferences.setString(storedKey, value);
    } else if (value is int) {
      success = await preferences.setInt(storedKey, value);
    } else if (value is double && value.isFinite) {
      success = await preferences.setDouble(storedKey, value);
    } else {
      throw ArgumentError('Unsupported preference value');
    }
    if (!success) throw StateError('Could not save preferences');
    notifyListeners();
  });

  Future<void> reset() => _enqueue(() async {
    for (final key in _preferences!.getKeys().where(
      (key) => key.startsWith(_prefix),
    )) {
      if (!await _preferences!.remove(key)) {
        throw StateError('Could not reset preferences');
      }
    }
    notifyListeners();
  });

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) async {
      if (_preferences == null) {
        throw StateError('SettingsStore is not initialized');
      }
      await action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
