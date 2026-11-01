import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'forum_identity.dart';
import 'models.dart';
import 'site.dart';

class ThreadProgress {
  int? viewed, latest;
  int latestPage = 1, checked = 0, attempted = 0;
  String? anchor, anchorUrl;
  bool get updated => viewed != null && latest != null && latest! > viewed!;
  Map<String, dynamic> toJson() => {
    'viewed': viewed,
    'latest': latest,
    'latestPage': latestPage,
    'checked': checked,
    'attempted': attempted,
    'anchor': anchor,
    'anchorUrl': anchorUrl,
  };
  static ThreadProgress fromJson(Map data) => ThreadProgress()
    ..viewed = data['viewed'] as int?
    ..latest = data['latest'] as int?
    ..latestPage = data['latestPage'] as int? ?? 1
    ..checked = data['checked'] as int? ?? 0
    ..attempted = data['attempted'] as int? ?? 0
    ..anchor = data['anchor'] as String?
    ..anchorUrl = data['anchorUrl'] as String?;
}

class FollowedAuthor {
  FollowedAuthor(
    this.id,
    this.name, {
    this.avatar,
    this.topics = const [],
    this.checked = 0,
    this.attempted = 0,
  });
  final String id;
  String name;
  Uri? avatar;
  List<ForumEntry> topics;
  int checked, attempted;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar?.toString(),
    'topics': topics.map((e) => e.toJson()).toList(),
    'checked': checked,
    'attempted': attempted,
  };
  static FollowedAuthor fromJson(Map data) => FollowedAuthor(
    data['id'] as String,
    data['name'] as String,
    avatar: Uri.tryParse(data['avatar'] as String? ?? ''),
    topics: (data['topics'] as List? ?? [])
        .map((e) => ForumEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    checked: data['checked'] as int? ?? 0,
    attempted: data['attempted'] as int? ?? 0,
  );
}

