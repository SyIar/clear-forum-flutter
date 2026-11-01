import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../widgets/glass.dart';

import '../core/models.dart';
import 'baidu_web_session.dart';

class BaiduActionPolicy {
  static const actionHosts = {'tieba.baidu.com', 'tiebac.baidu.com'};
  static const navigationHosts = {
    ...actionHosts,
    'wappass.baidu.com',
    'passport.baidu.com',
  };

  static bool accepts(Uri uri, {bool initial = false}) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      (initial ? actionHosts : navigationHosts).contains(
        uri.host.toLowerCase(),
      );

  static Map<String, String> cookies(TiebaSession session) {
    final values = <String, String>{
      'BDUSS': session.bduss,
      'STOKEN': session.stoken,
    };
    for (final part in session.rawCookie.split(';')) {
      final separator = part.indexOf('=');
      if (separator > 0 &&
          part.substring(0, separator).trim().toUpperCase() == 'BAIDUID') {
        values['BAIDUID'] = part.substring(separator + 1).trim();
      }
    }
    if (session.bduss.isEmpty ||
        session.stoken.isEmpty ||
        values.values.any(
          (value) => RegExp(r'[;\x00-\x20\x7f]').hasMatch(value),
        )) {
      throw const FormatException('Invalid Baidu web credentials');
    }
    return Map.unmodifiable(values..removeWhere((_, value) => value.isEmpty));
  }
}

/// Displays an official account action such as the report form.
class BaiduActionPage extends StatefulWidget {
  const BaiduActionPage({
    super.key,
    required this.url,
    required this.session,
    required this.title,
    required this.errorLabel,
    required this.retryLabel,
    required this.unsupportedLabel,
  });
  final Uri url;
  final TiebaSession session;
  final String title, errorLabel, retryLabel, unsupportedLabel;

  @override
  State<BaiduActionPage> createState() => _BaiduActionPageState();
}

class _BaiduActionPageState extends State<BaiduActionPage> {
  BaiduWebSessionLease? _lease;
  InAppWebViewController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _preparing = false;
  double _progress = 0;
  late String _host;

  bool get _supported =>
      !kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _host = widget.url.host;
    if (_supported) unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (_preparing) return;
    _preparing = true;
    try {
      if (!BaiduActionPolicy.accepts(widget.url, initial: true)) {
        throw const FormatException('Unsupported Baidu action origin');
      }
      final values = BaiduActionPolicy.cookies(widget.session);
      final lease = await BaiduWebSessionCoordinator.instance.acquire(
        configure: () async {
          for (final entry in values.entries) {
            final written = await CookieManager.instance().setCookie(
              url: WebUri('https://${widget.url.host}/'),
              name: entry.key,
              value: entry.value,
              domain: widget.url.host,
              path: '/',
              isSecure: true,
              isHttpOnly: true,
            );
            if (!written) throw StateError('Baidu cookie setup failed');
          }
        },
      );
      if (!mounted) {
        await lease.close();
        return;
      }
      _lease = lease;
      setState(() {
        _ready = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _preparing = false;
    }
  }

  Future<void> _close() async {
    try {
      await _controller?.stopLoading();
    } catch (_) {
      // The platform view may already have been removed.
    }
    try {
      await _lease?.close();
    } catch (_) {
      // A subsequent page must clear the store before loading.
    }
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title),
          Text(_host, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
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
              if (_progress < 1) LinearProgressIndicator(value: _progress),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri.uri(widget.url)),
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
                  onCreateWindow: (_, _) async => false,
                  shouldOverrideUrlLoading: (_, action) async {
                    final uri = action.request.url?.uriValue;
                    return uri != null && BaiduActionPolicy.accepts(uri)
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL;
                  },
                  onReceivedError: (_, request, _) {
                    if (mounted && request.isForMainFrame == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(widget.errorLabel)),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
  );
}
