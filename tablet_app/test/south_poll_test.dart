import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';
import 'package:forum_tablet/south_poll.dart';
import 'package:forum_tablet/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppStrings.load);
  test('Poll controls are display-only, hidden counts stay unknown and quoted forms are ignored', () {
    final page = Uri.parse('https://south-plus.net/read.php?tid=1');
    const form =
        '<form name="vote" action="job.php?action=vote"><table><tr><td><input name="voteid[]" type="checkbox" checked>A</td><td>Hidden</td></tr><tr><td><input name="voteid[]" type="checkbox">B</td><td>Hidden</td></tr></table></form>';
    final poll = SouthPoll.parse(parse(form), page)!;
    expect(poll.options.length, 2);
    expect(poll.options.first.selected, isTrue);
    expect(poll.total, isNull);
    expect(
      SouthPoll.parse(parse('<blockquote>$form</blockquote>'), page),
      isNull,
    );
    expect(
      SouthPoll.parse(
        parse(form.replaceFirst('job.php', 'https://evil.invalid/job.php')),
        page,
      ),
      isNull,
    );
  });
}
