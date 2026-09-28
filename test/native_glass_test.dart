import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_forum/ui/native_glass.dart';

void main() {
  testWidgets(
    'native controls synchronize state, reject disabled events and hide beneath routes',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      Map<Object?, Object?>? creation;
      final updates = <Map<Object?, Object?>>[];
      String? channel;
      final events = <String>[];
      final navigation = GlobalKey<NavigatorState>();
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final args = call.arguments as Map;
          expect(args['viewType'], 'dev.sylar.clearforum/glass');
          creation = const StandardMessageCodec().decodeMessage(
            ByteData.sublistView(args['params'] as Uint8List),
          ) as Map<Object?, Object?>;
          channel = 'dev.sylar.clearforum/glass/${args['id']}';
          messenger.setMockMethodCallHandler(MethodChannel(channel!), (
            call,
          ) async {
            if (call.method == 'update') {
              updates.add(Map<Object?, Object?>.from(call.arguments as Map));
            }
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (channel != null) {
          messenger.setMockMethodCallHandler(MethodChannel(channel!), null);
        }
      });
      Future<void> host({bool disabled = false, bool dark = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigation,
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: NativeGlassControl(
                    kind: 'toolbar',
                    title: 'Page 3',
                    selectedIndex: 1,
                    actions: [
                      NativeGlassAction(
                        id: 'previous',
                        label: 'Previous page',
                        symbol: 'chevron.backward',
                        onPressed: disabled
                            ? null
                            : () => events.add('previous'),
                      ),
                      NativeGlassAction(
                        id: 'save',
                        label: 'Save',
                        symbol: 'bookmark',
                        selected: dark,
                        onPressed: () => events.add('save'),
                      ),
                      NativeGlassAction(
                        id: 'menu',
                        label: 'More',
                        symbol: 'ellipsis',
                        menu: [
                          NativeGlassAction(
                            id: 'sort',
                            label: 'Sort',
                            symbol: '',
                            selected: true,
                            onPressed: () => events.add('sort'),
                          ),
                        ],
                      ),
                    ],
                    fallback: const Text('Fallback'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> event(String id) async {
        final reply = Completer<void>();
        tester.binding.channelBuffers.push(
          channel!,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('action', id),
          ),
          (_) => reply.complete(),
        );
        await tester.pump();
        await reply.future;
      }

      await host();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(find.text('Fallback'), findsNothing);
      expect(creation?['title'], 'Page 3');
      expect(creation?['selectedIndex'], 1);
      await event('previous');
      await event('sort');
      expect(events, ['previous', 'sort']);
      await host(disabled: true, dark: true);
      expect(updates.last['dark'], isTrue);
      final actions = updates.last['actions'] as List;
      expect((actions.first as Map)['enabled'], isFalse);
      expect((actions[1] as Map)['selected'], isTrue);
      await event('previous');
      await event('unknown');
      expect(events.length, 2);
      await event('save');
      expect(events.last, 'save');
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(NativeGlassControl)),
          builder: (_) => const AlertDialog(content: Text('Overlay')),
        ),
      );
      await tester.pumpAndSettle();
      expect(updates.last['visible'], isFalse);
      await event('save');
      expect(events.length, 3);
      navigation.currentState!.pop();
      await tester.pumpAndSettle();
      expect(updates.last['visible'], isTrue);
      await event('save');
      expect(events.length, 4);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
