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
  });
  final String title;
  final Uri url;
  final String subtitle;
  final bool pinned;
}

class TextRun {
  const TextRun(this.text, {this.bold = false, this.italic = false, this.url});
  final String text;
  final bool bold;
  final bool italic;
  final Uri? url;
}

enum BlockKind { paragraph, quote, spoiler, code, image, link, embeddedMedia }

class BodyBlock {
  const BodyBlock(
    this.kind, {
    this.runs = const [],
    this.children = const [],
    this.label = '',
    this.url,
    this.posterUrl,
    this.aspectRatio,
    this.directMedia = false,
  });
  final BlockKind kind;
  final List<TextRun> runs;
  final List<BodyBlock> children;
  final String label;
  final Uri? url;
  final Uri? posterUrl;
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
  });
  final String id;
  final String author;
  final List<BodyBlock> blocks;
  final String date;
  final String number;
}

class ForumPage {
  const ForumPage({
    required this.url,
    required this.title,
    required this.kind,
    this.entries = const [],
    this.posts = const [],
    this.previous,
    this.next,
    this.pageNumber = 1,
    this.loggedIn = false,
  });
  final Uri url;
  final String title;
  final PageKind kind;
  final List<ForumEntry> entries;
  final List<ForumPost> posts;
  final Uri? previous;
  final Uri? next;
  final int pageNumber;
  final bool loggedIn;
}
