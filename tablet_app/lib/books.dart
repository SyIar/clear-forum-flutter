import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'parsers.dart';
import 'session.dart';
import 'site.dart';
import 'strings.dart';
import 'forum_identity.dart';

int? chapterNumber(String? text) {
  if (text == null || text.isEmpty) return null;
  final decimal = int.tryParse(text);
  if (decimal != null) return decimal > 0 && decimal <= 100000 ? decimal : null;
  final digits = AppStrings.numbers('chapterDigits'),
      units = AppStrings.numbers('chapterUnits');
  if (text.split('').every(digits.containsKey)) {
    return chapterNumber(text.split('').map((c) => digits[c]).join());
  }
  var total = 0, section = 0, digit = 0;
  for (final char in text.split('')) {
    if (digits.containsKey(char)) {
      digit = digits[char]!;
    } else if (units.containsKey(char)) {
      final unit = units[char]!;
      if (unit == 10000) {
        total += (section + digit) * unit;
        section = 0;
      } else {
        section += (digit == 0 ? 1 : digit) * unit;
      }
      digit = 0;
    } else {
      return null;
    }
  }
  return chapterNumber('${total + section + digit}');
}

class ChapterAnchors {
  ChapterAnchors(List<BodyBlock> blocks, BookChapter chapter) {
    var last = chapter.first - 1;
    final seen = <int>{};
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (block.kind != BlockKind.paragraph) continue;
      final text = block.runs.map((r) => r.text).join().trim();
      if (text.length > 120) continue;
      final number = chapterNumber(
        AppStrings.pattern(
          chapter.extra ? 'extraHeadingPattern' : 'chapterHeadingPattern',
        ).firstMatch(text)?[1],
      );
      if (number == null ||
          number < chapter.first ||
          number > chapter.last ||
          number < last ||
          !seen.add(number)) {
        continue;
      }
      byParagraph[index] = number;
      last = number;
    }
  }
  final Map<int, int> byParagraph = {};
  int? paragraph(int number) =>
      byParagraph.entries.where((e) => e.value == number).firstOrNull?.key;
  int chapterAt(int paragraph, int fallback) =>
      byParagraph.entries.where((e) => e.key <= paragraph).lastOrNull?.value ??
      fallback;
}

class BookChapter {
  BookChapter(this.entry) {
    final range =
        AppStrings.pattern('chapterPattern').firstMatch(entry.title) ??
        AppStrings.pattern('chapterRangePattern').firstMatch(entry.title);
    first = chapterNumber(range?[1]) ?? 0;
    last = chapterNumber(range?[2]) ?? first;
    extra = AppStrings.pattern('extraPattern').hasMatch(entry.title);
    final partMatch = AppStrings.pattern('chapterPartPattern')
        .firstMatch(entry.title);
    part =
        AppStrings.numbers('chapterParts')[partMatch?[1] ?? partMatch?[2]] ?? 0;
  }
  final ForumEntry entry;
  late final int first, last;
  late final bool extra;
  late final int part;
}

// Keep publication ranges separate from chapter numbers. Reposted bundles can
// overlap; remove duplicate text only at a heading actually found in the body.
class BookSlice {
  BookSlice(this.chapter, this.blocks, {this.start = 0, int? end})
    : end = end ?? blocks.length;
  final BookChapter chapter;
  final List<BodyBlock> blocks;
  final int start, end;
  BookSlice joined(BookSlice boundary, {required bool before}) {
    if (chapter.extra != boundary.chapter.extra ||
        (chapter.part > 0 &&
            boundary.chapter.part > 0 &&
            chapter.first == boundary.chapter.first &&
            chapter.last == boundary.chapter.last)) {
      return this;
    }
    final anchors = ChapterAnchors(blocks, chapter);
    if (before) {
      final number = boundary.chapter.first - 1;
      if (chapter.first > number || chapter.last < number) {
        throw const FormatException('Missing previous chapter');
      }
      if (chapter.last > number) {
        final stop = anchors.paragraph(number + 1);
        if (stop == null || stop == 0) {
          throw const FormatException(
            'Unverified overlapping chapter boundary',
          );
        }
        return BookSlice(chapter, blocks, end: stop);
      }
    } else {
      final number = boundary.chapter.last + 1;
      if (chapter.first > number || chapter.last < number) {
        throw const FormatException('Missing next chapter');
      }
      if (chapter.first < number) {
        final begin = anchors.paragraph(number);
        if (begin == null) {
          throw const FormatException(
            'Unverified overlapping chapter boundary',
          );
        }
        return BookSlice(chapter, blocks, start: begin);
      }
    }
    return this;
  }
}

