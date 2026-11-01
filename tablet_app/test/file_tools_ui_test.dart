import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/download_ui.dart';
import 'package:forum_tablet/downloads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    DownloadManager.instance.fileJob = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DownloadManager.channel, (call) async {
          calls.add(call);
          return {
            'state': 'running',
            'operation': 'extract',
            'source': '/Downloads/test.zip',
            'name': 'test.zip',
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DownloadManager.channel, null),
  );

  testWidgets(
    'encrypted ZIP prompt passes password only to the transient job',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    promptFileJob(context, 'extract', '/Downloads/test.zip'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'private-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Extract ZIP'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'startFileJob');
      expect(calls.single.arguments, {
        'operation': 'extract',
        'path': '/Downloads/test.zip',
        'password': 'private-password',
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FileJobStatus())),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('private-password'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel does not start a conversion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => promptFileJob(context, 'convert', '/Downloads'),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });
}
