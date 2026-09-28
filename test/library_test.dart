import 'dart:convert';

import 'package:clean_forum/core/library.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/site.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLibraryStorage implements LibraryStorage {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failWrite) throw StateError('Storage unavailable');
    value = next;
  }
}

ForumPage visited(int id, {int page = 1}) => ForumPage(
  url: ForumSite.base.resolve(
    '/threads/topic.$id/${page == 1 ? '' : 'page-$page'}#post-$id',
  ),
  title: 'Topic $id',
  kind: PageKind.posts,
);

void main() {
  test(
    'bookmarks and reading progress survive a fresh library instance',
    () async {
      final storage = MemoryLibraryStorage();
      final first = ReadingLibrary(sample: false, storage: storage);
      await first.toggleBookmark(visited(1, page: 5).url, 'My saved page');
      await first.remember(visited(1, page: 5));
      final restarted = ReadingLibrary(sample: false, storage: storage);
      await restarted.load();
      expect(restarted.bookmarks.single.title, 'My saved page');
      expect(restarted.bookmarks.single.url, visited(1, page: 5).url);
      expect(restarted.recent.single.url.fragment, 'post-1');
    },
  );
  test(
    'recent reading keeps ten unique threads and their latest page',
    () async {
      final library = ReadingLibrary(
        sample: true,
        storage: MemoryLibraryStorage(),
      );
      for (var i = 1; i <= 12; i++) {
        await library.remember(visited(i));
      }
      await library.remember(visited(5, page: 3));
      expect(library.recent.length, 10);
      expect(library.recent.first.url, visited(5, page: 3).url);
      expect(library.recent.map((e) => e.title).toSet().length, 10);
      expect(library.recent.any((e) => e.title == 'Topic 1'), false);
    },
  );
  test(
    'concurrent updates retain both bookmark and history; clear is separate',
    () async {
      final library = ReadingLibrary(
        sample: true,
        storage: MemoryLibraryStorage(),
      );
      await Future.wait([
        library.toggleBookmark(visited(1).url, 'One'),
        library.remember(visited(2)),
        library.toggleBookmark(visited(3).url, 'Three'),
      ]);
      expect(library.bookmarks.length, 2);
      expect(library.recent.length, 1);
      await library.clearRecent();
      expect(library.recent, isEmpty);
      expect(library.bookmarks.length, 2);
    },
  );
  test(
    'failed persistence leaves visible state unchanged and can retry',
    () async {
      final storage = MemoryLibraryStorage()..failWrite = true;
      final library = ReadingLibrary(sample: false, storage: storage);
      await expectLater(
        library.toggleBookmark(visited(1).url, 'One'),
        throwsStateError,
      );
      expect(library.bookmarks, isEmpty);
      storage.failWrite = false;
      await library.toggleBookmark(visited(1).url, 'One');
      expect(library.bookmarks.length, 1);
      await library.toggleBookmark(visited(1).url, 'One');
      expect(library.bookmarks, isEmpty);
    },
  );
  test(
    'stored write routes and external links cannot enter the library',
    () async {
      final storage = MemoryLibraryStorage()
        ..value = jsonEncode({
          'version': 1,
          'bookmarks': [
            {
              'url': 'https://external.example/threads/topic.1/',
              'title': 'External',
            },
            {'url': 'https://simpcity.cr/logout/', 'title': 'Action'},
            {'url': visited(1).url.toString(), 'title': 'One'},
          ],
        });
      final library = ReadingLibrary(sample: false, storage: storage);
      await library.load();
      expect(library.bookmarks.single.title, 'One');
    },
  );
  test('unreadable storage is not silently overwritten', () async {
    final storage = MemoryLibraryStorage()..value = 'invalid data';
    final library = ReadingLibrary(sample: false, storage: storage);
    await expectLater(library.load(), throwsFormatException);
    await expectLater(
      library.toggleBookmark(visited(1).url, 'One'),
      throwsFormatException,
    );
    expect(storage.value, 'invalid data');
    storage.value = null;
    await library.load();
    expect(library.loaded, true);
  });
}
