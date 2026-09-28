import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'parser.dart';
import 'site.dart';

abstract class PageSource {
  Future<ForumPage> load(Uri url);
  Future<ForumPage?> openBrowser(Uri url);
  Future<void> clearSession();
}

class DeviceSession implements PageSource {
  DeviceSession({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.sylar.clearforum/session');
  final MethodChannel _channel;
  final _parser = ForumParser();
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  @override
  Future<ForumPage> load(Uri url) async {
    if (!ForumSite.readable(url)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    var current = url.removeFragment();
    for (var hop = 0; hop < 6; hop++) {
      final Map<dynamic, dynamic>? reply;
      try {
        reply = await _channel.invokeMapMethod('loadPage', current.toString());
      } on PlatformException {
        throw const ReaderFailure(FailureKind.network);
      }
      if (reply == null) throw const ReaderFailure(FailureKind.network);
      final status = reply['status'] as int? ?? 0;
      if (status >= 300 && status < 400) {
        final next = ForumSite.resolve(reply['location'] as String?, current);
        if (next != null &&
            ForumSite.sameOrigin(next) &&
            next.path.startsWith('/login')) {
          throw const ReaderFailure(FailureKind.login);
        }
        if (next == null || !ForumSite.readable(next)) {
          throw const ReaderFailure(FailureKind.unsupported);
        }
        current = next.removeFragment();
        continue;
      }
      return _parser.parse(
        reply['html'] as String? ?? '',
        current.replace(fragment: url.fragment),
        status: status,
      );
    }
    throw const ReaderFailure(FailureKind.network);
  }

  @override
  Future<ForumPage?> openBrowser(Uri url) async {
    if (!ForumSite.sameOrigin(url)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>(
        'openBrowser',
        url.toString(),
      );
      if (data == null) return null;
      final page = Uri.tryParse(data['url'] as String? ?? '');
      if (page == null || !ForumSite.readable(page)) {
        throw const ReaderFailure(FailureKind.unsupported);
      }
      return _parser.parse(data['html'] as String? ?? '', page);
    } on PlatformException {
      throw const ReaderFailure(FailureKind.network);
    }
  }

  @override
  Future<void> clearSession() => _channel.invokeMethod('clearSession');
  Future<void> openExternal(Uri url) async {
    if (url.scheme != 'https' || url.userInfo.isNotEmpty) return;
    await _channel.invokeMethod('openExternal', url.toString());
  }
}

class DemoSource implements PageSource {
  final _parser = ForumParser();
  @override
  Future<ForumPage> load(Uri url) async {
    final name = url.path.startsWith('/threads/')
        ? 'thread'
        : url.path.startsWith('/forums/')
        ? 'forum'
        : 'index';
    return _parser.parse(
      await rootBundle.loadString('assets/demo/$name.html'),
      url,
    );
  }

  @override
  Future<ForumPage?> openBrowser(Uri url) async => null;
  @override
  Future<void> clearSession() async {}
}
