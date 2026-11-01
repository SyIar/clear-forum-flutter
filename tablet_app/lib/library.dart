import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LibraryStore extends ChangeNotifier {
  LibraryStore(this.preferences) {
    bookmarks.addAll(_read('bookmarks'));
    history.addAll(_read('history'));
    offline.addAll(_read('offline'));
    textSize = preferences.getDouble('textSize') ?? 19;
  }
  final SharedPreferences preferences;
  final List<ForumEntry> bookmarks = [], history = [], offline = [];
  final Map<String, String> updateStatus = {};
  double textSize = 19;
  bool checking = false;
  List<ForumEntry> _read(String key) {
    try {
      return (jsonDecode(preferences.getString(key) ?? '[]') as List)
          .map((e) => ForumEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> persist(String key, List<ForumEntry> entries) async {
    await preferences.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  bool bookmarked(Uri url) => bookmarks.any((e) => e.url == url);
  Future<void> toggle(ForumEntry entry) async {
    if (bookmarked(entry.url)) {
      bookmarks.removeWhere((e) => e.url == entry.url);
    } else {
      bookmarks.insert(0, entry);
    }
    await persist('bookmarks', bookmarks);
  }

  Future<void> visit(ForumEntry entry) async {
    history.removeWhere((e) => e.url == entry.url);
    history.insert(0, entry);
    if (history.length > 300) history.removeRange(300, history.length);
    await persist('history', history);
  }

  Future<void> markOffline(ForumEntry entry) async {
    offline.removeWhere((e) => e.url == entry.url);
    offline.insert(0, entry);
    await persist('offline', offline);
  }

  Future<void> fontSize(double size) async {
    textSize = size;
    await preferences.setDouble('textSize', size);
    notifyListeners();
  }

  bool due(ForumEntry entry) =>
      DateTime.now().millisecondsSinceEpoch -
          (preferences.getInt('checked.${entry.url}') ?? 0) >=
      const Duration(hours: 1).inMilliseconds;
  Future<void> check(Future<ForumPage> Function(Uri) fetch) async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      for (final entry in List<ForumEntry>.of(bookmarks).where(due)) {
        updateStatus['${entry.url}'] = 'Loading';
        notifyListeners();
        try {
          final page = await fetch(entry.url);
          final signature =
              '${page.posts.lastOrNull?.id ?? page.entries.firstOrNull?.url}|${page.next}';
          final key = 'signature.${entry.url}';
          updateStatus['${entry.url}'] = preferences.getString(key) == signature
              ? 'No changes'
              : 'Updated';
          await preferences.setString(key, signature);
          await preferences.setInt(
            'checked.${entry.url}',
            DateTime.now().millisecondsSinceEpoch,
          );
        } catch (_) {
          updateStatus['${entry.url}'] = 'Failed';
        }
        notifyListeners();
      }
    } finally {
      checking = false;
      notifyListeners();
    }
  }
}
