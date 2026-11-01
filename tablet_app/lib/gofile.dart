import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Uri gofilePage(Uri url) {
  final parts = url.pathSegments;
  final id = url.host == 'gofile.io' && parts.length == 2 && parts.first == 'd'
      ? parts[1]
      : url.host.endsWith('.gofile.io') &&
            url.host != 'api.gofile.io' &&
            parts.length >= 4 &&
            parts[0] == 'download' &&
            parts[1] == 'web'
      ? parts[2]
      : '';
  if (url.scheme != 'https' ||
      url.userInfo.isNotEmpty ||
      url.port != 443 ||
      !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
    throw const FormatException('Invalid Gofile page');
  }
  return Uri.https('gofile.io', '/d/$id');
}

/// Observes the public content response made by Gofile's own page. No guessed
/// website token and no forum cookies are sent to the provider API.
Future<Map<String, dynamic>> captureGofile(Uri url, {int page = 1}) async {
  if (url.scheme != 'https' ||
      url.host != 'gofile.io' ||
      !RegExp(r'^/d/[A-Za-z0-9_-]{1,128}$').hasMatch(url.path) ||
      page < 1) {
    throw const FormatException('Invalid Gofile page');
  }
  final result = Completer<Map<String, dynamic>>();
  InAppWebViewController? controller;
  bool checking = false;
  Future<void> inspect() async {
    if (checking || controller == null || result.isCompleted) return;
    checking = true;
    try {
      final value = await controller!.evaluateJavascript(
        source: 'window.__forumFiles || null',
      );
      if (value is Map &&
          value['contentId'] == url.pathSegments.last &&
          value['page'] == page &&
          !result.isCompleted) {
        result.complete(Map<String, dynamic>.from(value));
      }
    } catch (_) {
      // A navigation can replace the JavaScript context during inspection.
    } finally {
      checking = false;
    }
  }

  final browser = HeadlessInAppWebView(
    initialSize: const Size(1000, 800),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: true,
    ),
    initialUrlRequest: URLRequest(
      url: WebUri(
        '${url.replace(queryParameters: page > 1 ? {'page': '$page'} : {})}',
      ),
    ),
    initialUserScripts: UnmodifiableListView([
      UserScript(
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
        source: r'''
(() => {
  if (location.origin !== 'https://gofile.io') return;
  const original = window.fetch;
  window.fetch = async function(...args) {
    const response = await original.apply(this,args);
    try {
      const input = args[0];
      const url = new URL(input instanceof Request ? input.url : String(input), location.href);
      const method = String(args[1]?.method || (input instanceof Request ? input.method : 'GET')).toUpperCase();
      if (method === 'GET' && url.origin === 'https://api.gofile.io' && /^\/contents\/[A-Za-z0-9_-]+$/.test(url.pathname)) {
        (async () => {
          const copy = response.clone();
          if (Number(copy.headers.get('content-length')) > 4194304) return;
          const reader = copy.body.getReader();
          const decoder = new TextDecoder();
          let size = 0, body = '';
          try {
            while (true) {
              const chunk = await reader.read();
              if (chunk.done) break;
              size += chunk.value.byteLength;
              if (size > 4194304) { await reader.cancel(); return; }
              body += decoder.decode(chunk.value, {stream: true});
            }
          } finally { reader.releaseLock(); }
          const envelope = JSON.parse(body + decoder.decode());
          const source = envelope.data || {};
          const pick = item => ({id:item.id,name:item.name,type:item.type,link:item.link,
            canAccess:item.canAccess,isFrozen:item.isFrozen,overloaded:item.overloaded});
          const children = source.type === 'file' ? [source] : Object.values(source.children || {});
          window.__forumFiles = {contentId:url.pathname.split('/')[2],page:Number(url.searchParams.get('page') || 1),
            status:children.length > 1000 ? 'error' : envelope.status,canAccess:source.canAccess,
            name:source.name,pages:envelope.metadata?.totalPages || 1,
            children:children.length > 1000 ? [] : children.map(pick)};
        })().catch(() => {});
      }
    } catch (_) {}
    return response;
  };
})();
''',
      ),
    ]),
    onWebViewCreated: (c) => controller = c,
    onLoadStop: (c, u) => inspect(),
  );
  Timer? poll;
  try {
    await browser.run();
    poll = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(inspect()),
    );
    return await result.future.timeout(const Duration(seconds: 35));
  } finally {
    poll?.cancel();
    await browser.dispose();
  }
}

typedef GofilePageLoader = Future<Map<String, dynamic>> Function(
  Uri url,
  int page,
);

/// Enumerates every declared page before publishing a complete download plan.
Future<List<Map<String, dynamic>>> collectGofile(
  Uri url,
  GofilePageLoader load,
) async {
  final result = <Map<String, dynamic>>[];
  final folders = <String>{}, files = <String>{};
  Future<void> folder(Uri target, int depth) async {
    if (depth > 8) throw const FormatException('Gofile folder depth exceeded');
    final id = target.pathSegments.last;
    if (!folders.add(id)) return;
    if (folders.length > 1000) throw const FormatException('Too many folders');
    var pages = 1;
    final seen = <String>{};
    for (var page = 1; page <= pages; page++) {
      final data = await load(target, page);
      final count = data['pages'];
      if (data['status'] != 'ok' ||
          data['canAccess'] == false ||
          data['contentId'] != id ||
          data['page'] != page ||
          count is! int ||
          count < page ||
          count > 200 ||
          data['children'] is! List) {
        throw const FormatException('Gofile page unavailable');
      }
      if (page == 1) pages = count;
      if (count != pages) {
        throw const FormatException('Gofile folder changed; retry');
      }
      final children = data['children'] as List;
      if (children.length > 1000) {
        throw const FormatException('Gofile page too large');
      }
      var additions = 0;
      for (final raw in children) {
        if (raw is! Map ||
            raw['id'] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(raw['id'] as String) ||
            !const ['file', 'folder'].contains(raw['type'])) {
          throw const FormatException('Invalid Gofile entry');
        }
        final child = Map<String, dynamic>.from(raw);
        final childID = child['id'] as String;
        if (!seen.add(childID)) continue;
        additions++;
        final childPage = Uri.https('gofile.io', '/d/$childID');
        if (child['type'] == 'folder') {
          await folder(childPage, depth + 1);
        } else {
          final file = Uri.tryParse('${child['link'] ?? ''}');
          if (child['canAccess'] == false ||
              child['isFrozen'] == true ||
              child['overloaded'] == true ||
              file == null ||
              file.scheme != 'https' ||
              file.userInfo.isNotEmpty ||
              file.port != 443 ||
              !file.host.endsWith('.gofile.io') ||
              file.host == 'api.gofile.io' ||
              file.pathSegments.length < 4 ||
              file.pathSegments[0] != 'download' ||
              file.pathSegments[1] != 'web' ||
              file.pathSegments[2] != childID) {
            throw const FormatException('Gofile file unavailable');
          }
          if (files.add(childID)) {
            result.add({
              ...child,
              'folder': data['name'] ?? '',
              'sourcePage': '$childPage',
            });
          }
          if (result.length > 10000) {
            throw const FormatException('Too many files');
          }
        }
      }
      if (page > 1 && additions == 0) {
        throw const FormatException('Repeated Gofile page');
      }
    }
  }

  await folder(gofilePage(url), 0);
  if (result.isEmpty) throw const FormatException('Empty file list');
  return result;
}
