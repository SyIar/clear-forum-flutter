import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/diagnostics.dart';

void main() {
  test('Copied diagnostics preserve body and images but remove credentials and executable data', () {
    final data = PageDiagnostic(
      Uri.parse('https://example.com/thread/20'),
      'Parsed',
      '<script>secret-script</script><form><input value="secret-password"></form>'
          '<div data-token="secret-data" onclick="secret-handler">Visible body</div>'
          '<a href="/logout?verify=secret-query">Sign out</a><img src="https://images.example/photo.jpg">',
    );
    expect(data.text, contains('Visible body'));
    expect(data.text, contains('photo.jpg'));
    expect(data.text, isNot(contains('secret-')));
  });
  test(
    'Forum form bodies and lazy image evidence survive with redacted addresses',
    () {
      final data = PageDiagnostic(
        Uri.parse(
          'https://user:secret-login@example.com/read.php?tid=20&verify=secret-verify#secret-fragment',
        ),
        'Parsed',
        '<form action="secret-form-action"><div class="tpc_content">Post body'
            '<img data-src="//images.example/photo.jpg?token=secret-image" '
            'data-original="https://images.example/original.jpg"></div></form>'
            '<iframe srcdoc="secret-document"></iframe>'
            '<a href="job.php?action-buytopic-tid-20-verify-secret-legacy.html">Buy</a>'
            '<a href="javascript:secret-code">Link</a>',
      );
      expect(data.text, contains('Post body'));
      expect(data.text, contains('tid=20'));
      expect(data.text, contains('data-src="//images.example/photo.jpg'));
      expect(data.text, contains('original.jpg'));
      expect(data.text, isNot(contains('secret-')));
      expect(data.text, isNot(contains('javascript:')));
    },
  );
}
