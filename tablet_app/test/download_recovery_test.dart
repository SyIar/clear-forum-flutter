import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/downloads.dart';
import 'package:forum_tablet/gofile.dart';

Map<String, dynamic> file(String id) => {
  'id': id,
  'name': '$id.mp4',
  'type': 'file',
  'link': 'https://store1.gofile.io/download/web/$id/$id.mp4',
};
Map<String, dynamic> page(
  String id,
  int number,
  int total,
  List<Map<String, dynamic>> children,
) => {
  'status': 'ok',
  'contentId': id,
  'page': number,
  'pages': total,
  'name': id,
  'children': children,
};

void main() {
  test('legacy queue accepts missing provider refresh metadata', () {
    final item = DownloadItem({
      'id': 'old',
      'name': 'a.zip',
      'state': 'paused',
      'refreshes': '',
    });
    expect(item.refreshes, 0);
    expect(item.remoteID, isEmpty);
  });

  test('refresh matches provider identity rather than a reused filename', () {
    final source = Uri.parse('https://gofile.io/d/one');
    final item = DownloadItem({
      'id': 'task',
      'name': 'old.mp4',
      'state': 'expired',
      'sourcePage': '$source',
      'remoteID': 'gofile:one',
    });
    final renamed = FileRequest(
      Uri.parse('https://store2.gofile.io/download/web/one/new.mp4'),
      'new.mp4',
      sourcePage: source,
      remoteID: 'gofile:one',
    );
    expect(refreshedFile(item, [renamed]), same(renamed));
    expect(
      () => refreshedFile(item, [renamed, renamed]),
      throwsFormatException,
    );
    expect(
      () => refreshedFile(item, [
        FileRequest(
          renamed.url,
          'old.mp4',
          sourcePage: source,
          remoteID: 'gofile:other',
        ),
      ]),
      throwsFormatException,
    );
  });

  test(
    'Gofile plan visits every page and nested folder exactly once',
    () async {
      final calls = <String>[];
      final files = await collectGofile(Uri.parse('https://gofile.io/d/root'), (
        url,
        number,
      ) async {
        final id = url.pathSegments.last;
        calls.add('$id:$number');
        if (id == 'child') return page(id, 1, 1, [file('c')]);
        return page(
          id,
          number,
          2,
          number == 1
              ? [
                  file('a'),
                  {'id': 'child', 'type': 'folder'},
                ]
              : [
                  file('b'),
                  {'id': 'child', 'type': 'folder'},
                ],
        );
      });
      expect(calls, ['root:1', 'child:1', 'root:2']);
      expect(files.map((e) => e['id']), ['a', 'c', 'b']);
      expect(files[1]['sourcePage'], 'https://gofile.io/d/c');
    },
  );

  test(
    'Gofile rejects incomplete pagination and mismatched responses',
    () async {
      for (final bad in [
        page('other', 2, 2, [file('b')]),
        page('root', 1, 2, [file('b')]),
        page('root', 2, 3, [file('b')]),
        page('root', 2, 2, [file('a')]),
        {
          ...page('root', 2, 2, [file('b')]),
          'canAccess': false,
        },
      ]) {
        await expectLater(
          collectGofile(
            Uri.parse('https://gofile.io/d/root'),
            (_, number) async =>
                number == 1 ? page('root', 1, 2, [file('a')]) : bad,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'Gofile download URL must belong to the declared file and provider',
    () async {
      for (final link in [
        'https://store1.gofile.io/download/web/other/a.mp4',
        'https://store1.gofile.io.evil.invalid/download/web/a/a.mp4',
        'https://api.gofile.io/download/web/a/a.mp4',
        'http://store1.gofile.io/download/web/a/a.mp4',
        'https://user:password@store1.gofile.io/download/web/a/a.mp4',
      ]) {
        await expectLater(
          collectGofile(
            Uri.parse('https://gofile.io/d/root'),
            (_, _) async => page('root', 1, 1, [
              {...file('a'), 'link': link},
            ]),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'Gofile embedded direct links resolve through their content identity',
    () {
      expect(
        gofilePage(
          Uri.parse(
            'https://store5.gofile.io/download/web/abc/clip.mp4?token=opaque',
          ),
        ),
        Uri.parse('https://gofile.io/d/abc'),
      );
      expect(
        () => gofilePage(Uri.parse('https://api.gofile.io/contents/abc')),
        throwsFormatException,
      );
      expect(
        () => gofilePage(Uri.parse('https://gofile.io:8443/d/abc')),
        throwsFormatException,
      );
    },
  );
}
