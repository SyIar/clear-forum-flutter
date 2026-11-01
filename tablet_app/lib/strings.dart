import 'dart:convert';

import 'package:flutter/services.dart';

class AppStrings {
  static Map<String, dynamic> _values = {};
  static Future<void> load() async {
    _values = jsonDecode(
      await rootBundle.loadString('assets/l10n/zh.json'),
    ) as Map<String, dynamic>;
  }

  static String text(String key) => _values[key] as String? ?? key;
  static RegExp pattern(String key) => RegExp(text(key), caseSensitive: false);
  static Map<String, int> numbers(String key) =>
      Map<String, int>.from(_values[key] as Map? ?? {});
}

String tr(String key) => AppStrings.text(key);
