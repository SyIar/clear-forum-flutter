import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'session.dart';
import 'strings.dart';

Future<bool> forumSignIn(BuildContext context, ForumSession session) async =>
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ForumLoginPage(session: session)),
    ) ??
    false;

class ForumLoginPage extends StatefulWidget {
  const ForumLoginPage({super.key, required this.session});
  final ForumSession session;
  @override
  State<ForumLoginPage> createState() => _ForumLoginPageState();
}

class _ForumLoginPageState extends State<ForumLoginPage> {
  InAppWebViewController? _controller;
  Timer? _poll;
  bool _checking = false, _finished = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.authenticationBoundary();
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_inspect()),
    );
  }

  @override
  void dispose() {
    _finished = true;
    _poll?.cancel();
    widget.session.authenticationBoundary();
    super.dispose();
  }

  Future<void> _inspect({bool manual = false}) async {
    final controller = _controller;
    if (_checking || _finished || controller == null) return;
    _checking = true;
    try {
      final url = await controller.getUrl();
      final source = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (!mounted || _finished || url == null || source is! String) return;
      final account = widget.session.observeAccount(Uri.parse('$url'), source);
      if (account.signedIn) {
        _finished = true;
        widget.session.authenticationBoundary();
        Navigator.pop(context, true);
      } else if (manual) {
        setState(() => _error = tr('Sign in not complete'));
      }
    } catch (_) {
      // A redirect can replace the JavaScript context during authentication.
      if (manual && mounted) setState(() => _error = tr('Page unavailable'));
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${tr(widget.session.site.name)} - ${tr('Login')}'),
      actions: [
        IconButton(
          tooltip: tr('Refresh'),
          onPressed: () => _controller?.reload(),
          icon: const Icon(Icons.refresh),
        ),
        TextButton(
          onPressed: () => _inspect(manual: true),
          child: Text(tr('Done')),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(tr('Website sign in hint')),
          ),
          if (_progress < 1) LinearProgressIndicator(value: _progress),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: InAppWebView(
              initialSettings: widget.session.settings,
              initialUrlRequest: URLRequest(
                url: WebUri('${widget.session.site.login}'),
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onProgressChanged: (controller, progress) {
                if (mounted) setState(() => _progress = progress / 100);
              },
              onLoadStop: (_, _) => _inspect(),
              onUpdateVisitedHistory: (_, _, _) => _inspect(),
              onReceivedError: (_, request, _) {
                if (request.isForMainFrame == true && mounted) {
                  setState(() => _error = tr('Page unavailable'));
                }
              },
              shouldOverrideUrlLoading: (_, action) async {
                final url = action.request.url;
                return url != null &&
                        url.scheme == 'https' &&
                        url.userInfo.isEmpty
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              },
            ),
          ),
        ],
      ),
    ),
  );
}
