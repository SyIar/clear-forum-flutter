import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class HistoryEntry {
  HistoryEntry({
    required this.threadId,
    required this.title,
    this.forumName = '',
    this.lastPostId = '',
    this.page = 1,
    this.onlyAuthor = false,
    DateTime? visitedAt,
  }) : visitedAt = visitedAt ?? DateTime.now();
  final String threadId, title, forumName, lastPostId;
  final int page;
  final bool onlyAuthor;
  final DateTime visitedAt;
  JsonMap toJson() => {
    'threadId': threadId,
    'title': title,
    'forumName': forumName,
    'lastPostId': lastPostId,
    'page': page,
    'onlyAuthor': onlyAuthor,
    'visitedAt': visitedAt.toIso8601String(),
  };
  factory HistoryEntry.fromJson(JsonMap value) => HistoryEntry(
    threadId: stringValue(value['threadId']),
    title: stringValue(value['title']),
    forumName: stringValue(value['forumName']),
    lastPostId: stringValue(value['lastPostId']),
    page: intValue(value['page']).clamp(1, 1000000),
    onlyAuthor: value['onlyAuthor'] == true,
    visitedAt:
        DateTime.tryParse(stringValue(value['visitedAt'])) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class ForumHistoryEntry {
  const ForumHistoryEntry({required this.forum, this.visitedAt});
  final Forum forum;

  /// Unknown for records migrated from the original recent-forum list.
  final DateTime? visitedAt;
  JsonMap toJson() => {
    'forum': forum.toJson(),
    if (visitedAt != null) 'visitedAt': visitedAt!.toIso8601String(),
  };
  factory ForumHistoryEntry.fromJson(JsonMap value) => ForumHistoryEntry(
    forum: Forum.fromJson(objectValue(value['forum'])),
    visitedAt: DateTime.tryParse(stringValue(value['visitedAt'])),
  );
}

class ReplyDraft {
  ReplyDraft({
    required this.key,
    required this.threadId,
    this.forumName = '',
    this.content = '',
    this.imagePaths = const [],
    this.parentPostId = '',
    this.targetSubPostId = '',
    this.replyUserId = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();
  final String key,
      threadId,
      forumName,
      content,
      parentPostId,
      targetSubPostId,
      replyUserId;
  final List<String> imagePaths;
  final DateTime updatedAt;
  JsonMap toJson() => {
    'key': key,
    'threadId': threadId,
    'forumName': forumName,
    'content': content,
    'imagePaths': imagePaths,
    'parentPostId': parentPostId,
    'targetSubPostId': targetSubPostId,
    'replyUserId': replyUserId,
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory ReplyDraft.fromJson(JsonMap value) => ReplyDraft(
    key: stringValue(value['key']),
    threadId: stringValue(value['threadId']),
    forumName: stringValue(value['forumName']),
    content: stringValue(value['content']),
    imagePaths: listValue(value['imagePaths'])
        .map(stringValue)
        .toList(growable: false),
    parentPostId: stringValue(value['parentPostId']),
    targetSubPostId: stringValue(value['targetSubPostId']),
    replyUserId: stringValue(value['replyUserId']),
    updatedAt:
        DateTime.tryParse(stringValue(value['updatedAt'])) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

enum BlockKind { user, forum, keyword, thread }

class BlockRule {
  const BlockRule({
    required this.kind,
    required this.value,
    this.label = '',
    this.user,
    this.allow = false,
    this.keywords = const [],
  });
  final BlockKind kind;
  final String value, label;
  final UserProfile? user;
  final bool allow;
  final List<String> keywords;
  List<String> get effectiveKeywords => keywords.isEmpty ? [value] : keywords;
  JsonMap toJson() => {
    'kind': kind.name,
    'value': value,
    'label': label,
    'allow': allow,
    if (keywords.isNotEmpty) 'keywords': keywords,
    if (user != null) 'user': user!.toJson(),
  };
  factory BlockRule.fromJson(JsonMap value) => BlockRule(
    kind: BlockKind.values.firstWhere(
      (kind) => kind.name == value['kind'],
      orElse: () => BlockKind.keyword,
    ),
    value: stringValue(value['value']),
    label: stringValue(value['label']),
    allow: value['allow'] == true,
    keywords: listValue(value['keywords'])
        .map(stringValue)
        .toList(growable: false),
    user: value['user'] is Map
        ? UserProfile.fromJson(objectValue(value['user']))
        : null,
  );
}

/// Local records are separate from credentials and scoped to the active account.
class LocalStore extends ChangeNotifier {
  static const _prefix = 'tieba_lite.local.v1.';
  static const _recentForumLimit = 5;
  SharedPreferences? _preferences;
  String _namespace = 'guest';
  JsonMap _data = _emptyData();
  bool _loadFailed = false;
  final Map<String, Set<String>> _sentDrafts = {};
  Future<void> _pending = Future<void>.value();

  static JsonMap _emptyData() => {
    'version': 1,
    'history': [],
    'pins': [],
    'search': [],
    'blocks': [],
    'drafts': [],
    'recentForums': [],
    'forumHistory': [],
  };
  static String _namespaceFor(String? accountId) =>
      accountId == null || accountId.isEmpty
      ? 'guest'
      : base64Url.encode(utf8.encode(accountId));

  Future<void> init({String? accountId}) async {
    _preferences ??= await SharedPreferences.getInstance();
    await activateAccount(accountId);
  }

  Future<void> activateAccount(String? accountId) => _enqueue(() async {
    final namespace = _namespaceFor(accountId);
    _namespace = namespace;
    _data = _emptyData();
    _loadFailed = true;
    try {
      _data = _read(namespace);
      _loadFailed = false;
    } finally {
      notifyListeners();
    }
  });

  JsonMap _read(String namespace) {
    final raw = _preferences!.getString('$_prefix$namespace');
    if (raw == null) return _emptyData();
    final parsed = jsonDecode(raw);
    if (parsed is! Map || parsed['version'] != 1) {
      throw const FormatException('Unsupported local record data');
    }
    for (final key in [
      'history',
      'pins',
      'search',
      'blocks',
      'drafts',
      'recentForums',
      'forumHistory',
    ]) {
      if (parsed.containsKey(key) && parsed[key] is! List) {
        throw const FormatException('Invalid local record collection');
      }
    }
    return {
      ..._emptyData(),
      if (!parsed.containsKey('forumHistory'))
        'forumHistory': listValue(parsed['recentForums'])
            .map(
              (forum) =>
                  ForumHistoryEntry(forum: Forum.fromJson(objectValue(forum)))
                      .toJson(),
            )
            .toList(),
      ...objectValue(parsed),
      'recentForums': listValue(parsed['recentForums'])
          .take(_recentForumLimit)
          .toList(),
    };
  }

  List<HistoryEntry> get histories => List.unmodifiable(
    listValue(_data['history'])
        .map((item) => HistoryEntry.fromJson(objectValue(item))),
  );
  List<Forum> get pinnedForums => List.unmodifiable(
    listValue(_data['pins']).map((item) => Forum.fromJson(objectValue(item))),
  );
  List<String> get pinnedForumNames =>
      List.unmodifiable(pinnedForums.map((forum) => forum.name));
  List<Forum> get recentForums => List.unmodifiable(
    listValue(_data['recentForums'])
        .map((item) => Forum.fromJson(objectValue(item))),
  );
  List<ForumHistoryEntry> get forumHistories => List.unmodifiable(
    listValue(_data['forumHistory'])
        .map((item) => ForumHistoryEntry.fromJson(objectValue(item))),
  );
  List<String> get searchQueries =>
      List.unmodifiable(listValue(_data['search']).map(stringValue));
  List<BlockRule> get blockRules => List.unmodifiable(
    listValue(_data['blocks'])
        .map((item) => BlockRule.fromJson(objectValue(item))),
  );
  List<UserProfile> get blockedUsers => List.unmodifiable(
    blockRules
        .where((rule) => rule.kind == BlockKind.user && !rule.allow)
        .map(
          (rule) => rule.user ?? UserProfile(id: rule.value, name: rule.label),
        ),
  );
  Set<String> get blockedUserIds => Set.unmodifiable(
    blockRules
        .where((rule) => rule.kind == BlockKind.user && !rule.allow)
        .map((rule) => rule.value),
  );
  List<ReplyDraft> get drafts => List.unmodifiable(
    listValue(_data['drafts'])
        .map((item) => ReplyDraft.fromJson(objectValue(item)))
        .where(
          (draft) => !(_sentDrafts[_namespace]?.contains(draft.key) ?? false),
        ),
  );

  ReplyDraft? getDraft(String key) {
    for (final item in drafts) {
      if (item.key == key) return item;
    }
    return null;
  }

  Future<void> recordHistory(HistoryEntry entry) => _update((data) {
    if (entry.threadId.isEmpty) throw ArgumentError('A thread ID is required');
    data['history'] = [
      entry.toJson(),
      ...listValue(data['history'])
          .where((item) => objectValue(item)['threadId'] != entry.threadId),
    ].take(1000).toList();
  });

  Future<void> clearHistory() => _update((data) => data['history'] = []);
  Future<void> removeHistory(String threadId) => _update(
    (data) =>
        data['history'] = listValue(data['history'])
            .where((item) => objectValue(item)['threadId'] != threadId)
            .toList(),
  );

  Future<void> recordForum(Forum forum) => _update((data) {
    if (forum.name.isEmpty) return;
    // Newest arrivals are displayed first; revisits keep their FIFO position.
    final recent = listValue(data['recentForums']);
    final index = recent.indexWhere(
      (item) => objectValue(item)['name'] == forum.name,
    );
    if (index < 0) {
      recent.insert(0, forum.toJson());
    } else {
      recent[index] = forum.toJson();
    }
    data['recentForums'] = recent.take(_recentForumLimit).toList();
    data['forumHistory'] = [
      ForumHistoryEntry(forum: forum, visitedAt: DateTime.now()).toJson(),
      ...listValue(data['forumHistory']).where(
        (item) => objectValue(objectValue(item)['forum'])['name'] != forum.name,
      ),
    ].take(1000).toList();
  });

  Future<void> removeForumHistory(String name) => _update((data) {
    data['forumHistory'] = listValue(data['forumHistory'])
        .where(
          (item) => objectValue(objectValue(item)['forum'])['name'] != name,
        )
        .toList();
    data['recentForums'] = listValue(data['recentForums'])
        .where((item) => objectValue(item)['name'] != name)
        .toList();
  });

  Future<void> clearForumHistory() => _update((data) {
    data['forumHistory'] = [];
    data['recentForums'] = [];
  });

  Future<void> togglePinnedForum(Forum forum) => _update((data) {
    if (forum.name.isEmpty) throw ArgumentError('A forum name is required');
    final previous = listValue(data['pins']);
    final next = previous
        .where((item) => objectValue(item)['name'] != forum.name)
        .toList();
    if (next.length == previous.length) next.insert(0, forum.toJson());
    data['pins'] = next;
  });

  Future<void> rememberSearch(String query) => _update((data) {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    data['search'] = [
      normalized,
      ...listValue(data['search']).where((value) => value != normalized),
    ].take(100).toList();
  });

  Future<void> clearSearchHistory() => _update((data) => data['search'] = []);
  Future<void> blockUser(UserProfile user) => addBlock(
    BlockRule(
      kind: BlockKind.user,
      value: user.id,
      label: user.name,
      user: user,
    ),
  );
  Future<void> unblockUser(String id) => removeBlock(BlockKind.user, id);
  Future<void> addBlock(BlockRule rule) => _update((data) {
    if (rule.value.trim().isEmpty) {
      throw ArgumentError('A block value is required');
    }
    if (rule.kind == BlockKind.keyword &&
        rule.effectiveKeywords.any((keyword) => keyword.isEmpty)) {
      throw ArgumentError('Keyword groups cannot contain empty values');
    }
    data['blocks'] = [
      rule.toJson(),
      ...listValue(data['blocks']).where(
        (item) =>
            !(objectValue(item)['kind'] == rule.kind.name &&
                objectValue(item)['value'] == rule.value &&
                (objectValue(item)['allow'] == true) == rule.allow),
      ),
    ];
  });

  Future<void> removeBlock(
    BlockKind kind,
    String value, {
    bool allow = false,
  }) => _update(
    (data) => data['blocks'] = listValue(data['blocks'])
        .where(
          (item) =>
              !(objectValue(item)['kind'] == kind.name &&
                  objectValue(item)['value'] == value &&
                  (objectValue(item)['allow'] == true) == allow),
        )
        .toList(),
  );

  bool _denied(BlockKind kind, bool Function(BlockRule rule) matches) {
    final rules = blockRules.where((rule) => rule.kind == kind);
    return rules.any((rule) => !rule.allow && matches(rule)) &&
        !rules.any((rule) => rule.allow && matches(rule));
  }

  bool blocksContent(String content) => _denied(
    BlockKind.keyword,
    (rule) => rule.effectiveKeywords.every(
      (keyword) => keyword.isNotEmpty && content.contains(keyword),
    ),
  );

  bool blocksUser(UserProfile user) => _denied(BlockKind.user, (rule) {
    final username = user.username.isNotEmpty ? user.username : user.name;
    final storedUsername = rule.user?.username ?? '';
    return (user.id.isNotEmpty && rule.value == user.id) ||
        (username.isNotEmpty &&
            (rule.value == username ||
                (storedUsername.isNotEmpty && storedUsername == username)));
  });

  bool blocksThread(ThreadSummary thread) =>
      blocksUser(thread.author) ||
      blocksContent(thread.title) ||
      blocksContent(thread.excerpt) ||
      _denied(
        BlockKind.forum,
        (rule) =>
            rule.value == thread.forum.name || rule.value == thread.forum.id,
      ) ||
      _denied(BlockKind.thread, (rule) => rule.value == thread.id);

  bool blocksPost(Post post) =>
      blocksUser(post.author) ||
      blocksContent(post.plainText) ||
      _denied(BlockKind.thread, (rule) => rule.value == post.threadId);

  Future<void> saveDraft(ReplyDraft draft) {
    final namespace = _namespace;
    return _update((data) {
      if (draft.key.isEmpty || draft.threadId.isEmpty) {
        throw ArgumentError('A draft key and thread ID are required');
      }
      data['drafts'] = [
        draft.toJson(),
        ...listValue(data['drafts'])
            .where((item) => objectValue(item)['key'] != draft.key),
      ];
    }).then((_) {
      if (_sentDrafts[namespace]?.remove(draft.key) == true &&
          namespace == _namespace) {
        notifyListeners();
      }
    });
  }

  /// A successful remote reply must not be offered as an unsent draft again.
  Future<void> markDraftSent(String key, {String? expectedAccountId}) {
    final namespace = expectedAccountId == null
        ? _namespace
        : _namespaceFor(expectedAccountId);
    (_sentDrafts[namespace] ??= {}).add(key);
    if (namespace == _namespace) notifyListeners();
    return _update(
      (data) =>
          data['drafts'] = listValue(data['drafts'])
              .where((item) => objectValue(item)['key'] != key)
              .toList(),
      namespace: namespace,
    );
  }

  Future<void> removeDraft(String key) => _update(
    (data) =>
        data['drafts'] = listValue(data['drafts'])
            .where((item) => objectValue(item)['key'] != key)
            .toList(),
  );

  Future<void> _update(
    void Function(JsonMap data) change, {
    String? namespace,
  }) {
    final capturedNamespace = namespace ?? _namespace;
    return _enqueue(() async {
      if (capturedNamespace == _namespace && _loadFailed) {
        throw StateError('Local records must load successfully before editing');
      }
      final next = objectValue(
        jsonDecode(
          jsonEncode(
            capturedNamespace == _namespace ? _data : _read(capturedNamespace),
          ),
        ),
      );
      change(next);
      if (!await _preferences!.setString(
        '$_prefix$capturedNamespace',
        jsonEncode(next),
      )) {
        throw StateError('Could not save local records');
      }
      if (capturedNamespace == _namespace) {
        _data = next;
        notifyListeners();
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) async {
      if (_preferences == null) {
        throw StateError('LocalStore is not initialized');
      }
      await action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
