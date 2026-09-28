import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/session.dart';
import 'package:clean_forum/core/site.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test-session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  test(
    'plain saved URLs do not acquire an empty fragment when reopened',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'status': 200,
          'html': File('assets/demo/thread.html').readAsStringSync(),
        },
      );
      final target = ForumSite.base.resolve('/threads/sample.1/');
      final page = await DeviceSession(channel: channel).load(target);
      expect(page.url, target);
      expect(page.url.hasFragment, false);
    },
  );
  test(
    'post anchors survive reading but are never sent in HTTP requests',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          'status': 200,
          'html': File('assets/demo/thread.html').readAsStringSync(),
        };
      });
      final target = ForumSite.base.resolve(
        '/threads/sample.1/page-5#post-123',
      );
      final page = await DeviceSession(channel: channel).load(target);
      expect(page.url, target);
      expect(calls.single.arguments, target.removeFragment().toString());
    },
  );
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    calls.clear();
  });
  test('redirect to another origin never becomes a second request', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'status': 302,
        'location': 'https://external.example/',
        'html': '',
      };
    });
    await expectLater(
      DeviceSession(channel: channel).load(ForumSite.base),
      throwsA(isA<ReaderFailure>()),
    );
    expect(calls.length, 1);
    expect(calls.single.arguments, 'https://simpcity.cr/');
  });
  test('same-origin pagination redirects are followed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return calls.length == 1
          ? {'status': 302, 'location': '/forums/design-notes.10/', 'html': ''}
          : {
              'status': 200,
              'html': File('assets/demo/forum.html').readAsStringSync(),
            };
    });
    final page = await DeviceSession(channel: channel).load(ForumSite.base);
    expect(page.entries.length, 3);
    expect(calls.length, 2);
  });
  test('login redirects result in a login prompt', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'status': 303, 'location': '/login/'},
    );
    await expectLater(
      DeviceSession(channel: channel).load(ForumSite.base),
      throwsA(
        isA<ReaderFailure>().having((e) => e.kind, 'kind', FailureKind.login),
      ),
    );
  });
  test('redirect loops are bounded', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'status': 302, 'location': '/'};
    });
    await expectLater(
      DeviceSession(channel: channel).load(ForumSite.base),
      throwsA(isA<ReaderFailure>()),
    );
    expect(calls.length, 6);
  });
  test('write routes never reach the native bridge', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await expectLater(
      DeviceSession(channel: channel).load(ForumSite.base.resolve('/logout/')),
      throwsA(isA<ReaderFailure>()),
    );
    expect(calls, isEmpty);
  });
}
