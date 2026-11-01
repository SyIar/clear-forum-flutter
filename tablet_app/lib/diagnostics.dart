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
      'Forum Tablet reader diagnostics\n$captured\n${address('$url')}\n$state\n\n'
      '--- SANITIZED PAGE HTML ---\n$source\n--- END SANITIZED PAGE HTML ---';
  static String? address(String value) {
    final url = Uri.tryParse(value);
    if (url == null ||
        (url.hasScheme && !const ['http', 'https'].contains(url.scheme))) {
      return null;
    }
    const allowed = {
      'tid',
      'fid',
      'uid',
      'page',
      'type',
      'action',
      'act',
      'app',
      'p',
      'mtid',
    };
    final clean = url.replace(
      userInfo: '',
      fragment: '',
      queryParameters: url.query.contains('=')
          ? url.queryParametersAll.map(
              (key, values) => MapEntry(
                key,
                allowed.contains(key.toLowerCase()) ? values : ['[redacted]'],
              ),
            )
          : null,
    );
    if (!url.query.contains('=') &&
        RegExp(
          r'(?:^|-)(?:token|csrf|password|session|auth|verify|secret)-',
          caseSensitive: false,
        ).hasMatch(url.query)) {
      return clean.replace(query: '[redacted]').toString();
    }
    return clean.toString();
  }

  static String sanitize(String source) {
    final doc = html.parse(source);
    for (final element in doc.querySelectorAll(
      'script,style,input,textarea,select,object,embed,meta,link,iframe,svg,noscript',
    )) {
      element.remove();
    }
    const addresses = {
      'href',
      'src',
      'data-src',
      'data-original',
      'data-full-src',
      'data-full-url',
      'data-url',
    };
    const allowed = {
      ...addresses,
      'id',
      'class',
      'name',
      'type',
      'width',
      'height',
      'colspan',
      'rowspan',
      'loading',
      'referrerpolicy',
    };
    for (final element in doc.querySelectorAll('*')) {
      element.attributes.removeWhere((name, _) => !allowed.contains(name));
      for (final name in addresses) {
        final raw = element.attributes[name];
        if (raw == null) continue;
        final sanitized = address(raw);
        if (sanitized == null) {
          element.attributes.remove(name);
        } else {
          element.attributes[name] = sanitized;
        }
      }
    }
    final output = doc.outerHtml;
    return output.length <= 2 * 1024 * 1024
        ? output
        : '${output.substring(0, 2 * 1024 * 1024)}\n[Truncated]';
  }
}
