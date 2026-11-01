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
}
