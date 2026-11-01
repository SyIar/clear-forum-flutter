import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Observes the public content response made by Gofile's own page. No guessed
/// website token and no forum cookies are sent to the provider API.
Future<Map<String, dynamic>> captureGofile(Uri url) async {
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
      if (value is Map && !result.isCompleted) {
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
    initialUrlRequest: URLRequest(url: WebUri('$url')),
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
      const url = new URL(typeof input === 'string' ? input : input.url, location.href);
      if (url.origin === 'https://api.gofile.io' && /^\/contents\/[A-Za-z0-9_-]+$/.test(url.pathname)) {
        response.clone().json().then(envelope => {
          const source = envelope.data || {};
          const pick = item => ({id:item.id,name:item.name,type:item.type,link:item.link});
          window.__forumFiles = {status:envelope.status,name:source.name,pages:envelope.metadata?.totalPages || 1,
            children:(source.type === 'file' ? [source] : Object.values(source.children || {})).slice(0,1000).map(pick)};
        }).catch(() => {});
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
