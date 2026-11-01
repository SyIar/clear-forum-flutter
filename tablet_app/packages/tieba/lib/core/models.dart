import 'dart:typed_data';

typedef JsonMap = Map<String, dynamic>;
typedef SessionProvider = TiebaSession? Function();

enum FeedKind { personalized, concern, hot }

enum NotificationKind { replies, mentions, likes }

enum ContentType { text, image, link, mention, emoji, video, audio, unknown }

class TiebaSession {
  const TiebaSession({
    required this.bduss,
    required this.stoken,
    this.userId = '',
    this.tbs = '',
    this.rawCookie = '',
    this.zid = '',
    this.user = const UserProfile(),
  });
  final String bduss, stoken, userId, tbs, rawCookie, zid;
  final UserProfile user;
  bool get isAuthenticated => bduss.isNotEmpty && stoken.isNotEmpty;
  TiebaSession copyWith({
    String? userId,
    String? tbs,
    String? zid,
    UserProfile? user,
  }) => TiebaSession(
    bduss: bduss,
    stoken: stoken,
    userId: userId ?? this.userId,
    tbs: tbs ?? this.tbs,
    rawCookie: rawCookie,
    zid: zid ?? this.zid,
    user: user ?? this.user,
  );
  JsonMap toJson() => {
    'bduss': bduss,
    'stoken': stoken,
    'userId': userId,
    'tbs': tbs,
    'rawCookie': rawCookie,
    'zid': zid,
    'user': user.toJson(),
  };
  factory TiebaSession.fromJson(JsonMap json) => TiebaSession(
    bduss: stringValue(json['bduss']),
    stoken: stringValue(json['stoken']),
    userId: stringValue(json['userId']),
    tbs: stringValue(json['tbs']),
    rawCookie: stringValue(json['rawCookie']),
    zid: stringValue(json['zid']),
    user: UserProfile.fromJson(objectValue(json['user'])),
  );
}

class UserProfile {
  const UserProfile({
    this.id = '',
    this.name = '',
    this.username = '',
    this.avatar = '',
    this.portrait = '',
    this.level = 0,
    this.intro = '',
    this.isFollowing = false,
    this.followerCount = 0,
    this.followingCount = 0,
    this.threadCount = 0,
    this.sex = 0,
    this.birthday = '',
    this.showBirthday = false,
  });
  final String id, name, username, avatar, portrait, intro, birthday;
  final int level, followerCount, followingCount, threadCount, sex;
  final bool isFollowing, showBirthday;
  JsonMap toJson() => {
    'id': id,
    'name': name,
    'username': username,
    'sex': sex,
    'birthday': birthday,
    'showBirthday': showBirthday,
    'avatar': avatar,
    'portrait': portrait,
    'level': level,
    'intro': intro,
    'isFollowing': isFollowing,
    'followerCount': followerCount,
    'followingCount': followingCount,
    'threadCount': threadCount,
  };
  factory UserProfile.fromJson(JsonMap json) => UserProfile(
    id: stringValue(json['id']),
    name: stringValue(json['name']),
    username: stringValue(json['username']),
    sex: intValue(json['sex']),
    birthday: stringValue(json['birthday']),
    showBirthday: boolValue(json['showBirthday']),
    avatar: stringValue(json['avatar']),
    portrait: stringValue(json['portrait']),
    level: intValue(json['level']),
    intro: stringValue(json['intro']),
    isFollowing: boolValue(json['isFollowing']),
    followerCount: intValue(json['followerCount']),
    followingCount: intValue(json['followingCount']),
    threadCount: intValue(json['threadCount']),
  );
}

class Forum {
  const Forum({
    this.id = '',
    this.name = '',
    this.avatar = '',
    this.description = '',
    this.memberCount,
    this.threadCount = 0,
    this.level = 0,
    this.isFollowing = false,
    this.isSigned = false,
  });
  final String id, name, avatar, description;
  final int? memberCount;
  final int threadCount, level;
  final bool isFollowing, isSigned;
  Forum copyWith({bool? isSigned}) => Forum(
    id: id,
    name: name,
    avatar: avatar,
    description: description,
    memberCount: memberCount,
    threadCount: threadCount,
    level: level,
    isFollowing: isFollowing,
    isSigned: isSigned ?? this.isSigned,
  );
  JsonMap toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'description': description,
    'memberCount': memberCount,
    'threadCount': threadCount,
    'level': level,
    'isFollowing': isFollowing,
    'isSigned': isSigned,
  };
  factory Forum.fromJson(JsonMap json) => Forum(
    id: stringValue(json['id']),
    name: stringValue(json['name']),
    avatar: stringValue(json['avatar']),
    description: stringValue(json['description']),
    memberCount: json['memberCount'] == null
        ? null
        : intValue(json['memberCount']),
    threadCount: intValue(json['threadCount']),
    level: intValue(json['level']),
    isFollowing: boolValue(json['isFollowing']),
    isSigned: boolValue(json['isSigned']),
  );
}

class ContentPart {
  const ContentPart({
    this.type = ContentType.text,
    this.text = '',
    this.url = '',
    this.thumbnail = '',
    this.sourceId = '',
    this.caption = '',
    this.width = 0,
    this.height = 0,
  });
  final ContentType type;
  final String text, url, thumbnail, sourceId, caption;
  final int width, height;
}

