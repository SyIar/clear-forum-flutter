import 'dart:async';

import 'package:clean_forum/core/media_posters.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final page = Uri.https('turbo.cr', '/embed/sample');
  BodyBlock media(String id) => BodyBlock(
    BlockKind.embeddedMedia,
    url: Uri.https('turbo.cr', '/embed/$id'),
  );
  test(
    'real poster metadata wins, including relative URLs and HTML entities',
    () {
      expect(
        MediaPosters.parse('''
      <meta property="og:image" content="/fallback.png">
      <video id="main-video" data-poster="https://images.example/tenant/thumbs/sample.jpg?a=1&amp;b=2"></video>
      <script>untrusted()</script>''', page),
        Uri.parse('https://images.example/tenant/thumbs/sample.jpg?a=1&b=2'),
      );
      expect(
        MediaPosters.parse('<video poster="../thumb.jpg"></video>', page),
        Uri.https('turbo.cr', '/thumb.jpg'),
      );
      expect(
        MediaPosters.parse(
          '<meta property="og:image" content="https://images.example/poster.webp">',
          page,
        ),
        Uri.https('images.example', '/poster.webp'),
      );
      expect(
        MediaPosters.parse(
          '<video src="https://video.example/file.mp4"></video>',
          page,
        ),
        null,
      );
      expect(
        MediaPosters.parse('<video poster="javascript:bad()"></video>', page),
        null,
      );
      expect(
        MediaPosters.parse(
          '<video poster="https://images.example:9443/a.png"></video>',
          page,
        ),
        null,
      );
      expect(
        MediaPosters.parse(
          '<div class="ad-container"><video poster="https://images.example/ad.jpg"></video></div>',
          page,
        ),
        null,
      );
    },
  );
  test(
    'metadata requests are deduplicated and limited to two concurrent reads',
    () async {
      final reads = <Completer<String?>>[];
      final posters = MediaPosters((_) {
        final read = Completer<String?>();
        reads.add(read);
        return read.future;
      });
      final first = posters.resolve(media('one'));
      expect(identical(first, posters.resolve(media('one'))), true);
      final second = posters.resolve(media('two'));
      final third = posters.resolve(media('three'));
      expect(reads.length, 2);
      reads[0].complete('<video data-poster="/real.jpg"></video>');
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(reads.length, 3);
      reads[1].completeError(StateError('unavailable'));
      reads[2].complete(null);
      expect(await second, null);
      expect(await third, null);
      expect(await posters.resolve(media('two')), null);
      expect(
        reads.length,
        3,
        reason: 'Scrolling must not retry a failed request',
      );
    },
  );
  test('leaving a page drops queued metadata work', () async {
    final reads = <Completer<String?>>[];
    final posters = MediaPosters((_) {
      final read = Completer<String?>();
      reads.add(read);
      return read.future;
    });
    final pending = [
      for (var i = 0; i < 6; i++) posters.resolve(media('item$i')),
    ];
    posters.dispose();
    for (final read in reads) {
      read.complete(null);
    }
    await Future.wait(pending);
    expect(reads.length, 2);
  });
  test('only supported metadata routes cross the native bridge', () async {
    const channel = MethodChannel('poster-test');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return '<video data-poster="/cover.jpg"></video>';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final session = DeviceSession(channel: channel);
    await session.mediaPosterHTML(page);
    await session.mediaPosterHTML(Uri.https('cyberdrop.cr', '/e/sample'));
    for (final address in [
      'https://turbo.cr.evil.example/embed/sample',
      'https://turbo.cr/logout',
      'https://turbo.cr/embed/sample?token=x',
      'http://turbo.cr/embed/sample',
      'https://name:secret@turbo.cr/embed/sample',
      'https://cyberdrop.cr/e/',
    ]) {
      expect(await session.mediaPosterHTML(Uri.parse(address)), null);
    }
    expect(calls.length, 2);
    expect(calls.first.method, 'mediaPosterHTML');
    expect(calls.first.arguments, page.toString());
  });
}
