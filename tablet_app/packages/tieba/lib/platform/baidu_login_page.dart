import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../widgets/glass.dart';
import 'baidu_web_session.dart';

class BaiduCookies {
  const BaiduCookies({
    required this.bduss,
    required this.stoken,
    required this.baiduid,
    required this.cookie,
  });
  final String bduss, stoken, baiduid, cookie;
}

/// This WebView is used only for Baidu authentication, never forum rendering.
class BaiduLoginPage extends StatefulWidget {
  const BaiduLoginPage({
    super.key,
    required this.onCookies,
    this.title = 'Baidu account',
    this.cancelLabel = 'Cancel',
    this.finishLabel = 'Finish sign-in',
    this.privacyLabel =
        'Sign in on the official Baidu page. Passwords stay on that page.',
    this.errorLabel = 'Sign-in could not be completed. Please try again.',
    this.notReadyLabel = 'Complete sign-in on the Baidu page first.',
    this.unsupportedLabel = 'Use the installed iOS app to sign in.',
    this.retryLabel = 'Retry',
  });

  final Future<void> Function(BaiduCookies cookies) onCookies;
  final String title,
      cancelLabel,
      finishLabel,
      privacyLabel,
      errorLabel,
      notReadyLabel,
      unsupportedLabel,
      retryLabel;

  @override
  State<BaiduLoginPage> createState() => _BaiduLoginPageState();
}

class _BaiduLoginPageState extends State<BaiduLoginPage> {
  static const _loginUrl =
      'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';
  BaiduWebSessionLease? _lease;
  InAppWebViewController? _controller;
  bool _ready = false;
  bool _busy = false;
  bool _failed = false;
  bool _preparing = false;
  double _progress = 0;
  String _host = 'wappass.baidu.com';

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (_supported) unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (_preparing) return;
    _preparing = true;
    try {
      final lease = await BaiduWebSessionCoordinator.instance.acquire();
      if (!mounted) {
        await lease.close();
        return;
      }
      _lease = lease;
      if (mounted) {
        setState(() {
          _ready = true;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _preparing = false;
    }
  }

  bool _isBaidu(WebUri? uri) {
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'baidu.com' || host.endsWith('.baidu.com');
  }

  Future<BaiduCookies?> _readCookies() async {
    final values = <String, String>{};
    for (final origin in [
      'https://baidu.com/',
      'https://wappass.baidu.com/',
      'https://tieba.baidu.com/',
    ]) {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(origin),
      );
      for (final cookie in cookies) {
        final name = cookie.name;
        final value = cookie.value;
        if (RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name) &&
            !RegExp(r'[;\r\n]').hasMatch(value)) {
          values[name] = value;
        }
      }
    }
    final normalized = values.map(
      (name, value) => MapEntry(name.toUpperCase(), value),
    );
    final bduss = normalized['BDUSS'] ?? '';
    final stoken = normalized['STOKEN'] ?? '';
    if (bduss.isEmpty || stoken.isEmpty) return null;
    return BaiduCookies(
      bduss: bduss,
      stoken: stoken,
      baiduid: normalized['BAIDUID'] ?? '',
      cookie: values.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; '),
    );
  }

  Future<void> _finish({bool automatic = false}) async {
    if (_busy || !_ready || _lease?.active != true) return;
    setState(() => _busy = true);
    try {
      final cookies = await _readCookies();
      if (!mounted) return;
      if (cookies == null) {
        if (!automatic) _show(widget.notReadyLabel);
        return;
      }
      await widget.onCookies(cookies);
      if (!mounted) return;
      await _controller?.stopLoading();
      await _lease?.close();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) _show(widget.errorLabel);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  void dispose() {
    if (_supported) {
      final controller = _controller;
      unawaited(() async {
        try {
          await controller?.stopLoading();
        } catch (_) {
          // The platform view may already have been removed.
        }
        try {
          await _lease?.close();
        } catch (_) {
          // A subsequent page must clear the store before loading.
        }
      }());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: GlassAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(_host, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        leading: IconButton(
          tooltip: widget.cancelLabel,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            onPressed: !_ready || _busy ? null : () => _finish(),
            child: Text(widget.finishLabel),
          ),
        ],
      ),
      body: !_supported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(widget.unsupportedLabel),
              ),
            )
          : !_ready
          ? Center(
              child: _failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.errorLabel),
                        FilledButton(
                          onPressed: _prepare,
                          child: Text(widget.retryLabel),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            )
          : Column(
              children: [
                if (_busy || _progress < 1)
                  LinearProgressIndicator(value: _busy ? null : _progress),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.privacyLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      javaScriptCanOpenWindowsAutomatically: false,
                      supportMultipleWindows: true,
                      isInspectable: false,
                      allowFileAccessFromFileURLs: false,
                      allowUniversalAccessFromFileURLs: false,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    ),
                    onWebViewCreated: (controller) => _controller = controller,
                    onProgressChanged: (_, progress) {
                      if (mounted) setState(() => _progress = progress / 100);
                    },
                    onLoadStart: (_, url) {
                      if (mounted && url != null) {
                        setState(() => _host = url.host);
                      }
                    },
                    onLoadStop: (_, url) async {
                      if (_isBaidu(url) &&
                          url!.host == 'tieba.baidu.com' &&
                          url.path.startsWith('/index/tbwise/')) {
                        await _finish(automatic: true);
                      }
                    },
                    onCreateWindow: (_, _) async => false,
                    shouldOverrideUrlLoading: (_, action) async =>
                        _isBaidu(action.request.url)
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL,
                    onReceivedError: (_, request, _) {
                      if (request.isForMainFrame == true && mounted) {
                        _show(widget.errorLabel);
                      }
                    },
                  ),
                ),
              ],
            ),
    ),
  );
}
