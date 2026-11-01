import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as image;
import 'package:protobuf/protobuf.dart';

import 'models.dart';
import 'transport.dart';
import 'proto/FrsPage/FrsPage.pb.dart' as frs;
import 'proto/PbPage/PbPageRequest.pb.dart' as pb;
import 'proto/PbPage/PbPageResponse.pb.dart' as pb;
import 'proto/PbFloor/PbFloorRequest.pb.dart' as floor;
import 'proto/PbFloor/PbFloorResponse.pb.dart' as floor;
import 'proto/Personalized.pb.dart' as personalized;
import 'proto/UserLike/UserLike.pb.dart' as concern;
import 'proto/HotThreadList/HotThreadList.pb.dart' as hot;
import 'proto/TopicList/TopicList.pb.dart' as topic_list;
import 'proto/SearchSug/SearchSugRequest.pb.dart' as search_sug;
import 'proto/SearchSug/SearchSugResponse.pb.dart' as search_sug;
import 'proto/Profile/ProfileRequest.pb.dart' as profile;
import 'proto/Profile/ProfileResponse.pb.dart' as profile;
import 'proto/UserPost/UserPostRequest.pb.dart' as user_post;
import 'proto/UserPost/UserPostResponse.pb.dart' as user_post;
import 'proto/GetForumDetail/GetForumDetailRequest.pb.dart' as detail;
import 'proto/GetForumDetail/GetForumDetailResponse.pb.dart' as detail;
import 'proto/ForumRuleDetail/ForumRuleDetailRequest.pb.dart' as rule;
import 'proto/ForumRuleDetail/ForumRuleDetailResponse.pb.dart' as rule;
import 'proto/AddPost/AddPostRequest.pb.dart' as add_post;
import 'proto/AddPost/AddPostResponse.pb.dart' as add_post;

export 'models.dart';
export 'transport.dart' show TiebaApiException;

class TiebaApi {
  TiebaApi({
    required SessionProvider sessionProvider,
    Dio? dio,
    String? deviceId,
  }) : transport = TiebaTransport(
         sessionProvider: sessionProvider,
         dio: dio,
         deviceId: deviceId,
       );
  final TiebaTransport transport;
  final Map<int, String> _concernCursors = {1: ''};
  String _concernAccount = '';
  final Map<String, String> _tbsTokens = {};

  Future<TiebaSession> login({
    required String bduss,
    required String stoken,
    String cookie = '',
  }) async {
    if (bduss.trim().isEmpty || stoken.trim().isEmpty) {
      throw const TiebaApiException(
        'The Baidu sign-in did not provide the required cookies.',
        code: 'missing_cookie',
      );
    }
    final candidate = TiebaSession(
      bduss: bduss,
      stoken: stoken,
      rawCookie: cookie,
    );
    final json = await transport.form(
      '/c/s/login',
      {
        'bdusstoken': '$bduss|',
        'stoken': stoken,
        'channel_id': '',
        'channel_uid': '',
        'authsid': 'null',
      },
      session: candidate,
      omit: {'BDUSS'},
    );
    final user = _user(objectValue(json['user']));
    if (user.id.isEmpty) {
      throw const TiebaApiException(
        'The server did not return an account.',
        code: 'invalid_account',
      );
    }
    await transport.form('/c/s/initNickname', {
      'BDUSS': bduss,
      'stoken': stoken,
    }, session: candidate);
    var zid = '';
    try {
      zid = await transport.fetchZid();
    } on TiebaApiException {
      // Browsing remains available if the optional device service is unavailable.
    }
    final tbs = stringValue(objectValue(json['anti'])['tbs']);
    _tbsTokens.remove(user.id);
    if (tbs.isNotEmpty) _tbsTokens[user.id] = tbs;
    return candidate.copyWith(userId: user.id, tbs: tbs, user: user, zid: zid);
  }

  Future<List<Forum>> followedForums() async {
    final session = transport.requireSession();
    final json = await transport.form('/c/f/forum/getforumlist', {
      'user_id': session.userId,
    }, authenticated: true);
    return _records(json['forum_info'])
        .map((entry) => _forum({...entry, 'is_like': 1}))
        .toList(growable: false);
  }

  Future<Set<String>> officialBatchSign(List<Forum> forums) async {
    final session = transport.requireSession();
    final info = await transport.form(
      '/c/f/forum/getforumlist',
      {'user_id': session.userId},
      authenticated: true,
      version: '11.10.8.6',
    );
    if (transport.requireSession().userId != session.userId) {
      throw const TiebaApiException(
        'The account changed before check-in.',
        code: 'account_changed',
      );
    }
    final allowed = forums
        .where((forum) => !forum.isSigned)
        .map((forum) => forum.id)
        .toSet();
    final minimumLevel = intValue(info['level']);
    final limit = intValue(info['msign_step_num']);
    final candidates = _records(info['forum_info'])
        .map(_forum)
        .where(
          (forum) =>
              allowed.contains(forum.id) &&
              !forum.isSigned &&
              forum.level >= minimumLevel,
        )
        .take(max(0, limit))
        .toList();
    if (candidates.isEmpty) return {};
    final response = await transport.form(
      '/c/c/forum/msign',
      {
        'forum_ids': candidates.map((forum) => forum.id).join(','),
        'tbs': _sessionTbs(session),
        'authsid': 'null',
        'stoken': session.stoken,
        'user_id': session.userId,
      },
      authenticated: true,
      version: '11.10.8.6',
      session: session,
    );
    final requested = candidates.map((forum) => forum.id).toSet();
    return _records(response['info'])
        .where((entry) => boolValue(entry['signed']))
        .map((entry) => stringValue(entry['forum_id']))
        .where(requested.contains)
        .toSet();
  }