class ThreadSummary {
  const ThreadSummary({
    this.id = '',
    this.title = '',
    this.author = const UserProfile(),
    this.forum = const Forum(),
    this.excerpt = '',
    this.replyCount = 0,
    this.likeCount = 0,
    this.createdAt,
    this.images = const [],
    this.imageThumbnails = const [],
    this.isLiked = false,
    this.isBookmarked = false,
    this.isPinned = false,
    this.isDigest = false,
    this.videoUrl = '',
    this.lastPostId = '',
  });
  final String id, title, excerpt, videoUrl, lastPostId;
  final UserProfile author;
  final Forum forum;
  final int replyCount, likeCount;
  final DateTime? createdAt;
  final List<String> images, imageThumbnails;
  final bool isLiked, isBookmarked, isPinned, isDigest;
  JsonMap toJson() => {
    'id': id,
    'title': title,
    'author': author.toJson(),
    'forum': forum.toJson(),
    'excerpt': excerpt,
    'replyCount': replyCount,
    'likeCount': likeCount,
    'createdAt': createdAt?.toIso8601String(),
    'images': images,
    'imageThumbnails': imageThumbnails,
    'lastPostId': lastPostId,
  };
  factory ThreadSummary.fromJson(JsonMap json) => ThreadSummary(
    id: stringValue(json['id']),
    title: stringValue(json['title']),
    author: UserProfile.fromJson(objectValue(json['author'])),
    forum: Forum.fromJson(objectValue(json['forum'])),
    excerpt: stringValue(json['excerpt']),
    replyCount: intValue(json['replyCount']),
    likeCount: intValue(json['likeCount']),
    createdAt: DateTime.tryParse(stringValue(json['createdAt'])),
    images: listValue(json['images']).map(stringValue).toList(),
    imageThumbnails: listValue(json['imageThumbnails'])
        .map(stringValue)
        .toList(),
    lastPostId: stringValue(json['lastPostId']),
  );
}

class Post {
  const Post({
    this.id = '',
    this.threadId = '',
    this.author = const UserProfile(),
    this.floor = 0,
    this.createdAt,
    this.content = const [],
    this.replyCount = 0,
    this.replies = const [],
    this.isLiked = false,
    this.likeCount = 0,
    this.parentPostId = '',
  });
  final String id, threadId, parentPostId;
  final UserProfile author;
  final int floor, replyCount, likeCount;
  final DateTime? createdAt;
  final List<ContentPart> content;
  final List<Post> replies;
  final bool isLiked;
  String get plainText => content.map((part) => part.text).join();
}

class NotificationItem {
  const NotificationItem({
    this.id = '',
    this.kind = NotificationKind.replies,
    this.author = const UserProfile(),
    this.threadId = '',
    this.postId = '',
    this.title = '',
    this.content = '',
    this.createdAt,
    this.isRead = false,
  });
  final String id, threadId, postId, title, content;
  final NotificationKind kind;
  final UserProfile author;
  final DateTime? createdAt;
  final bool isRead;
}

class PageResult<T> {
  const PageResult({
    this.items = const [],
    this.page = 1,
    this.hasMore = false,
    this.forum,
    this.thread,
    this.tbs = '',
    this.total = 0,
    this.topic,
    this.relatedForums = const [],
  });
  final List<T> items;
  final int page, total;
  final bool hasMore;
  final Forum? forum;
  final ThreadSummary? thread;
  final String tbs;
  final HotTopic? topic;
  final List<Forum> relatedForums;
}

class HotTopic {
  const HotTopic({
    this.id = '',
    this.title = '',
    this.excerpt = '',
    this.imageUrl = '',
    this.hotCount = 0,
    this.tag = 0,
    this.threadId = '',
    this.url = '',
  });
  final String id, title, excerpt, imageUrl, threadId, url;
  final int hotCount, tag;
}

class HotTab {
  const HotTab({this.id = '', this.title = '', this.code = ''});
  final String id, title, code;
}

class HotOverview {
  const HotOverview({
    this.topics = const [],
    this.threads = const [],
    this.tabs = const [],
  });
  final List<HotTopic> topics;
  final List<ThreadSummary> threads;
  final List<HotTab> tabs;
}

class UploadResult {
  const UploadResult({
    required this.url,
    required this.pictureId,
    this.width = 0,
    this.height = 0,
    this.size = 0,
  });
  final String url, pictureId;
  final int width, height, size;
}

class ForumRule {
  const ForumRule({
    this.title = '',
    this.content = '',
    this.parts = const [],
    this.author = '',
    this.publishedAt = '',
  });
  final String title, content, author, publishedAt;
  final List<ContentPart> parts;
}

class ImageUpload {
  const ImageUpload({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

String stringValue(dynamic value) => value == null ? '' : value.toString();
int intValue(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(stringValue(value)) ?? 0;
bool boolValue(dynamic value) => value == true || value == 1 || value == '1';
JsonMap objectValue(dynamic value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};
List<dynamic> listValue(dynamic value) => value is List ? value : <dynamic>[];
