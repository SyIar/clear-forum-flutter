import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/forum_identity.dart';
import 'package:forum_tablet/models.dart';
import 'package:forum_tablet/offline_threads.dart';
import 'package:forum_tablet/session.dart';
import 'package:forum_tablet/site.dart';

const south = ForumSite(Module.south);
final root = south.home.resolve('/read.php?tid=20');
PageCapture capture(int number, {int total = 2, int tid = 20}) => PageCapture(
  south.pageUrl(south.home.resolve('/read.php?tid=$tid'), number),
  '<h1 id="subject_tpc">Thread</h1><div class="pagesone">Pages: $number/$total</div>'
  '<table class="js-post"><tr><td><a href="u.php?uid=42"><img src="/avatar.png"><b>Writer</b></a>'
  '<div class="tiptop"><a>#$number</a></div><div class="tpc_content" id="read_$number">'
  '<img src="https://images.example/preview.png" data-original="https://images.example/full.png">'
  '<a href="job.php?action-download-pid-10-tid-20-aid-30.html">archive.zip</a>'
  '</div></td></tr></table>',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final stores = <OfflineThreads>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('forum-offline-');
  });
  tearDown(() async {
    for (final store in stores) {
      store.dispose();
      await store.idle;
    }
    stores.clear();
    await directory.delete(recursive: true);
  });
  OfflineThreads create({
    required Future<PageCapture> Function(Uri) page,
    OfflineImageLoader? image,
  }) {
    final store = OfflineThreads(
      ForumSession(south),
      directory: directory,
      loadPage: page,
      loadImage: image ?? ((_, _) async => Uint8List.fromList([1, 2, 3])),
    );
    stores.add(store);
    return store;
  }

  test('Snapshots start at unfiltered page one, freeze the page count and include originals and avatars', () async {
    final pages = <Uri>[], images = <Uri>[];
    final store = create(
      page: (url) async {
        pages.add(url);
        return capture(
          south.pageNumber(url),
          total: south.pageNumber(url) == 1 ? 2 : 3,
        );
      },
      image: (url, referer) async {
        images.add(url);
        expect(south.sameThread(referer, root), isTrue);
        return Uint8List(3);
      },
    );
    final job = await store.enqueue(
      south.home.resolve('/read.php?tid-20-uid-42-page-5.html'),
      'Saved',
    );
    await store.idle;
    expect(pages.map(south.pageNumber), [1, 2]);
    expect(pages.any(south.filtered), isFalse);
    expect(images.map((u) => u.path).toSet(), {
      '/avatar.png',
      '/preview.png',
      '/full.png',
    });
    expect(images.any((u) => u.path == '/job.php'), isFalse);
    expect(job.complete, isTrue);
    expect(job.totalPages, 2);
    final count = pages.length;
    final local = await store.capture(job, south.pageUrl(root, 2));
    expect(local.cached, isTrue);
    expect(pages.length, count);
    await expectLater(
      store.capture(job, south.pageUrl(root, 3)),
      throwsA(isA<ReaderFailure>()),
    );
    expect(pages.length, count);
    expect(
      store.localAssets(job).values.every((path) => File(path).existsSync()),
      isTrue,
    );
  });
  test('A partial image failure remains incomplete and retry downloads only the missing asset', () async {
    var pageCalls = 0, fail = true;
    final images = <String, int>{};
    final store = create(
      page: (url) async {
        pageCalls++;
        return capture(1, total: 1);
      },
      image: (url, _) async {
        images.update(url.path, (n) => n + 1, ifAbsent: () => 1);
        if (url.path == '/full.png' && fail) {
          throw const HttpException('Offline');
        }
        return Uint8List(3);
      },
    );
    final job = await store.enqueue(root, 'Saved');
    await store.idle;
    expect(job.status, 'Incomplete');
    expect(job.pages.length, 1);
    expect(job.assets.length, 2);
    fail = false;
    await store.retry(job);
    await store.idle;
    expect(pageCalls, 1);
    expect(images['/preview.png'], 1);
    expect(images['/full.png'], 2);
    expect(job.complete, isTrue);
  });
  test(
    'A stopped application resumes from persisted page checkpoints',
    () async {
      final requested = Completer<void>(), response = Completer<PageCapture>();
      final first = create(
        page: (url) async {
          if (south.pageNumber(url) == 1) return capture(1);
          requested.complete();
          return response.future;
        },
      );
      await first.enqueue(root, 'Saved');
      await requested.future;
      first.dispose();
      stores.remove(first);
      response.complete(capture(2));
      await first.idle;
      final requests = <int>[];
      final restored = create(
        page: (url) async {
          requests.add(south.pageNumber(url));
          return capture(south.pageNumber(url));
        },
      );
      await restored.resume();
      await restored.idle;
      expect(requests, [2]);
      expect(restored.jobs.single.complete, isTrue);
    },
  );
  test('Removing a job during a response cannot resurrect it', () async {
    final requested = Completer<void>(), response = Completer<PageCapture>();
    final store = create(
      page: (_) {
        requested.complete();
        return response.future;
      },
    );
    final job = await store.enqueue(root, 'Saved');
    await requested.future;
    await store.remove(job);
    response.complete(capture(1));
    await store.idle;
    expect(store.jobs, isEmpty);
    expect(Directory('${directory.path}/${job.folder}').existsSync(), isFalse);
    final restored = create(
      page: (_) async => throw StateError('Must not fetch'),
    );
    await restored.resume();
    await restored.idle;
    expect(restored.jobs, isEmpty);
  });
  test('Redirects to another thread and cached online fallback never become snapshots', () async {
    var stale = false;
    final store = create(
      page: (_) async => stale
          ? PageCapture(root, capture(1).html, cached: true)
          : capture(1, tid: 21),
    );
    final job = await store.enqueue(root, 'Saved');
    await store.idle;
    expect(job.status, 'Incomplete');
    expect(job.pages, isEmpty);
    stale = true;
    await store.retry(job);
    await store.idle;
    expect(job.pages, isEmpty);
  });
  test(
    'A corrupt manifest is retained and never replaced by an empty library',
    () async {
      final file = File('${directory.path}/index.json');
      await file.writeAsString('{corrupt');
      final store = create(
        page: (_) async => throw StateError('Must not fetch'),
      );
      await store.resume();
      expect(store.readOnly, isTrue);
      await expectLater(store.enqueue(root, 'Saved'), throwsStateError);
      expect(await file.readAsString(), '{corrupt');
    },
  );
}
