import 'package:html/parser.dart' as html;

/// Local-only diagnostics. Authentication inputs and executable page data are
/// removed before the source can be copied out of the application.
class PageDiagnostic {
  PageDiagnostic(this.url, this.state, String source)
    : captured = DateTime.now(),
      source = sanitize(source);
  final Uri url;
  final DateTime captured;
  final String state, source;
  String get text =>
      'Forum Tablet reader diagnostics\n$captured\n$url\n$state\n\n'
      '--- SANITIZED PAGE HTML ---\n$source\n--- END SANITIZED PAGE HTML ---';
  static String sanitize(String source) {
    final doc = html.parse(source);
    for (final element in doc.querySelectorAll(
      'script,style,input,textarea,select,form,noscript',
    )) {
      element.remove();
    }
    for (final element in doc.querySelectorAll('*')) {
      element.attributes.removeWhere(
        (name, _) =>
            name.toString().startsWith('on') ||
            name.toString().startsWith('data-') ||
            name == 'value' ||
            name == 'nonce',
      );
      for (final name in ['href', 'src']) {
        final url = Uri.tryParse(element.attributes[name] ?? '');
        if (url == null) continue;
        if (url.userInfo.isNotEmpty ||
            url.queryParameters.keys.any(
              (key) => RegExp(
                r'token|csrf|password|session|auth|verify|secret',
                caseSensitive: false,
              ).hasMatch(key),
            )) {
          element.attributes.remove(name);
        }
      }
    }
    final output = doc.outerHtml;
    return output.length <= 2 * 1024 * 1024
        ? output
        : '${output.substring(0, 2 * 1024 * 1024)}\n[Truncated]';
  }
}
