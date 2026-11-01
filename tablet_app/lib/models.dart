import 'south_purchase.dart';
import 'south_poll.dart';

enum PageKind { forums, threads, posts }

enum FailureKind {
  login,
  verification,
  forbidden,
  rateLimit,
  network,
  unsupported,
}

class ReaderFailure implements Exception {
  const ReaderFailure(this.kind, [this.status]);
  final FailureKind kind;
  final int? status;
}

class ForumEntry {
  const ForumEntry({
    required this.title,
    required this.url,
    this.subtitle = '',
    this.pinned = false,
    this.date = '',
    this.tags = const [],
    this.authorID = '',
    this.thumbnail,
    this.totalPosts,
  });
  final String title;
  final Uri url;
  final String subtitle;
  final bool pinned;
  final String date, authorID;
  final List<String> tags;
  final Uri? thumbnail;
  final int? totalPosts;
  ForumEntry copyWith({String? title, Uri? url, String? subtitle}) =>
      ForumEntry(
        title: title ?? this.title,
        url: url ?? this.url,
        subtitle: subtitle ?? this.subtitle,
        pinned: pinned,
        date: date,
        tags: tags,
        authorID: authorID,
        thumbnail: thumbnail,
        totalPosts: totalPosts,
      );
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': '$url',
    'subtitle': subtitle,
    'date': date,
    'tags': tags,
    'authorID': authorID,
    'pinned': pinned,
    'thumbnail': thumbnail?.toString(),
    'totalPosts': totalPosts,
  };
  factory ForumEntry.fromJson(Map<String, dynamic> data) => ForumEntry(
    title: data['title'] as String,
    url: Uri.parse(data['url'] as String),
    subtitle: data['subtitle'] as String? ?? '',
    date: data['date'] as String? ?? '',
    tags: List<String>.from(data['tags'] as List? ?? []),
    authorID: data['authorID'] as String? ?? '',
    pinned: data['pinned'] as bool? ?? false,
    thumbnail: data['thumbnail'] is String
        ? Uri.tryParse(data['thumbnail'] as String)
        : null,
    totalPosts: data['totalPosts'] as int?,
  );
}

class TextRun {
  const TextRun(this.text, {this.bold = false, this.italic = false, this.url});
  final String text;
  final bool bold;
  final bool italic;
  final Uri? url;
}

enum BlockKind {
  paragraph,
  quote,
  spoiler,
  code,
  image,
  link,
  embeddedMedia,
  purchase,
}

class BodyBlock {
  const BodyBlock(
    this.kind, {
    this.runs = const [],
    this.children = const [],
    this.label = '',
    this.url,
    this.posterUrl,
    this.originalUrl,
    this.offer,
    this.aspectRatio,
    this.directMedia = false,
  });
  final BlockKind kind;
  final List<TextRun> runs;
  final List<BodyBlock> children;
  final String label;
  final Uri? url;
  final Uri? posterUrl;
  final Uri? originalUrl;
  final PurchaseOffer? offer;
  final double? aspectRatio;
  final bool directMedia;
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.author,
    required this.blocks,
    this.date = '',
    this.number = '',
    this.avatar,
    this.authorID = '',
  });
  final String id;
  final String author;
  final List<BodyBlock> blocks;
  final String date;
  final String number;
  final Uri? avatar;
  final String authorID;
  int? get floor =>
      int.tryParse(number.replaceAll('#', '').replaceAll(',', ''));
}

class ForumPage {
  const ForumPage({
    required this.url,
    required this.title,
    required this.kind,
    this.poll,
    this.entries = const [],
    this.posts = const [],
    this.previous,
    this.next,
    this.pageNumber = 1,
    this.loggedIn = false,
    this.lastPage,
    this.totalPages = 1,
    this.originalPosterID,
    this.terminalConfirmed = true,
    this.pageCountConfirmed = false,
  });
  final Uri url;
  final SouthPoll? poll;
  final String title;
  final PageKind kind;
  final List<ForumEntry> entries;
  final List<ForumPost> posts;
  final Uri? previous;
  final Uri? next;
  final int pageNumber;
  final bool loggedIn;
  final Uri? lastPage;
  final int totalPages;
  final String? originalPosterID;
  final bool terminalConfirmed;
  final bool pageCountConfirmed;
  int? get maximumPostNumber =>
      terminalConfirmed && next == null && totalPages <= pageNumber
      ? posts
            .map((p) => p.floor)
            .nonNulls
            .fold<int?>(null, (n, f) => n == null || f > n ? f : n)
      : null;
}