class FollowedBook {
  FollowedBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.position,
    this.checked = 0,
    this.attempted = 0,
    this.cachePending = false,
    this.readChapter,
  });
  final String title, author;
  List<BookChapter> chapters;
  Uri? position;
  int checked, attempted;
  int? readChapter;
  bool cachePending;
  String? status;
  int get latest => chapters
      .where((c) => !c.extra)
      .fold(0, (n, c) => c.last > n ? c.last : n);
  BookChapter? get current =>
      chapters
          .where(
            (c) =>
                const ForumSite(Module.bookhouse)
                    .sameThread(c.entry.url, position ?? Uri()),
          )
          .firstOrNull ??
      chapters.firstOrNull;
  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'chapters': chapters.map((c) => c.entry.toJson()).toList(),
    'position': position?.toString(),
    'checked': checked,
    'attempted': attempted,
    'cachePending': cachePending,
    'readChapter': readChapter,
  };
  factory FollowedBook.fromJson(Map data) => FollowedBook(
    title: data['title'] as String,
    author: data['author'] as String,
    chapters: (data['chapters'] as List)
        .map(
          (e) => BookChapter(
            ForumEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          ),
        )
        .toList(),
    position: Uri.tryParse(data['position'] as String? ?? ''),
    checked: data['checked'] as int? ?? 0,
    attempted: data['attempted'] as int? ?? 0,
    cachePending: data['cachePending'] as bool? ?? false,
    readChapter: data['readChapter'] as int?,
  );
}

class BookLibrary extends ChangeNotifier {
  BookLibrary(this.preferences, this.session) {
    try {
      books.addAll(
        (jsonDecode(preferences.getString('books.v1') ?? '[]') as List).map(
          (e) => FollowedBook.fromJson(e as Map),
        ),
      );
    } catch (_) {
      readOnly = true;
    }
  }
  final SharedPreferences preferences;
  final ForumSession session;
  final List<FollowedBook> books = [];
  final Set<FollowedBook> caching = {};
  bool readOnly = false, checking = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _persist() async {
    if (readOnly) return;
    await preferences.setString(
      'books.v1',
      jsonEncode(books.map((b) => b.toJson()).toList()),
    );
    notifyListeners();
  }

  String titleFor(ForumEntry entry) =>
      AppStrings.pattern('bookTitlePattern').firstMatch(entry.title)?[1] ??
      entry.title
          .replaceAll(AppStrings.pattern('chapterPattern'), '')
          .replaceAll(AppStrings.pattern('chapterRangePattern'), '')
          .trim();
  Future<FollowedBook> follow(
    ForumEntry entry,
    String title,
    String author,
  ) async {
    if (readOnly) {
      throw const FormatException('Preserved unreadable book library');
    }
    var book = books
        .where((b) => b.title == title && b.author == author)
        .firstOrNull;
    if (book == null) {
      book = FollowedBook(
        title: title,
        author: author,
        chapters: [BookChapter(entry)],
        position: entry.url,
      );
      books.insert(0, book);
      await _persist();
    }
    unawaited(update(book, manual: true));
    return book;
  }

  Future<void> remove(FollowedBook book) async {
    books.remove(book);
    await _persist();
  }

  FollowedBook? bookFor(Uri url) => books
      .where(
        (b) => b.chapters.any((c) => session.site.sameThread(c.entry.url, url)),
      )
      .firstOrNull;
  BookChapter? publication(Uri url) =>
      bookFor(url)?.chapters
          .where((c) => session.site.sameThread(c.entry.url, url))
          .firstOrNull;
  Uri? jumpTo(FollowedBook book, int number, {bool extra = false}) {
    final choices =
        book.chapters
            .where(
              (c) => c.extra == extra && c.first <= number && c.last >= number,
            )
            .toList()
          ..sort((a, b) => a.part.compareTo(b.part));
    return choices.firstOrNull?.entry.url.replace(fragment: 'chapter-$number');
  }

  Uri? adjacent(Uri url, int offset) {
    if (offset != -1 && offset != 1) return null;
    final book = bookFor(url);
    if (book == null) return null;
    final index = book.chapters.indexWhere(
      (c) => session.site.sameThread(c.entry.url, url),
    );
    if (index < 0) return null;
    final current = book.chapters[index];
    for (
      var i = index + offset;
      i >= 0 && i < book.chapters.length;
      i += offset
    ) {
      final candidate = book.chapters[i];
      if (candidate.extra != current.extra ||
          (candidate.part > 0 &&
              current.part > 0 &&
              candidate.first == current.first &&
              candidate.last == current.last) ||
          (offset > 0
              ? candidate.last > current.last
              : candidate.first < current.first)) {
        return candidate.entry.url;
      }
    }
    return null;
  }

