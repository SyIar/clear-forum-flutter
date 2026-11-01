import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'account.dart';
import 'downloads.dart';
import 'parsers.dart';
import 'site.dart';
import 'strings.dart';

class PageCapture {
  const PageCapture(this.url, this.html, {this.cached = false});
  final Uri url;
  final String html;
  final bool cached;
}

class ForumSession {
  ForumSession(this.site);
  final ForumSite site;
  final account = ValueNotifier(const ForumAccount(AccountStatus.unknown));
  int _accountRevision = 0;
  void authenticationBoundary() {
    _accountRevision++;
  }

  ForumAccount observeAccount(Uri url, String source, {int? revision}) {
    final observed = ForumAccount.inspect(site, url, source);
    if ((revision == null || revision == _accountRevision) &&
        observed.status != AccountStatus.unknown &&
        (observed.status != account.value.status ||
            observed.name != account.value.name)) {
      account.value = observed;
    }
    return observed;
  }

  Future<void> _tail = Future.value();
  static const desktopAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  InAppWebViewSettings get settings => InAppWebViewSettings(
    userAgent: desktopAgent,
    javaScriptEnabled: true,
    cacheEnabled: true,
    sharedCookiesEnabled: true,
    thirdPartyCookiesEnabled: false,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    supportMultipleWindows: false,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    loadWithOverviewMode: true,
    useWideViewPort: true,
  );
  Future<PageCapture> fetch(Uri target, {bool offline = false}) async {
    final url = site.canonical(target);
    if (!site.readable(url)) throw const ReaderFailure(FailureKind.unsupported);
    if (offline) {
      final cache = await cached(url);
      if (cache != null) return cache;
      throw const ReaderFailure(FailureKind.network);
    }
    final prior = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await prior;
    try {
      final capture = await _capture(url);
      // Persist only a parsed forum document, never a verification or login form.
      PageParser(site).parse(capture.html, capture.url);
      await save(capture);
      return capture;
    } catch (_) {
      final cache = await cached(url);
      if (cache != null) return cache;
      rethrow;
    } finally {
      done.complete();
    }
  }

  Future<PageCapture> _capture(Uri url) async {
    if (kIsWeb) throw const ReaderFailure(FailureKind.network);
    final result = Completer<PageCapture>();
    final accountRevision = _accountRevision;
    InAppWebViewController? controller;
    bool reading = false;
    var lastFailure = const ReaderFailure(FailureKind.network);
    Future<void> inspect() async {
      if (reading || controller == null || result.isCompleted) return;
      reading = true;
      try {
        final current = await controller!.getUrl();
        if (current == null || !site.sameOrigin(Uri.parse('$current'))) return;
        final content = await controller!.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        if (content is! String ||
            content.isEmpty ||
            content.length > 8 * 1024 * 1024) {
          return;
        }
        final document = PageCapture(
          site.canonical(Uri.parse('$current')),
          content,
        );
        observeAccount(document.url, content, revision: accountRevision);
        if (site.isLogin(document.url)) {
          result.completeError(const ReaderFailure(FailureKind.login));
          return;
        }
        try {
          PageParser(site).parse(content, document.url);
        } on ReaderFailure catch (failure) {
          lastFailure = failure;
          if (failure.kind == FailureKind.login && !result.isCompleted) {
            result.completeError(failure);
          }
          return;
        }
        if (!result.isCompleted) result.complete(document);
      } catch (_) {
        /* Navigation can replace the JavaScript context. */
      } finally {
        reading = false;
      }
    }

    final browser = HeadlessInAppWebView(
      initialSize: const Size(1200, 900),
      initialSettings: settings,
      initialUrlRequest: URLRequest(url: WebUri('$url')),
      onWebViewCreated: (value) {
        controller = value;
      },
      onLoadStop: (c, u) async {
        await inspect();
      },
      onReceivedError: (c, request, error) {
        if (request.isForMainFrame == true && !result.isCompleted) {
          result.completeError(const ReaderFailure(FailureKind.network));
        }
      },
      shouldOverrideUrlLoading: (c, action) async {
        final u = Uri.tryParse('${action.request.url}');
        return u != null && u.scheme == 'https' && u.userInfo.isEmpty
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
    );
    Timer? poll;
    try {
      await browser.run();
      poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(inspect()),
      );
      return await result.future.timeout(
        const Duration(seconds: 40),
        onTimeout: () => throw lastFailure,
      );
    } finally {
      poll?.cancel();
      await browser.dispose();
    }
  }

