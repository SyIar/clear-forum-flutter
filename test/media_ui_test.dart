import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/ui/rich_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('media is user-triggered and remains reachable inside spoilers', (
    tester,
  ) async {
    final opened = <BodyBlock>[];
    final media = BodyBlock(
      BlockKind.embeddedMedia,
      label: 'player.example',
      url: Uri.parse('https://player.example/embed/sample'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichBody(
            blocks: [
              BodyBlock(BlockKind.spoiler, label: 'Spoiler', children: [media]),
            ],
            onLink: (_) {},
            onMedia: opened.add,
          ),
        ),
      ),
    );
    expect(opened, isEmpty);
    await tester.tap(find.text('Spoiler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to open video player'));
    expect(opened, [media]);
  });
  testWidgets('missing URLs stay explicit and cannot launch a player', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichBody(
            blocks: const [
              BodyBlock(BlockKind.embeddedMedia, label: 'Embedded media'),
            ],
            onLink: (_) {},
            onMedia: (_) => called = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('No playable URL was found in this page.'));
    expect(called, false);
  });
}