  Future<void> record(Uri url, {int? chapter}) async {
    final book = bookFor(url);
    if (book == null ||
        (book.position == url &&
            (chapter == null || chapter == book.readChapter))) {
      return;
    }
    book.position = url;
    if (chapter != null) book.readChapter = chapter;
    await _persist();
  }

  Future<void> updateAll({bool manual = false}) async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      for (final book in List.of(books)) {
        await update(book, manual: manual);
      }
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> update(FollowedBook book, {bool manual = false}) async {
    if (readOnly ||
        !books.contains(book) ||
        book.status == 'Loading' ||
        (!manual &&
            DateTime.now().millisecondsSinceEpoch - book.attempted < 3600000) ||
        DateTime.now().millisecondsSinceEpoch - book.checked < 3600000) {
      return;
    }
    book.status = 'Loading';
    book.attempted = DateTime.now().millisecondsSinceEpoch;
    await _persist();
    try {
      final query = String.fromCharCodes(book.title.runes.take(7));
      Uri? next = const ForumSite(Module.bookhouse).search(query);
      final seen = <Uri>{};
      final found = <BookChapter>[];
      while (next != null && seen.add(next) && seen.length <= 200) {
        final capture = await session.fetch(next);
        if (capture.cached) throw const ReaderFailure(FailureKind.network);
        final page = PageParser(session.site).parse(capture.html, capture.url);
        found.addAll(
          page.entries
              .where((e) => e.subtitle.trim() == book.author.trim())
              .map(BookChapter.new),
        );
        next = page.next;
      }
      if (found.isEmpty) {
        throw const FormatException('No matching author chapters');
      }
      if (!books.contains(book) || _disposed) return;
      final merged = {
        for (final chapter in book.chapters) '${chapter.entry.url}': chapter,
        for (final chapter in found) '${chapter.entry.url}': chapter,
      };
      book.chapters = merged.values.toList()
        ..sort((a, b) {
          if (a.extra != b.extra) return a.extra ? 1 : -1;
          final first = a.first.compareTo(b.first);
          if (first != 0) return first;
          final part = a.part.compareTo(b.part);
          return part != 0 ? part : a.entry.title.compareTo(b.entry.title);
        });
      book.checked = DateTime.now().millisecondsSinceEpoch;
      book.status = 'Updated';
      await _persist();
    } catch (_) {
      book.status = 'Failed';
      notifyListeners();
    }
  }

  Future<void> cacheAll(FollowedBook book) async {
    if (readOnly || !books.contains(book) || !caching.add(book)) return;
    book.cachePending = true;
    await _persist();
    try {
      for (final chapter in List.of(book.chapters)) {
        if (!books.contains(book) || _disposed) return;
        if (await session.cached(chapter.entry.url) != null) continue;
        final capture = await session.fetch(chapter.entry.url);
        if (capture.cached) throw const ReaderFailure(FailureKind.network);
        notifyListeners();
      }
      book.cachePending = false;
      await _persist();
    } catch (_) {
      book.status = 'Failed';
      notifyListeners();
    } finally {
      caching.remove(book);
      notifyListeners();
    }
  }

  Future<List<(ForumEntry, String)>> searchCache(
    FollowedBook book,
    String keyword,
  ) async {
    if (keyword.trim().isEmpty) return [];
    final result = <(ForumEntry, String)>[];
    for (final chapter in book.chapters) {
      final capture = await session.cached(chapter.entry.url);
      if (capture == null) continue;
      final page = PageParser(session.site).parse(capture.html, capture.url);
      String plain(List<BodyBlock> blocks) => blocks
          .map((b) => b.runs.map((r) => r.text).join() + plain(b.children))
          .join('\n');
      final blocks = page.posts.firstOrNull?.blocks ?? const <BodyBlock>[];
      for (var paragraph = 0; paragraph < blocks.length; paragraph++) {
        final text = plain([blocks[paragraph]]);
        final index = text.toLowerCase().indexOf(keyword.trim().toLowerCase());
        if (index >= 0) {
          result.add((
            chapter.entry.copyWith(
              url: chapter.entry.url.replace(fragment: 'novel-p-$paragraph'),
            ),
            text.substring(
              (index - 35).clamp(0, text.length),
              (index + 100).clamp(0, text.length),
            ),
          ));
          if (result.length >= 500) return result;
        }
      }
    }
    return result;
  }
}