  Future<List<String>> searchSuggestions(
    String query, {
    bool isForum = false,
  }) async {
    if (query.trim().isEmpty) return [];
    final data = await _proto(
      '/c/s/searchSug?cmd=309438&format=protobuf',
      search_sug.SearchSugRequest(),
      search_sug.SearchSugResponse.fromBuffer,
      {
        'common': _common(),
        'word': query.trim(),
        'isforum': isForum ? '1' : '0',
      },
    );
    return listValue(data['list'])
        .map(stringValue)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<HotOverview> hotOverview({String tabCode = 'all'}) async {
    final data = await _proto(
      '/c/f/forum/hotThreadList?cmd=309661',
      hot.HotThreadListRequest(),
      hot.HotThreadListResponse.fromBuffer,
      {'common': _common(legacy: true), 'tabId': '1', 'tabCode': tabCode},
      legacy: true,
    );
    return HotOverview(
      topics: _records(data['topic_list']).map(_topic).toList(growable: false),
      threads: _records(data['thread_info'])
          .where(_isContent)
          .map((entry) => _thread(entry))
          .toList(growable: false),
      tabs: _records(data['hot_thread_tab_info'])
          .map(
            (entry) => HotTab(
              id: stringValue(entry['tab_id']),
              title: _first(entry, ['tab_title', 'tab_name']),
              code: stringValue(entry['tab_code']),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<HotTopic>> hotTopics() async {
    final data = await _proto(
      '/c/f/recommend/topicList?cmd=309289',
      topic_list.TopicListRequest(),
      topic_list.TopicListResponse.fromBuffer,
      {
        'common': _common(legacy: true),
        'call_from': 'newbang',
        'list_type': 'all',
        'need_tab_list': '0',
        'fid': '0',
      },
      legacy: true,
    );
    return _records(data['topic_list']).map(_topic).toList(growable: false);
  }

  Future<PageResult<ThreadSummary>> topicThreads(
    String topicId, {
    required String topicName,
    int page = 1,
  }) async {
    _id(topicId);
    _page(page);
    final accountId = transport.sessionProvider()?.userId;
    final response = await transport.web('/mo/q/newtopic/topicDetail', {
      'topic_id': topicId,
      'topic_name': topicName,
      'is_new': 0,
      'is_share': 1,
      'pn': page,
      'rn': 10,
      'offset': 0,
      'derivative_to_pic_id': '',
    });
    final data = objectValue(response['data']);
    final tbs = stringValue(data['tbs']);
    if (accountId != null && tbs.isNotEmpty) _tbsTokens[accountId] = tbs;
    final records = <JsonMap>[
      if (page == 1)
        for (final section in _records(data['special_topic']))
          ..._records(section['thread_list']),
      for (final item in _records(
        objectValue(data['relate_thread'])['thread_list'],
      ))
        {...objectValue(item['thread_info']), 'user_agree': item['user_agree']},
    ];
    final seen = <String>{};
    final threads = <ThreadSummary>[];
    for (final record in records) {
      final id = _first(record, ['tid', 'id']);
      if (id.isNotEmpty && seen.add(id)) {
        threads.add(_thread({...record, 'id': id}));
      }
    }
    return PageResult(
      items: threads,
      page: page,
      hasMore: threads.isNotEmpty && boolValue(data['has_more']),
      topic: _topic({...objectValue(data['topic_info']), 'topic_id': topicId}),
      relatedForums: _records(data['relateForum'] ?? data['relate_forum'])
          .map(_forum)
          .toList(growable: false),
      tbs: tbs,
    );
  }

  Future<PageResult<ThreadSummary>> feed({
    FeedKind kind = FeedKind.personalized,
    int page = 1,
  }) async {
    _page(page);
    JsonMap data;
    List<JsonMap> records;
    bool hasMore;
    switch (kind) {
      case FeedKind.personalized:
        data = await _proto(
          '/c/f/excellent/personalized?cmd=309264',
          personalized.PersonalizedRequest(),
          personalized.PersonalizedResponse.fromBuffer,
          {
            'common': _common(),
            'pn': page,
            'load_type': page == 1 ? 1 : 2,
            'page_thread_count': 20,
            'q_type': 1,
            'new_net_type': 1,
          },
        );
        records = _records(data['thread_list']);
        hasMore = records.isNotEmpty;
      case FeedKind.concern:
        final account = transport.requireSession().userId;
        if (account != _concernAccount || page == 1) {
          _concernCursors
            ..clear()
            ..[1] = '';
          _concernAccount = account;
        }
        if (!_concernCursors.containsKey(page)) {
          throw const TiebaApiException(
            'Refresh the following feed before loading another page.',
            code: 'cursor_missing',
          );
        }
        data = await _proto(
          '/c/f/concern/userlike?cmd=309474',
          concern.UserLikeRequest(),
          concern.UserLikeResponse.fromBuffer,
          {
            'common': _common(),
            'pageTag': _concernCursors[page],
            'lastRequestUnix':
                '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
            'followType': 1,
            'loadType': page == 1 ? 1 : 2,
          },
          authenticated: true,
        );
        _concernCursors[page + 1] = stringValue(data['page_tag']);
        records = _records(data['thread_info'])
            .map((entry) => objectValue(entry['thread_list']))
            .where((entry) => entry.isNotEmpty)
            .toList();
        hasMore = boolValue(data['has_more']);
      case FeedKind.hot:
        if (page > 1) return PageResult(page: page);
        data = await _proto(
          '/c/f/forum/hotThreadList?cmd=309661',
          hot.HotThreadListRequest(),
          hot.HotThreadListResponse.fromBuffer,
          {'common': _common(), 'tabId': '0', 'tabCode': ''},
        );
        records = _records(data['thread_info']);
        hasMore = false;
    }
    return PageResult(
      items: records
          .where(_isContent)
          .map((entry) => _thread(entry))
          .toList(growable: false),
      page: page,
      hasMore: hasMore,
    );
  }

  Future<PageResult<ThreadSummary>> forumThreads(
    String name, {
    int page = 1,
    int sort = 0,
    bool digest = false,
  }) async {
    if (name.trim().isEmpty) {
      throw const TiebaApiException(
        'Enter a forum name.',
        code: 'invalid_input',
      );
    }
    _page(page);
    final data = await _proto(
      '/c/f/frs/page?cmd=301001',
      frs.FrsPageRequest(),
      frs.FrsPageResponse.fromBuffer,
      {
        'common': _common(),
        'kw': Uri.encodeComponent(name),
        'pn': page,
        'rn': 90,
        'rn_need': 30,
        'q_type': 2,
        'sort_type': sort,
        'load_type': page == 1 ? 1 : 2,
        'is_good': digest ? 1 : 0,
        'cid': 0,
        'st_type': 'recom_flist',
        'with_group': 1,
      },
    );
    final forum = _forum(objectValue(data['forum']), fallbackName: name);
    final users = _users(data['user_list']);
    final threads = _records(data['thread_list'])
        .where(_isContent)
        .map((entry) => _thread(entry, forum: forum, users: users))
        .toList(growable: false);
    return PageResult(
      items: threads,
      page: page,
      hasMore: _hasMore(data, threads.length),
      forum: forum,
      tbs: _tbs(data),
    );
  }

  Future<PageResult<Post>> threadPosts(
    String id, {
    int page = 1,
    bool onlyAuthor = false,
    int sort = 0,
    String? postId,
    String? anchorPostId,
  }) async {
    _id(id);
    _page(page);
    final anchor = anchorPostId ?? postId;
    if (anchor != null && anchor.isNotEmpty) _id(anchor);
    final data = await _proto(
      '/c/f/pb/page?cmd=302001&format=protobuf',
      pb.PbPageRequest(),
      pb.PbPageResponse.fromBuffer,
      {
        'common': _common(),
        'kz': id,
        'pn': anchor != null && anchor.isNotEmpty && anchor != '0' ? 0 : page,
        'pid': anchor?.isNotEmpty == true ? anchor : '0',
        'lz': onlyAuthor ? 1 : 0,
        'r': sort,
        'with_floor': 1,
        'floor_rn': 4,
        'floor_sort_type': 1,
        'rn': 15,
        'q_type': 2,
        'source_type': 2,
      },
    );
    final forum = _forum(objectValue(data['forum']));
    final users = _users(data['user_list']);
    final thread = _thread(
      objectValue(data['thread']),
      forum: forum,
      users: users,
    );
    final posts = _records(data['post_list'])
        .map((entry) => _post(entry, id, users))
        .toList(growable: false);
    final currentPage = intValue(objectValue(data['page'])['current_page']);
    return PageResult(
      items: posts,
      page: currentPage > 0 ? currentPage : page,
      hasMore: _hasMore(data, posts.length),
      forum: forum,
      thread: thread,
      tbs: _tbs(data),
      total: intValue(objectValue(data['page'])['total_count']),
    );
  }

  Future<PageResult<Post>> floorReplies({
    required String threadId,
    required String postId,
    required String forumId,
    int page = 1,
  }) async {
    _id(threadId);
    _id(postId);
    _page(page);
    final data = await _proto(
      '/c/f/pb/floor?cmd=302002&format=protobuf',
      floor.PbFloorRequest(),
      floor.PbFloorResponse.fromBuffer,
      {
        'common': _common(),
        'kz': threadId,
        'pid': postId,
        'forum_id': forumId.isEmpty ? '0' : forumId,
        'pn': page,
      },
      outerToken: false,
    );
    final posts = _records(data['subpost_list'])
        .map((entry) => _post(entry, threadId, {}, parentId: postId))
        .toList(growable: false);
    return PageResult(
      items: posts,
      page: page,
      hasMore: _hasMore(data, posts.length),
      forum: _forum(objectValue(data['forum'])),
      thread: _thread(objectValue(data['thread'])),
      tbs: _tbs(data),
    );
  }

  Future<List<Forum>> searchForums(String query) async {
    _query(query);
    final json = await transport.web('/mo/q/search/forum', {'word': query});
    final data = objectValue(json['data']);
    final exact = objectValue(data['exact_match']);
    final records = [
      if (exact.isNotEmpty) exact,
      ..._records(data['fuzzy_match']),
    ];
    final seen = <String>{};
    return records
        .map(_forum)
        .where(
          (forum) =>
              forum.name.isNotEmpty &&
              seen.add(forum.id.isEmpty ? forum.name : forum.id),
        )
        .toList(growable: false);
  }

  Future<PageResult<ThreadSummary>> searchThreads(
    String query, {
    int page = 1,
    int sort = 0,
    String? forumName,
  }) async {
    _query(query);
    _page(page);
    final json = await transport.web('/mo/q/search/thread', {
      'word': query,
      'pn': page,
      'st': sort,
      'tt': 1,
      'ct': 1,
      'is_use_zonghe': 1,
      'cv': '99.9.101',
      'fname': ?forumName,
    });
    final data = objectValue(json['data']);
    return PageResult(
      items: _records(data['post_list'])
          .map((entry) => _thread(entry))
          .toList(growable: false),
      page: page,
      hasMore: boolValue(data['has_more']),
    );
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    _query(query);
    final json = await transport.web('/mo/q/search/user', {'word': query});
    final data = objectValue(json['data']);
    final exact = objectValue(data['exact_match']);
    final seen = <String>{};
    return [if (exact.isNotEmpty) exact, ..._records(data['fuzzy_match'])]
        .map(_user)
        .where((user) => user.id.isNotEmpty && seen.add(user.id))
        .toList(growable: false);
  }

  Future<PageResult<ThreadSummary>> favorites({int page = 1}) async {
    _page(page);
    final session = transport.requireSession();
    final data = await transport.form('/c/f/post/threadstore', {
      'rn': 30,
      'offset': (page - 1) * 30,
      'user_id': session.userId,
    }, authenticated: true);
    final records = _records(data['store_thread']);
    return PageResult(
      items: records.map((entry) => _thread(entry)).toList(growable: false),
      page: page,
      hasMore: records.length >= 30,
    );
  }

  Future<PageResult<NotificationItem>> notifications({
    NotificationKind kind = NotificationKind.replies,
    int page = 1,
  }) async {
    _page(page);
    final endpoint = switch (kind) {
      NotificationKind.replies => 'replyme',
      NotificationKind.mentions => 'atme',
      NotificationKind.likes => 'agreeme',
    };
    final json = await transport.form(
      '/c/u/feed/$endpoint',
      {'pn': page - 1},
      version: '8.2.2',
      authenticated: true,
    );
    final list =
        json[kind == NotificationKind.mentions
            ? 'at_list'
            : kind == NotificationKind.likes
            ? 'agree_list'
            : 'reply_list'] ??
        json['reply_list'];
    final records = _records(list);
    return PageResult(
      items: records
          .map(
            (entry) => NotificationItem(
              id: _first(entry, ['post_id', 'id']),
              kind: kind,
              author: _user(objectValue(entry['replyer'] ?? entry['user'])),
              threadId: _first(entry, ['thread_id', 'tid']),
              postId: _first(entry, ['post_id', 'pid']),
              title: stringValue(entry['title']),
              content: _stripHtml(stringValue(entry['content'])),
              createdAt: _date(entry['time']),
              isRead: !boolValue(entry['unread']),
            ),
          )
          .toList(growable: false),
      page: page,
      hasMore: _hasMore(json, records.length),
    );
  }

  Future<Map<NotificationKind, int>> notificationCounts() async {
    final data = await transport.form(
      '/c/s/msg',
      {'bookmark': 1},
      authenticated: true,
      version: '8.2.2',
    );
    final message = objectValue(data['message']);
    return {
      NotificationKind.replies: intValue(message['replyme']),
      NotificationKind.mentions: intValue(message['atme']),
      NotificationKind.likes: intValue(message['agreeme']),
    };
  }

  Future<UserProfile> userProfile(String id) async {
    _id(id);
    final self = transport.sessionProvider()?.userId;
    final data = await _proto(
      '/c/u/user/profile?cmd=303012&format=protobuf',
      profile.ProfileRequest(),
      profile.ProfileResponse.fromBuffer,
      {
        'common': _common(),
        'uid': self?.isNotEmpty == true ? self : id,
        if (self != id) 'friend_uid': id,
        'is_guest': self == id ? 0 : 1,
        'has_plist': 1,
        'is_from_usercenter': 1,
        'need_post_count': 1,
        'page': 1,
        'pn': 1,
        'rn': 20,
      },
    );
    return _user(objectValue(data['user']));
  }

  Future<PageResult<ThreadSummary>> userPosts(
    String id, {
    int page = 1,
    bool replies = false,
  }) async {
    _id(id);
    _page(page);
    final data = await _proto(
      '/c/u/feed/userpost?cmd=303002&format=protobuf',
      user_post.UserPostRequest(),
      user_post.UserPostResponse.fromBuffer,
      {
        'common': _common(),
        'uid': id,
        'pn': page,
        'offset': (page - 1) * 20,
        'rn': 20,
        'is_thread': replies ? 0 : 1,
        'need_content': 1,
      },
    );
    final records = _records(data['post_list']);
    return PageResult(
      items: records.map((entry) => _thread(entry)).toList(growable: false),
      page: page,
      hasMore: records.length >= 20,
    );
  }

  Future<PageResult<Forum>> userForums(String id, {int page = 1}) async {
    _id(id);
    _page(page);
    final self = transport.sessionProvider()?.userId;
    final data = await transport.form('/c/f/forum/like', {
      'page_no': page,
      'page_size': 50,
      'uid': self ?? id,
      'friend_uid': id,
      'is_guest': self == id ? 0 : 1,
    }, version: '7.2.0.0');
    final records = [
      ..._records(objectValue(data['forum_list'])['non-gconforum']),
      ..._records(objectValue(data['forum_list'])['gconforum']),
    ];
    if (records.isEmpty && data['forum_list'] is List) {
      records.addAll(_records(data['forum_list']));
    }
    return PageResult(
      items: records.map(_forum).toList(growable: false),
      page: page,
      hasMore: boolValue(data['has_more']),
    );
  }

  Future<Forum> forumDetail(String id) async {
    _id(id);
    final data = await _proto(
      '/c/f/forum/getforumdetail?cmd=303021&format=protobuf',
      detail.GetForumDetailRequest(),
      detail.GetForumDetailResponse.fromBuffer,
      {'common': _common(), 'forum_id': id},
    );
    return _forum(objectValue(data['forum_info']));
  }

  Future<List<ForumRule>> forumRules(String id) async {
    _id(id);
    final data = await _proto(
      '/c/f/forum/forumRuleDetail?cmd=309690&format=protobuf',
      rule.ForumRuleDetailRequest(),
      rule.ForumRuleDetailResponse.fromBuffer,
      {'common': _common(), 'forum_id': id},
    );
    final author = _first(objectValue(data['bazhu']), [
      'name_show',
      'user_name',
      'name',
    ]);
    return [
      if (stringValue(data['preface']).isNotEmpty)
        ForumRule(
          title: stringValue(data['title']),
          content: stringValue(data['preface']),
          parts: [ContentPart(text: stringValue(data['preface']))],
          author: author,
          publishedAt: stringValue(data['publish_time']),
        ),
      ..._records(data['rules']).map(
        (entry) => ForumRule(
          title: stringValue(entry['title']),
          content: _parts(entry['content']).map((part) => part.text).join(),
          parts: _parts(entry['content']),
          author: author,
          publishedAt: stringValue(data['publish_time']),
        ),
      ),
    ];
  }

  Future<void> signForum(Forum forum) async {
    final session = transport.requireSession();
    await transport.form('/c/c/forum/sign', {
      'fid': forum.id,
      'kw': forum.name,
      'tbs': _sessionTbs(session),
    }, authenticated: true);
  }

  Future<void> followForum(Forum forum, {bool follow = true}) async {
    final session = transport.requireSession();
    await transport.form(
      follow ? '/c/c/forum/like' : '/c/c/forum/unfavolike',
      {'fid': forum.id, 'kw': forum.name, 'tbs': _sessionTbs(session)},
      authenticated: true,
      version: follow ? '7.2.0.0' : '11.10.8.6',
    );
  }

  Future<void> followUser(UserProfile user, {bool follow = true}) async {
    final session = transport.requireSession();
    if (user.portrait.isEmpty) {
      throw const TiebaApiException(
        'This profile does not contain a portrait identifier.',
        code: 'missing_portrait',
      );
    }
    await transport.form(follow ? '/c/c/user/follow' : '/c/c/user/unfollow', {
      'portrait': user.portrait,
      'tbs': _sessionTbs(session),
      'authsid': 'null',
      'from_type': 2,
      'in_live': 0,
    }, authenticated: true);
  }

  Future<void> agree({
    required String threadId,
    String? postId,
    String forumId = '',
    bool undo = false,
  }) async {
    _id(threadId);
    final session = transport.requireSession();
    await transport.form(
      '/c/c/agree/opAgree',
      {
        'thread_id': threadId,
        'post_id': ?postId,
        'obj_type': postId == null ? 1 : 3,
        'agree_type': 2,
        'op_type': undo ? 1 : 0,
        'forum_id': forumId,
        'tbs': _sessionTbs(session),
        'personalized_rec_switch': 1,
      },
      authenticated: true,
      version: '12.25.1.0',
    );
  }

  Future<void> bookmark({
    required String threadId,
    String postId = '',
    bool remove = false,
  }) async {
    _id(threadId);
    final session = transport.requireSession();
    await transport.form(
      remove ? '/c/c/post/rmstore' : '/c/c/post/addstore',
      remove
          ? {
              'tid': threadId,
              'fid': 'null',
              'tbs': _sessionTbs(session),
              'user_id': session.userId,
            }
          : {
              'data': jsonEncode([
                {
                  'tid': threadId,
                  'pid': postId.isEmpty ? '0' : postId,
                  'status': 1,
                },
              ]),
            },
      authenticated: true,
      version: '12.25.1.0',
    );
  }

  Future<String> reply({
    required String content,
    required Forum forum,
    required String threadId,
    String? parentPostId,
    String? subPostId,
    String? replyUserId,
  }) async {
    transport.requireSession();
    _id(threadId);
    if (content.trim().isEmpty) {
      throw const TiebaApiException(
        'Write a reply before sending.',
        code: 'empty_content',
      );
    }
    final data = await _proto(
      '/c/c/post/add?cmd=309731&format=protobuf',
      add_post.AddPostRequest(),
      add_post.AddPostResponse.fromBuffer,
      {
        'common': _common(posting: true),
        'content': content,
        'fid': forum.id,
        'kw': forum.name,
        'tid': threadId,
        'name_show': transport.requireSession().user.name,
        'anonymous': '1',
        'can_no_forum': '0',
        'entrance_type': '0',
        'floor_num': '0',
        'is_ad': '0',
        'is_addition': '0',
        'is_barrage': '0',
        'is_feedback': '0',
        'is_giftpost': '0',
        'is_pictxt': '0',
        'is_twzhibo_thread': '0',
        'new_vcode': '1',
        'takephoto_num': '0',
        'vcode_tag': '12',
        if (parentPostId == null) 'barrage_time': '0',
        if (parentPostId == null) 'post_from': '13',
        if (parentPostId != null && subPostId == null) 'post_from': '0',
        'quote_id': ?parentPostId,
        'repostid': ?parentPostId,
        'sub_post_id': ?subPostId,
        'reply_uid': ?replyUserId,
      },
      authenticated: true,
      posting: true,
    );
    final pid = stringValue(data['pid']);
    if (pid.isEmpty) {
      throw const TiebaApiException(
        'The server did not confirm the reply. Check the thread before trying again.',
        code: 'reply_unconfirmed',
      );
    }
    return pid;
  }

  Future<UploadResult> uploadImage(
    Uint8List bytes, {
    required String filename,
    String forumName = '',
    int watermarkType = 2,
    bool saveOriginal = true,
  }) async {
    final accountId = transport.requireSession().userId;
    if (watermarkType < 0 || watermarkType > 2) {
      throw const TiebaApiException(
        'Choose a valid watermark type.',
        code: 'invalid_input',
      );
    }
    if (bytes.isEmpty || bytes.length > 10485760) {
      throw const TiebaApiException(
        'Choose an image smaller than 10 MiB.',
        code: 'invalid_image_size',
      );
    }
    var decoded = image.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const TiebaApiException(
        'The selected file is not a supported image.',
        code: 'invalid_image',
      );
    }
    var upload = bytes;
    if (upload.length > 5242880) {
      if (max(decoded.width, decoded.height) > 1920) {
        decoded = image.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 1920 : null,
          height: decoded.height > decoded.width ? 1920 : null,
        );
      }
      upload = Uint8List.fromList(image.encodeJpg(decoded, quality: 90));
    }
    if (upload.length > 10485760) {
      throw const TiebaApiException(
        'This image is too large after compression.',
        code: 'invalid_image_size',
      );
    }
    const chunkSize = 512000;
    final resourceId =
        '${md5.convert(upload).toString().toUpperCase()}$chunkSize';
    JsonMap result = {};
    for (var start = 0; start < upload.length; start += chunkSize) {
      if (transport.requireSession().userId != accountId) {
        throw const TiebaApiException(
          'The account changed during upload.',
          code: 'account_changed',
        );
      }
      final end = min(start + chunkSize, upload.length);
      result = await transport.upload('/c/s/uploadPicture', {
        'alt': 'json',
        'chunkNo': '${start ~/ chunkSize + 1}',
        'groupId': '1',
        'height': '${decoded.height}',
        'width': '${decoded.width}',
        'isFinish': end == upload.length ? '1' : '0',
        'is_bjh': '0',
        'pic_water_type': '$watermarkType',
        'resourceId': resourceId,
        'saveOrigin': saveOriginal ? '1' : '0',
        'size': '${upload.length}',
        if (forumName.isNotEmpty) 'forum_name': forumName,
        if (forumName.isNotEmpty) 'small_flow_fname': forumName,
      }, Uint8List.sublistView(upload, start, end));
    }
    final picture = objectValue(objectValue(result['pic_info'])['origin_pic']);
    final url = stringValue(picture['pic_url']);
    final id = stringValue(result['pic_id']);
    if (url.isEmpty || id.isEmpty) {
      throw const TiebaApiException(
        'The server did not confirm the uploaded image.',
        code: 'upload_unconfirmed',
      );
    }
    return UploadResult(
      url: _https(url),
      pictureId: id,
      width: decoded.width,
      height: decoded.height,
      size: upload.length,
    );
  }

  Future<void> updateProfile({
    required String nickname,
    required String intro,
    int? sex,
    String? birthday,
    bool? showBirthday,
  }) async {
    if (sex != null && (sex < 0 || sex > 2)) {
      throw const TiebaApiException(
        'Choose a valid profile gender.',
        code: 'invalid_input',
      );
    }
    await transport.form(
      '/c/c/profile/modify',
      {
        'nick_name': nickname,
        'intro': intro,
        'sex': ?sex,
        'birthday_time': ?birthday,
        if (showBirthday != null) 'birthday_show_status': showBirthday ? 1 : 0,
        'cam': '',
        'need_cam_decrypt': '1',
        'need_keep_nickname_flag': '0',
      },
      authenticated: true,
      version: '12.25.1.0',
    );
  }

  Future<void> uploadPortrait(
    Uint8List bytes, {
    String filename = 'portrait.jpg',
  }) async {
    transport.requireSession();
    if (bytes.isEmpty || bytes.length > 5242880) {
      throw const TiebaApiException(
        'Choose a portrait smaller than 5 MiB.',
        code: 'invalid_image_size',
      );
    }
    final decoded = image.decodeImage(bytes);
    if (decoded == null ||
        decoded.width <= 0 ||
        decoded.width != decoded.height) {
      throw const TiebaApiException(
        'Crop the portrait to a square image first.',
        code: 'invalid_image',
      );
    }
    await transport.upload(
      '/c/c/img/portrait',
      {},
      bytes,
      fieldName: 'pic',
      version: '11.10.8.6',
    );
  }

  Future<JsonMap> reportContext({
    String category = '1',
    required String threadId,
    String? postId,
    String? forumId,
  }) {
    if (postId == null || postId.isEmpty) {
      throw const TiebaApiException(
        'Open a post before reporting it.',
        code: 'missing_post',
      );
    }
    _id(postId);
    return transport.form(
      '/c/f/ueg/checkjubao',
      {'category': '1', 'pid': postId},
      authenticated: true,
      version: '12.25.1.0',
    );
  }

  Future<void> deletePost({
    required Forum forum,
    required String threadId,
    required String postId,
    bool subPost = false,
  }) async {
    final session = transport.requireSession();
    _id(threadId);
    _id(postId);
    await transport.form(
      '/c/c/bawu/delpost',
      {
        'fid': forum.id,
        'word': forum.name,
        'z': threadId,
        'pid': postId,
        'tbs': _sessionTbs(session),
        'isfloor': subPost ? 1 : 0,
        'src': subPost ? 3 : 1,
        'is_vipdel': 0,
        'delete_my_post': 1,
      },
      authenticated: true,
      version: '12.25.1.0',
    );
  }

  Future<void> deleteThread({
    required Forum forum,
    required String threadId,
  }) async {
    final session = transport.requireSession();
    _id(threadId);
    await transport.form(
      '/c/c/bawu/delthread',
      {
        'fid': forum.id,
        'word': forum.name,
        'z': threadId,
        'tbs': _sessionTbs(session),
        'src': 1,
        'is_vipdel': 0,
        'delete_my_thread': 1,
        'is_frs_mask': 0,
      },
      authenticated: true,
      version: '12.25.1.0',
    );
  }

  Future<JsonMap> _proto(
    String path,
    GeneratedMessage request,
    GeneratedMessage Function(List<int>) decode,
    JsonMap data, {
    bool authenticated = false,
    bool outerToken = true,
    bool posting = false,
    bool legacy = false,
  }) async {
    final accountId = transport.sessionProvider()?.userId;
    request.mergeFromProto3Json({'data': data});
    final response = await transport.protobuf(
      path,
      request,
      decode,
      authenticated: authenticated,
      outerToken: outerToken,
      posting: posting,
      legacy: legacy,
    );
    final token = _tbs(response);
    if (accountId != null && accountId.isNotEmpty && token.isNotEmpty) {
      _tbsTokens[accountId] = token;
    }
    return response;
  }

  String _sessionTbs(TiebaSession session) =>
      _tbsTokens[session.userId] ?? session.tbs;

  JsonMap _common({bool posting = false, bool legacy = false}) {
    final session = transport.sessionProvider();
    return {
      '_client_type': 2,
      '_client_version': posting
          ? '12.35.1.0'
          : legacy
          ? '11.10.8.6'
          : '12.52.1.0',
      '_client_id': 'wappc_${transport.deviceId.split('|').first}',
      '_timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      '_os_version': '33',
      'model': 'iPhone',
      'brand': 'Apple',
      'from': '1020031h',
      'cuid': transport.deviceId,
      'cuid_galaxy2': transport.deviceId,
      'net_type': 1,
      'pversion': '1.0.3',
      'lego_lib_version': '3.0.0',
      if (session?.bduss.isNotEmpty == true) 'BDUSS': session!.bduss,
      if (session?.stoken.isNotEmpty == true) 'stoken': session!.stoken,
      if (posting && session != null && _sessionTbs(session).isNotEmpty)
        'tbs': _sessionTbs(session),
      if (session?.zid.isNotEmpty == true) 'z_id': session!.zid,
    };
  }

  void close() => transport.close();
}

void _page(int value) {
  if (value < 1) {
    throw const TiebaApiException(
      'Page numbers start at 1.',
      code: 'invalid_input',
    );
  }
}

void _id(String value) {
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    throw const TiebaApiException(
      'This item has an invalid identifier.',
      code: 'invalid_input',
    );
  }
}

void _query(String value) {
  if (value.trim().isEmpty) {
    throw const TiebaApiException(
      'Enter a search term.',
      code: 'invalid_input',
    );
  }
}

String _first(JsonMap map, List<String> keys) {
  for (final key in keys) {
    final value = stringValue(map[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

List<JsonMap> _records(dynamic value) =>
    (value is List
            ? value
            : value is Map
            ? value.values.toList()
            : <dynamic>[])
        .whereType<Map>()
        .map((value) => objectValue(value))
        .toList();
String _https(String value) => value.startsWith('//')
    ? 'https:$value'
    : value.startsWith('http://')
    ? value.replaceFirst('http://', 'https://')
    : value;
String _httpUrl(String value) {
  final result = _https(value);
  final uri = Uri.tryParse(result);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? result
      : '';
}

String _stripHtml(String value) => value
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ');
DateTime? _date(dynamic value) {
  final n = intValue(value);
  return n <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(n < 100000000000 ? n * 1000 : n);
}

String _tbs(JsonMap data) => stringValue(objectValue(data['anti'])['tbs']);
bool _hasMore(JsonMap data, int count) {
  final page = objectValue(data['page']);
  return data['page'] is Map
      ? boolValue(page['has_more'])
      : data.containsKey('has_more')
      ? boolValue(data['has_more'])
      : count >= 15;
}

bool _isContent(JsonMap entry) =>
    entry['ala_info'] == null &&
    entry['advertisement'] == null &&
    intValue(entry['is_ad']) == 0;
Map<String, JsonMap> _users(dynamic values) => {
  for (final item in _records(values)) stringValue(item['id']): item,
};

UserProfile _user(JsonMap data) {
  final portrait = _first(data, ['portrait', 'user_portrait']);
  final avatar = portrait.startsWith('http') || portrait.startsWith('//')
      ? _https(portrait)
      : portrait.isEmpty
      ? ''
      : 'https://tb.himg.baidu.com/sys/portrait/item/$portrait';
  return UserProfile(
    id: _first(data, ['id', 'user_id', 'uid', 'lz_uid']),
    name: _first(data, [
      'name_show',
      'show_nickname',
      'user_nickname',
      'name',
      'user_name',
    ]),
    avatar: _https(
      _first(data, ['avatar', 'portraith']).isEmpty
          ? avatar
          : _first(data, ['avatar', 'portraith']),
    ),
    portrait: portrait,
    username: _first(data, ['name', 'user_name']),
    sex: intValue(data['sex']),
    birthday: stringValue(objectValue(data['birthday_info'])['birthday_time']),
    showBirthday: boolValue(
      objectValue(data['birthday_info'])['birthday_show_status'],
    ),
    level: intValue(data['level_id'] ?? data['level']),
    intro: _first(data, ['intro', 'display_intro']),
    isFollowing:
        boolValue(data['has_concerned']) || boolValue(data['is_friend']),
    followerCount: intValue(data['fans_num']),
    followingCount: intValue(data['concern_num']),
    threadCount: intValue(data['post_num']),
  );
}

Forum _forum(JsonMap data, {String fallbackName = ''}) => Forum(
  id: _first(data, ['id', 'forum_id', 'fid']),
  name: _first(data, ['name', 'forum_name', 'forum_name_show']).isEmpty
      ? fallbackName
      : _first(data, ['name', 'forum_name', 'forum_name_show']),
  avatar: _https(_first(data, ['avatar', 'avatar_url'])),
  description: _first(data, ['slogan', 'intro', 'description', 'desc']),
  memberCount: int.tryParse(
    stringValue(
      data['member_num'] ?? data['member_count'] ?? data['concern_num'],
    ),
  ),
  threadCount: intValue(
    data['thread_num'] ?? data['thread_count'] ?? data['post_num'],
  ),
  level: intValue(data['user_level'] ?? data['level_id']),
  isFollowing: boolValue(data['is_like']) || boolValue(data['has_concerned']),
  isSigned: boolValue(
    data['is_sign_in'] ??
        objectValue(
          objectValue(data['sign_in_info'])['user_info'],
        )['is_sign_in'],
  ),
);

ThreadSummary _thread(
  JsonMap data, {
  Forum? forum,
  Map<String, JsonMap> users = const {},
}) {
  final authorData = objectValue(data['author'] ?? data['user']);
  final author = _user(
    authorData.isNotEmpty
        ? authorData
        : users[stringValue(data['author_id'] ?? data['user_id'])] ??
              {
                'id': data['author_id'] ?? data['user_id'],
                'name': data['user_name'],
                'portrait': data['user_portrait'],
              },
  );
  final abstracts =
      data['abstract'] ??
      data['abstract_thread'] ??
      data['rich_abstract'] ??
      data['first_post_content'];
  final excerpt = abstracts is List
      ? _parts(abstracts).map((part) => part.text).join()
      : abstracts is String
      ? abstracts
      : _first(data, ['content', 'content_thread', '_abstract']);
  final media = _records(data['media'])
      .where(
        (entry) => _first(entry, [
          'big_pic',
          'origin_pic',
          'src',
          'small_pic',
          'water_pic',
        ]).isNotEmpty,
      )
      .toList();
  final images = media
      .map(
        (entry) => _https(
          _first(entry, [
            'big_pic',
            'origin_pic',
            'src',
            'small_pic',
            'water_pic',
          ]),
        ),
      )
      .where((url) => url.isNotEmpty)
      .toList();
  final thumbnails = media
      .map(
        (entry) => _httpUrl(
          _first(entry, [
            'small_pic',
            'big_pic',
            'origin_pic',
            'src',
            'water_pic',
          ]),
        ),
      )
      .toList(growable: false);
  final agree = objectValue(data['agree']);
  return ThreadSummary(
    id: _first(data, ['id', 'tid', 'thread_id']),
    title: _stripHtml(stringValue(data['title'])),
    author: author,
    forum:
        forum ??
        _forum({
          'forum_id': data['forum_id'],
          'forum_name': data['forum_name'],
          ...objectValue(data['forum_info']),
        }),
    excerpt: _stripHtml(excerpt),
    replyCount: intValue(
      data['reply_num'] ?? data['post_num'] ?? data['count'],
    ),
    likeCount: intValue(
      data['agree_num'] ?? data['like_num'] ?? agree['agree_num'],
    ),
    createdAt: _date(data['create_time'] ?? data['time'] ?? data['last_time']),
    images: images,
    imageThumbnails: thumbnails,
    isLiked: boolValue(agree['has_agree'] ?? data['user_agree']),
    isBookmarked: boolValue(data['is_collect'] ?? data['collect_status']),
    isPinned: boolValue(data['is_top']),
    isDigest: boolValue(data['is_good']),
    videoUrl: _https(stringValue(objectValue(data['video_info'])['video_url'])),
    lastPostId: _first(data, [
      'mark_pid',
      'collect_mark_pid',
      'post_id',
      'pid',
    ]),
  );
}

HotTopic _topic(JsonMap data) => HotTopic(
  id: _first(data, ['topic_id', 'id']),
  title: _first(data, ['topic_name', 'title']),
  excerpt: _first(data, ['topic_desc', 'desc']),
  imageUrl: _httpUrl(_first(data, ['topic_image', 'topic_pic', 'topicPic'])),
  hotCount: intValue(data['discuss_num']),
  tag: intValue(data['topic_tag'] ?? data['tag']),
  threadId: stringValue(data['topic_tid']),
  url: _httpUrl(stringValue(data['topic_h5_url'])),
);

Post _post(
  JsonMap data,
  String threadId,
  Map<String, JsonMap> users, {
  String parentId = '',
}) {
  final authorData = objectValue(data['author']);
  final id = _first(data, ['id', 'pid', 'post_id']);
  final agree = objectValue(data['agree']);
  final subPosts = objectValue(data['sub_post_list']);
  return Post(
    id: id,
    threadId: threadId,
    parentPostId: parentId,
    author: _user(
      authorData.isNotEmpty
          ? authorData
          : users[stringValue(data['author_id'])] ?? {},
    ),
    floor: intValue(data['floor']),
    createdAt: _date(data['time']),
    content: _parts(data['content']),
    replyCount: intValue(
      data['sub_post_number'] ?? subPosts['sub_post_number'],
    ),
    replies: _records(subPosts['sub_post_list'])
        .map((entry) => _post(entry, threadId, users, parentId: id))
        .toList(growable: false),
    likeCount: intValue(agree['agree_num']),
    isLiked: boolValue(agree['has_agree']),
  );
}

List<ContentPart> _parts(dynamic value) {
  if (value is String) return [ContentPart(text: _stripHtml(value))];
  return _records(value)
      .map((part) {
        final type = intValue(part['type']);
        final contentType = switch (type) {
          0 || 9 || 27 => ContentType.text,
          1 => ContentType.link,
          2 => ContentType.emoji,
          3 || 20 => ContentType.image,
          4 => ContentType.mention,
          5 => ContentType.video,
          10 => ContentType.audio,
          _ => ContentType.unknown,
        };
        final size = stringValue(part['bsize']).split(',');
        var url = _first(
          part,
          contentType == ContentType.image
              ? [
                  'origin_src',
                  'big_cdn_src',
                  'big_src',
                  'dynamic',
                  'cdn_src',
                  'cdn_src_active',
                  'src',
                ]
              : ['link', 'src', 'text'],
        );
        var text = stringValue(part['text']);
        if (contentType == ContentType.emoji) {
          final emojiId = stringValue(part['text']);
          text = stringValue(part['c']).isEmpty ? text : '#(${part['c']})';
          if (RegExp(r'^image_emoticon\d+$').hasMatch(emojiId)) {
            url =
                'https://tieba.baidu.com/tb/editor/images/client/$emojiId.png';
          }
        }
        if (contentType == ContentType.audio) {
          final voice = stringValue(part['voice_md5']);
          url = voice.isEmpty
              ? ''
              : 'https://tiebac.baidu.com/c/p/voice?voice_md5=${Uri.encodeQueryComponent(voice)}&play_from=pb_voice_play';
        }
        return ContentPart(
          type: contentType,
          text: text,
          url: _httpUrl(url),
          thumbnail: _https(_first(part, ['cdn_src', 'src', 'big_src'])),
          sourceId: contentType == ContentType.emoji
              ? stringValue(part['text'])
              : contentType == ContentType.mention
              ? stringValue(part['uid'])
              : '',
          caption: stringValue(part['c']),
          width: intValue(
            part['width'] ?? (size.isNotEmpty ? size.first : null),
          ),
          height: intValue(
            part['height'] ?? (size.length > 1 ? size[1] : null),
          ),
        );
      })
      .toList(growable: false);
}
