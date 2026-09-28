import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'site.dart';

abstract class LibraryStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesLibraryStorage implements LibraryStorage {
  PreferencesLibraryStorage({required bool sample})
    : _key = sample ? 'reading_library_sample_v1' : 'reading_library_v1';
  final String _key;
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString(_key);
  @override
  Future<void> write(String value) => _preferences.setString(_key, value);
}

class SavedPage {
  const SavedPage({required this.url, required this.title});
  final Uri url;
  final String title;
  Map<String, String> toJson() => {'url': url.toString(), 'title': title};

  static SavedPage? fromJson(Object? value) {
    if (value is! Map || value['url'] is! String) return null;
    final url = ForumSite.resolve(
      value['url'] as String,
      ForumSite.base,
      internal: true,
    );
    if (url == null) return null;
    final title = value['title'];
    return SavedPage(url: url, title: title is String ? title : url.path);
  }
}

class ReadingLibrary extends ChangeNotifier {
  ReadingLibrary({required this.sample, LibraryStorage? storage})
    : _storage = storage ?? PreferencesLibraryStorage(sample: sample);
  static const recentLimit = 10;
  final bool sample;
  final LibraryStorage _storage;
  List<SavedPage> _bookmarks = [];
  List<SavedPage> _recent = [];
  List<SavedPage> get bookmarks => List.unmodifiable(_bookmarks);
  List<SavedPage> get recent => List.unmodifiable(_recent);
  bool loaded = false;
  bool loadFailed = false;
  bool _disposed = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();

  String _bookmarkKey(Uri url) => url.toString();
  String _recentKey(Uri url) {
    final thread = RegExp(r'^/threads/([^/]+\.\d+)(?:/|$)')
        .firstMatch(url.path);
    return thread == null
        ? url.removeFragment().toString()
        : '/threads/${thread.group(1)}/';
  }

  bool isBookmarked(Uri url) =>
      _bookmarks.any((entry) => _bookmarkKey(entry.url) == _bookmarkKey(url));

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final raw = await _storage.read();
      final data = raw == null ? null : jsonDecode(raw);
      if (data != null && (data is! Map || data['version'] != 1)) {
        throw const FormatException('Unsupported library data');
      }
      List<SavedPage> decode(Object? value, String Function(Uri) key) {
        if (value == null) return [];
        if (value is! List) throw const FormatException('Invalid library list');
        final seen = <String>{};
        return value
            .map(SavedPage.fromJson)
            .whereType<SavedPage>()
            .where((e) => seen.add(key(e.url)))
            .toList();
      }

      _bookmarks = decode(data?['bookmarks'], _bookmarkKey);
      _recent = decode(data?['recent'], _recentKey).take(recentLimit).toList();
      loaded = true;
      loadFailed = false;
    } catch (_) {
      loadFailed = true;
      _loading = null;
      rethrow;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _change(
    ({List<SavedPage> bookmarks, List<SavedPage> recent}) Function() update,
  ) {
    final next = _writes.then((_) async {
      await load();
      final value = update();
      await _storage.write(
        jsonEncode({
          'version': 1,
          'bookmarks': value.bookmarks.map((e) => e.toJson()).toList(),
          'recent': value.recent.map((e) => e.toJson()).toList(),
        }),
      );
      _bookmarks = value.bookmarks;
      _recent = value.recent;
      if (!_disposed) notifyListeners();
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> toggleBookmark(Uri url, String title) {
    if (!ForumSite.readable(url)) {
      throw const FormatException('Unsupported URL');
    }
    return _change(
      () => (
        bookmarks: isBookmarked(url)
            ? _bookmarks
                  .where((e) => _bookmarkKey(e.url) != _bookmarkKey(url))
                  .toList()
            : [SavedPage(url: url, title: title), ..._bookmarks],
        recent: _recent,
      ),
    );
  }

  Future<void> remember(ForumPage page) {
    if (!ForumSite.readable(page.url)) {
      throw const FormatException('Unsupported URL');
    }
    return _change(
      () => (
        bookmarks: _bookmarks,
        recent: [
          SavedPage(url: page.url, title: page.title),
          ..._recent.where((e) => _recentKey(e.url) != _recentKey(page.url)),
        ].take(recentLimit).toList(),
      ),
    );
  }

  Future<void> clearRecent() =>
      _change(() => (bookmarks: _bookmarks, recent: []));

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class LibraryScope extends InheritedNotifier<ReadingLibrary> {
  const LibraryScope({
    super.key,
    required ReadingLibrary library,
    required super.child,
  }) : super(notifier: library);
  static ReadingLibrary? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryScope>()?.notifier;
}
