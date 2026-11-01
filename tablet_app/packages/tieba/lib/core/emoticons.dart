import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TiebaEmoticon {
  const TiebaEmoticon({required this.id, required this.name});
  final String id, name;
  String get token => '#($name)';
  String get url => 'https://tieba.baidu.com/tb/editor/images/client/$id.png';
  String get imageUrl => url;
  String? get assetPath => assetForId(id);

  static String? assetForId(String id) {
    final normalized = id == 'image_emoticon' ? 'image_emoticon1' : id;
    final number = int.tryParse(normalized.replaceFirst('image_emoticon', ''));
    if (!RegExp(r'^image_emoticon[0-9]+$').hasMatch(normalized)) return null;
    if (number != null && ((number >= 1 && number <= 50) || number == 89)) {
      return 'assets/emoticons/$normalized.webp';
    }
    if ({61, 77, 78, 79, 80, 81, 82, 83, 84}.contains(number)) {
      return 'assets/emoticons/$normalized.png';
    }
    return null;
  }
}

/// Canonical token names are localized resources and must not be translated.
class EmoticonCatalog {
  EmoticonCatalog();
  static final instance = EmoticonCatalog();
  static const _asset = 'assets/l10n/emoticons_zh.arb';
  static const _cacheKey = 'tieba_lite.emoticons.learned.v1';
  final Map<String, TiebaEmoticon> _items = {};
  final Map<String, String> _learned = {};
  Future<void>? _loading;
  Future<void> _persisting = Future<void>.value();

  List<TiebaEmoticon> get items {
    final result = _items.values.toList()
      ..sort((left, right) => _number(left.id).compareTo(_number(right.id)));
    return List.unmodifiable(result);
  }

  TiebaEmoticon? byId(String id) =>
      _items[id == 'image_emoticon' ? 'image_emoticon1' : id];

  TiebaEmoticon? byName(String name) {
    for (final item in _items.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  TiebaEmoticon? fromToken(String token) {
    if (!token.startsWith('#(') || !token.endsWith(')')) return null;
    return byName(token.substring(2, token.length - 1));
  }

  Future<void> load({AssetBundle? bundle}) =>
      _loading ??= _load(bundle ?? rootBundle)
          .catchError((Object error, StackTrace stack) {
            _loading = null;
            Error.throwWithStackTrace(error, stack);
          });

  Future<void> _load(AssetBundle bundle) async {
    final decoded = jsonDecode(await bundle.loadString(_asset));
    if (decoded is! Map) {
      throw const FormatException('Invalid emoticon resource');
    }
    final beforeLoading = Map<String, String>.of(_learned);
    for (final entry in decoded.entries) {
      final id = entry.key.toString();
      final name = entry.value;
      if (name is String && _valid(id, name)) {
        _items[id] = TiebaEmoticon(id: id, name: name);
      }
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_cacheKey);
      if (raw != null) {
        final values = jsonDecode(raw);
        if (values is Map) {
          for (final entry in values.entries.take(1024)) {
            if (entry.value is String) {
              _register(entry.key.toString(), entry.value as String);
            }
          }
        }
      }
    } catch (_) {
      // A cache failure must not remove the bundled catalog.
    }
    for (final entry in beforeLoading.entries) {
      _register(entry.key, entry.value);
    }
  }

  /// Called only with the ID and caption returned by Tieba content responses.
  void register(String id, String name) {
    if (!_register(id, name)) return;
    _persisting = _persisting
        .then((_) async {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(_cacheKey, jsonEncode(_learned));
        })
        .catchError((Object _) {
          // Learned labels are a disposable cache, not account data.
        });
    unawaited(_persisting);
  }

  bool _register(String id, String name) {
    final normalized = id == 'image_emoticon' ? 'image_emoticon1' : id;
    if (!_valid(normalized, name) ||
        _items.containsKey(normalized) ||
        byName(name) != null ||
        _learned.length >= 1024) {
      return false;
    }
    _items[normalized] = TiebaEmoticon(id: normalized, name: name);
    _learned[normalized] = name;
    return true;
  }

  static bool _valid(String id, String name) =>
      RegExp(r'^image_emoticon[1-9][0-9]{0,3}$').hasMatch(id) &&
      name.isNotEmpty &&
      name.length <= 48 &&
      !RegExp(r'[()#\r\n\x00-\x1f]').hasMatch(name);

  static int _number(String id) =>
      int.tryParse(id.replaceFirst('image_emoticon', '')) ?? 0;
}

Future<List<TiebaEmoticon>> loadEmoticons() async {
  await EmoticonCatalog.instance.load();
  return EmoticonCatalog.instance.items;
}
