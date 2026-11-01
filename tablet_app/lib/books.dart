import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'parsers.dart';
import 'session.dart';
import 'site.dart';
import 'strings.dart';

class BookChapter {
  BookChapter(this.entry) {
    final range =
        AppStrings.pattern('chapterPattern').firstMatch(entry.title) ??
        AppStrings.pattern('chapterRangePattern').firstMatch(entry.title);
    first = int.tryParse(range?[1] ?? '') ?? 0;
    last = int.tryParse(range?[2] ?? '') ?? first;
    extra = AppStrings.pattern('extraPattern').hasMatch(entry.title);
  }
  final ForumEntry entry;
  late final int first, last;
  late final bool extra;
}

class FollowedBook {
  FollowedBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.position,
    this.checked = 0,
    this.cachePending = false,
  });
  final String title, author;
  List<BookChapter> chapters;
  Uri? position;
  int checked;
  bool cachePending;
  String? status;
  int get latest => chapters
      .where((c) => !c.extra)
      .fold(0, (n, c) => c.last > n ? c.last : n);
  BookChapter? get current =>
      chapters.where((c) => c.entry.url == position).firstOrNull ??
      chapters.firstOrNull;
  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'chapters': chapters.map((c) => c.entry.toJson()).toList(),
    'position': position?.toString(),
    'checked': checked,
    'cachePending': cachePending,
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
    cachePending: data['cachePending'] as bool? ?? false,
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
    unawaited(update(book));
    return book;
  }

  Future<void> remove(FollowedBook book) async {
    books.remove(book);
    await _persist();
  }

  FollowedBook? bookFor(Uri url) =>
      books.where((b) => b.chapters.any((c) => c.entry.url == url)).firstOrNull;
  Uri? adjacent(Uri url, int offset) {
    final book = bookFor(url);
    if (book == null) return null;
    final index = book.chapters.indexWhere((c) => c.entry.url == url) + offset;
    return index >= 0 && index < book.chapters.length
        ? book.chapters[index].entry.url
        : null;
  }

  Future<void> record(Uri url) async {
    final book = bookFor(url);
    if (book == null || book.position == url) return;
    book.position = url;
    await _persist();
  }

  Future<void> updateAll() async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      for (final book in List.of(books)) {
        await update(book);
      }
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> update(FollowedBook book) async {
    if (book.status == 'Loading' ||
        DateTime.now().millisecondsSinceEpoch - book.checked < 3600000) {
      return;
    }
    book.status = 'Loading';
    notifyListeners();
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
      final merged = {
        for (final chapter in book.chapters) '${chapter.entry.url}': chapter,
        for (final chapter in found) '${chapter.entry.url}': chapter,
      };
      book.chapters = merged.values.toList()
        ..sort((a, b) {
          if (a.extra != b.extra) return a.extra ? 1 : -1;
          final first = a.first.compareTo(b.first);
          return first == 0 ? a.entry.title.compareTo(b.entry.title) : first;
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
    if (!caching.add(book)) return;
    book.cachePending = true;
    await _persist();
    try {
      for (final chapter in List.of(book.chapters)) {
        if (!books.contains(book)) break;
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
      final text = page.posts.map((p) => plain(p.blocks)).join('\n');
      final index = text.toLowerCase().indexOf(keyword.toLowerCase());
      if (index >= 0) {
        result.add((
          chapter.entry,
          text.substring(
            (index - 35).clamp(0, text.length),
            (index + 100).clamp(0, text.length),
          ),
        ));
      }
    }
    return result;
  }
}