class LibraryStore extends ChangeNotifier {
  LibraryStore(this.preferences, {this.site = const ForumSite(Module.simp)}) {
    bookmarks.addAll(_readEntries('bookmarks'));
    history.addAll(_readEntries('history'));
    offline.addAll(_readEntries('offline'));
    textSize = preferences.getDouble('textSize') ?? 19;
    final raw = preferences.getString('forum.library.v2');
    if (raw != null) {
      try {
        final doc = jsonDecode(raw) as Map;
        for (final e in (doc['progress'] as Map).entries) {
          progress['${e.key}'] = ThreadProgress.fromJson(e.value as Map);
        }
        for (final e in doc['authors'] as List) {
          final author = FollowedAuthor.fromJson(e as Map);
          authors[author.id] = author;
        }
        blocked.addAll(Map<String, String>.from(doc['blocked'] as Map));
        readThreads.addAll(List<String>.from(doc['readThreads'] as List));
      } catch (_) {
        readOnly = true;
      }
    }
  }
  final SharedPreferences preferences;
  final ForumSite site;
  final List<ForumEntry> bookmarks = [], history = [], offline = [];
  final Map<String, ThreadProgress> progress = {};
  final Map<String, FollowedAuthor> authors = {};
  final Map<String, String> blocked = {}, updateStatus = {};
  final Set<String> readThreads = {};
  double textSize = 19;
  bool checking = false, readOnly = false, updatesOnly = false;
  int completedChecks = 0, totalChecks = 0;
  String? currentCheck;
  static const interval = Duration(hours: 1);
  List<ForumEntry> _readEntries(String key) {
    try {
      return (jsonDecode(preferences.getString(key) ?? '[]') as List)
          .map((e) => ForumEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      readOnly = true;
      return [];
    }
  }

  Future<void> _persistState() async {
    if (readOnly) return;
    await preferences.setString(
      'forum.library.v2',
      jsonEncode({
        'progress': progress.map((key, value) => MapEntry(key, value.toJson())),
        'authors': authors.values.map((a) => a.toJson()).toList(),
        'blocked': blocked,
        'readThreads': readThreads.toList(),
      }),
    );
    notifyListeners();
  }

  Future<void> persist(String key, List<ForumEntry> entries) async {
    if (readOnly) return;
    await preferences.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  ThreadProgress? stateFor(Uri url) => progress[site.threadKey(url)];
  Uri destination(ForumEntry entry) {
    final state = stateFor(entry.url);
    if (site.module != Module.simp ||
        site.filtered(entry.url) ||
        state == null ||
        state.latestPage <= site.pageNumber(entry.url)) {
      return entry.url;
    }
    return site.pageUrl(entry.url, state.latestPage).removeFragment();
  }

  bool bookmarked(Uri url) =>
      bookmarks.any((e) => e.url == url || destination(e) == url);
  Future<void> toggle(ForumEntry entry) async {
    if (readOnly) return;
    if (bookmarked(entry.url)) {
      bookmarks.removeWhere(
        (e) => e.url == entry.url || destination(e) == entry.url,
      );
    } else {
      bookmarks.insert(0, entry);
    }
    await persist('bookmarks', bookmarks);
  }

  Future<int> importBookmarks(Iterable<ForumEntry> entries) async {
    if (readOnly) throw const FormatException('Preserved unreadable library');
    var count = 0;
    for (final entry in entries) {
      if (!site.readable(entry.url) ||
          bookmarks.any((e) => e.url == entry.url)) {
        continue;
      }
      bookmarks.add(entry);
      count++;
    }
    await persist('bookmarks', bookmarks);
    return count;
  }

  Future<void> rename(ForumEntry entry, String title) async {
    final index = bookmarks.indexOf(entry);
    if (readOnly || index < 0 || title.trim().isEmpty) return;
    bookmarks[index] = entry.copyWith(title: title.trim());
    await persist('bookmarks', bookmarks);
  }

  Future<void> visit(ForumEntry entry) async {
    if (readOnly) return;
    final key = site.threadKey(entry.url);
    history.removeWhere(
      (e) => key == null ? e.url == entry.url : site.threadKey(e.url) == key,
    );
    history.insert(0, entry);
    if (history.length > 300) history.removeRange(300, history.length);
    if (key != null) readThreads.add(key);
    await persist('history', history);
    await _persistState();
  }

  Future<void> clearHistory() async {
    if (readOnly) return;
    history.clear();
    await persist('history', history);
  }

  Future<void> markOffline(ForumEntry entry) async {
    if (readOnly) return;
    offline.removeWhere((e) => site.sameThread(e.url, entry.url));
    offline.insert(0, entry);
    await persist('offline', offline);
  }

  Future<void> fontSize(double size) async {
    textSize = size;
    await preferences.setDouble('textSize', size);
    notifyListeners();
  }

  Future<void> observePage(ForumPage page, {bool live = true}) async {
    final key = site.threadKey(page.url);
    if (readOnly ||
        key == null ||
        page.kind != PageKind.posts ||
        page.posts.isEmpty ||
        site.filtered(page.url)) {
      return;
    }
    final state = progress.putIfAbsent(key, ThreadProgress.new);
    state.latestPage = math.max(state.latestPage, page.totalPages);
    if (live && page.maximumPostNumber != null) {
      state.latest = math.max(state.latest ?? 0, page.maximumPostNumber!);
      state.checked = DateTime.now().millisecondsSinceEpoch;
    }
    for (final post in page.posts) {
      final author = authors[post.authorID];
      if (author != null && post.author.isNotEmpty) {
        author.name = post.author;
        author.avatar = post.avatar ?? author.avatar;
      }
    }
    await _persistState();
  }

  Future<void> recordVisible(
    ForumPage page,
    ForumPost post, {
    int? visibleMaximum,
  }) async {
    final key = site.threadKey(page.url);
    if (readOnly ||
        key == null ||
        blocked.containsKey(post.authorID) ||
        post.floor == null) {
      return;
    }
    final state = progress.putIfAbsent(key, ThreadProgress.new);
    final maximum = math.max(state.viewed ?? -1, visibleMaximum ?? post.floor!);
    if (state.viewed == maximum &&
        state.anchor == post.id &&
        state.anchorUrl == '${page.url}') {
      return;
    }
    state.viewed = maximum;
    state.anchor = post.id;
    state.anchorUrl = '${page.url}';
    final index = history.indexWhere((e) => site.sameThread(e.url, page.url));
    if (index >= 0) {
      history[index] = history[index].copyWith(
        url: page.url.replace(fragment: post.id),
      );
      await persist('history', history);
    }
    await _persistState();
  }

  Future<void> follow(ForumPost post) async {
    if (readOnly ||
        site.authorTopics(post.authorID) == null ||
        blocked.containsKey(post.authorID)) {
      return;
    }
    authors.putIfAbsent(
      post.authorID,
      () => FollowedAuthor(post.authorID, post.author, avatar: post.avatar),
    );
    await _persistState();
  }

  Future<void> unfollow(String id) async {
    if (readOnly) return;
    authors.remove(id);
    await _persistState();
  }

  Future<void> block(String id, String name) async {
    if (readOnly || !site.validAuthor(id)) return;
    blocked[id] = name;
    authors.remove(id);
    await _persistState();
  }

  Future<void> unblock(String id) async {
    if (readOnly) return;
    blocked.remove(id);
    await _persistState();
  }

  bool isUnread(Uri url) => !readThreads.contains(site.threadKey(url));
  static bool isDue(
    int checked,
    int attempted, {
    bool manual = false,
    int? now,
  }) {
    final time = now ?? DateTime.now().millisecondsSinceEpoch;
    return time - checked >= interval.inMilliseconds &&
        (manual || time - attempted >= interval.inMilliseconds);
  }

  bool due(ForumEntry entry, {bool manual = false}) {
    final state = stateFor(entry.url);
    return isDue(state?.checked ?? 0, state?.attempted ?? 0, manual: manual);
  }

  Future<ForumPage> latestPage(
    ForumPage initial,
    Future<ForumPage> Function(Uri) fetch,
  ) async {
    var page = initial;
    if (page.kind != PageKind.posts ||
        site.threadKey(page.url) == null ||
        site.filtered(page.url)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    for (var step = 0; step < 3; step++) {
      if (page.maximumPostNumber != null) return page;
      final last = page.lastPage ?? page.next;
      if (last == null ||
          !site.sameThread(last, initial.url) ||
          site.pageNumber(last) <= page.pageNumber) {
        break;
      }
      page = await fetch(last);
      if (!site.sameThread(page.url, initial.url) ||
          site.filtered(page.url) ||
          page.kind != PageKind.posts) {
        break;
      }
    }
    throw const ReaderFailure(FailureKind.unsupported);
  }

  Future<void> check(
    Future<ForumPage> Function(Uri) fetch, {
    bool manual = false,
  }) async {
    if (checking || readOnly || site.module == Module.bookhouse) return;
    checking = true;
    completedChecks = 0;
    final targets = <String, ForumEntry>{};
    for (final e in [...bookmarks, ...history.take(10)]) {
      final key = site.threadKey(e.url);
      if (key != null && !site.filtered(e.url)) {
        targets.putIfAbsent(key, () => e);
      }
    }
    final people = authors.values.toList();
    totalChecks = targets.length + people.length;
    notifyListeners();
    var stop = false;
    try {
      for (final target in targets.entries) {
        final key = target.key, entry = target.value;
        final state = progress.putIfAbsent(key, ThreadProgress.new);
        if (!isDue(state.checked, state.attempted, manual: manual)) {
          updateStatus[key] = 'Checked recently';
          completedChecks++;
          continue;
        }
        currentCheck = entry.title;
        updateStatus[key] = 'Loading';
        state.attempted = DateTime.now().millisecondsSinceEpoch;
        await _persistState();
        try {
          final first = await fetch(site.threadRoot(entry.url)!);
          final last = await latestPage(first, fetch);
          state.latestPage = math.max(
            state.latestPage,
            math.max(first.totalPages, last.totalPages),
          );
          state.latest = math.max(state.latest ?? 0, last.maximumPostNumber!);
          state.checked = DateTime.now().millisecondsSinceEpoch;
          updateStatus[key] = state.updated ? 'Updated' : 'No changes';
        } catch (error) {
          stop =
              error is ReaderFailure &&
              const [
                FailureKind.login,
                FailureKind.verification,
                FailureKind.rateLimit,
              ].contains(error.kind);
          updateStatus[key] =
              error is ReaderFailure && error.kind == FailureKind.verification
              ? 'Login or verify in browser'
              : 'Failed';
        }
        completedChecks++;
        await _persistState();
        if (stop) break;
      }
      if (!stop) {
        for (final author in people) {
          if (authors[author.id] != author || blocked.containsKey(author.id)) {
            continue;
          }
          final statusKey = 'author:${author.id}';
          if (!isDue(author.checked, author.attempted, manual: manual)) {
            updateStatus[statusKey] = 'Checked recently';
            completedChecks++;
            continue;
          }
          currentCheck = author.name;
          updateStatus[statusKey] = 'Loading';
          author.attempted = DateTime.now().millisecondsSinceEpoch;
          await _persistState();
          try {
            final page = await fetch(site.authorTopics(author.id)!);
            if (page.kind != PageKind.threads ||
                site.parameters(page.url)['uid'] != author.id ||
                page.pageNumber != 1) {
              throw const ReaderFailure(FailureKind.unsupported);
            }
            final seen = <String>{};
            final entries = page.entries
                .where(
                  (e) =>
                      e.authorID == author.id &&
                      site.threadKey(e.url) != null &&
                      seen.add(site.threadKey(e.url)!),
                )
                .take(3)
                .toList();
            if (page.entries.isNotEmpty && entries.isEmpty) {
              throw const ReaderFailure(FailureKind.unsupported);
            }
            if (authors[author.id] != author) continue;
            author.topics = entries;
            author.checked = DateTime.now().millisecondsSinceEpoch;
            updateStatus[statusKey] = entries.any((e) => isUnread(e.url))
                ? 'Updated'
                : 'No changes';
          } catch (_) {
            updateStatus[statusKey] = 'Failed';
          }
          completedChecks++;
          await _persistState();
        }
      }
    } finally {
      checking = false;
      currentCheck = null;
      notifyListeners();
    }
  }
}