  Future<File> _file(Uri url) async {
    final directory = await getApplicationSupportDirectory();
    final folder = Directory('${directory.path}/pages');
    await folder.create(recursive: true);
    return File('${folder.path}/${sha256.convert(utf8.encode('$url'))}.json');
  }

  Future<void> save(PageCapture capture) async {
    if (kIsWeb) return;
    final file = await _file(capture.url);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'url': '${capture.url}', 'html': capture.html}),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<PageCapture?> cached(Uri url) async {
    if (kIsWeb) return null;
    try {
      final file = await _file(url);
      if (!await file.exists()) return null;
      final map = jsonDecode(await file.readAsString()) as Map;
      return PageCapture(
        Uri.parse(map['url'] as String),
        map['html'] as String,
        cached: true,
      );
    } catch (_) {
      return null;
    }
  }
}

class SiteBrowser extends StatefulWidget {
  const SiteBrowser({super.key, required this.session, required this.url});
  final ForumSession session;
  final Uri url;
  @override
  State<SiteBrowser> createState() => _SiteBrowserState();
}

class _SiteBrowserState extends State<SiteBrowser> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String? _error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Browser')),
      actions: [
        IconButton(
          tooltip: tr('Refresh'),
          onPressed: () => _controller?.reload(),
          icon: const Icon(Icons.refresh),
        ),
        TextButton(
          onPressed: () async {
            final current = await _controller?.getUrl();
            final content = await _controller?.evaluateJavascript(
              source: 'document.documentElement.outerHTML',
            );
            if (!mounted || current == null || content is! String) return;
            final url = widget.session.site.canonical(Uri.parse('$current'));
            if (!widget.session.site.readable(url)) {
              setState(() => _error = tr('Page unavailable'));
              return;
            }
            try {
              PageParser(widget.session.site).parse(content, url);
              final capture = PageCapture(url, content);
              await widget.session.save(capture);
              if (context.mounted) Navigator.pop(context, capture);
            } catch (_) {
              if (mounted) setState(() => _error = tr('Page unavailable'));
            }
          },
          child: Text(tr('Read page')),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_progress < 1) LinearProgressIndicator(value: _progress),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: kIsWeb
              ? Center(child: Text(tr('File browser unavailable')))
              : InAppWebView(
                  initialSettings: widget.session.settings,
                  initialUrlRequest: URLRequest(url: WebUri('${widget.url}')),
                  onWebViewCreated: (c) {
                    _controller = c;
                  },
                  onProgressChanged: (c, progress) {
                    if (mounted) setState(() => _progress = progress / 100);
                  },
                  onLoadStop: (c, u) async {
                    try {
                      final source = await c.evaluateJavascript(
                        source: 'document.documentElement.outerHTML',
                      );
                      if (u != null && source is String) {
                        widget.session.observeAccount(Uri.parse('$u'), source);
                      }
                    } catch (_) {
                      // Navigation may replace the current JavaScript context.
                    }
                  },
                  onDownloadStartRequest: (controller, request) async {
                    final url = Uri.parse('${request.url}');
                    final cookies = await CookieManager.instance().getCookies(
                      url: request.url,
                    );
                    try {
                      await DownloadManager.instance.enqueue(
                        FileRequest(
                          url,
                          request.suggestedFilename ?? 'download',
                          referer: '${await controller.getUrl() ?? widget.url}',
                          cookie: cookies
                              .map((c) => '${c.name}=${c.value}')
                              .join('; '),
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(tr('Queued'))));
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(() => _error = tr('Download failed'));
                      }
                    }
                  },
                  shouldOverrideUrlLoading: (c, action) async {
                    final url = action.request.url;
                    return url != null &&
                            const ['http', 'https'].contains(url.scheme)
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL;
                  },
                ),
        ),
      ],
    ),
  );
}
