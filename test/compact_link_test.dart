import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/ui/compact_link.dart';
import 'package:clean_forum/ui/rich_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long external URLs use short boxes with full-size tap targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final url = Uri.https('example.org', '/notes/${'long-path-' * 20}');
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: RichBody(
              onLink: (value) => opened = value,
              blocks: [
                BodyBlock(
                  BlockKind.paragraph,
                  runs: [TextRun(url.toString(), url: url)],
                ),
                const BodyBlock(
                  BlockKind.paragraph,
                  runs: [TextRun('Next line')],
                ),
                BodyBlock(
                  BlockKind.link,
                  url: url,
                  label: 'A long descriptive title ' * 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CompactLink), findsNWidgets(2));
    for (final link in find.byType(CompactLink).evaluate()) {
      final size = tester.getSize(find.byWidget(link.widget));
      expect(size.height, inInclusiveRange(44, 48));
      expect(size.width, lessThanOrEqualTo(280));
    }
    await tester.tap(find.byType(CompactLink).first);
    expect(opened, url);
    expect(tester.takeException(), null);
  });
}
