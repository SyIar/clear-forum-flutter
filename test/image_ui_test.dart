import 'dart:ui' as ui;

import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/ui/media_widgets.dart';
import 'package:clean_forum/ui/rich_body.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BodyBlock picture(String name, {double? ratio}) => BodyBlock(
    BlockKind.image,
    label: name,
    url: Uri.https('images.example', '/$name.png'),
    aspectRatio: ratio,
  );

  Widget reader(List<BodyBlock> blocks, ReaderImageProvider provider) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichBody(
              blocks: blocks,
              onLink: (_) {},
              imageProvider: provider,
            ),
          ),
        ),
      );

  testWidgets('images load without a tap, show progress and allow zoom', (
    tester,
  ) async {
    final provider = _ControlledImage();
    await tester.pumpWidget(reader([picture('first')], (_) => provider));
    expect(provider.streams.length, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    provider.streams.single.complete(800, 500);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    provider.streams.last.complete(800, 500);
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });

  testWidgets(
    'failed images can retry and recover without reopening the page',
    (tester) async {
      final provider = _ControlledImage();
      await tester.pumpWidget(reader([picture('retry')], (_) => provider));
      provider.streams.single.fail();
      await tester.pump();
      expect(find.text('Retry image'), findsOneWidget);
      await tester.tap(find.text('Retry image'));
      await tester.pump();
      expect(provider.streams.length, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      provider.streams.last.complete(400, 400);
      await tester.pumpAndSettle();
      expect(find.text('Retry image'), findsNothing);
      expect(tester.takeException(), null);
    },
  );

  testWidgets('adjacent images share a row and text separates image groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _ControlledImage();
    await tester.pumpWidget(
      reader([
        picture('first', ratio: 1.6),
        picture('second', ratio: 1.6),
        const BodyBlock(BlockKind.paragraph, runs: [TextRun('Between images')]),
        picture('third', ratio: 1.6),
      ], (_) => provider),
    );
    provider.streams.single.complete(800, 500);
    await tester.pumpAndSettle();
    expect(find.byType(ImageGallery), findsNWidgets(2));
    final images = find.byType(Image);
    expect(
      tester.getTopLeft(images.at(0)).dy,
      tester.getTopLeft(images.at(1)).dy,
    );
    expect(
      tester.getTopLeft(images.at(0)).dx,
      lessThan(tester.getTopLeft(images.at(1)).dx),
    );
    expect(
      tester.getTopLeft(find.text('Between images')).dy,
      greaterThan(tester.getBottomLeft(images.at(0)).dy),
    );
    expect(
      tester.getTopLeft(images.at(2)).dy,
      greaterThan(tester.getBottomLeft(find.text('Between images')).dy),
    );
  });

  testWidgets('decoded proportions cap tall previews and preserve fitting', (
    tester,
  ) async {
    final provider = _ControlledImage();
    await tester.pumpWidget(reader([picture('tall')], (_) => provider));
    provider.streams.single.complete(100, 1600);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Image)).height, lessThanOrEqualTo(420));
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    expect(tester.takeException(), null);
  });

  testWidgets('closed spoilers do not request hidden images', (tester) async {
    final provider = _ControlledImage();
    await tester.pumpWidget(
      reader([
        BodyBlock(
          BlockKind.spoiler,
          label: 'Spoiler',
          children: [picture('hidden')],
        ),
      ], (_) => provider),
    );
    expect(provider.streams, isEmpty);
    await tester.tap(find.text('Spoiler'));
    await tester.pump();
    expect(provider.streams.length, 1);
    provider.streams.single.complete(400, 400);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'thumbnail is separate from playback even on a narrow dark screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = _ControlledImage();
      var plays = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: MediaCard(
                block: BodyBlock(
                  BlockKind.embeddedMedia,
                  label: 'player.example',
                  url: Uri.https('player.example', '/embed/sample'),
                  posterUrl: Uri.https('images.example', '/poster.png'),
                ),
                imageProvider: (_) => provider,
                onPlay: () => plays++,
              ),
            ),
          ),
        ),
      );
      expect(plays, 0);
      provider.streams.single.fail();
      await tester.pumpAndSettle();
      final thumbnail = find.byIcon(Icons.image_not_supported_outlined);
      await tester.tap(thumbnail);
      expect(plays, 0);
      final play = find.text('Tap to play');
      expect(
        tester.getCenter(thumbnail).dx,
        lessThan(tester.getTopLeft(play).dx),
      );
      await tester.tap(play);
      expect(plays, 1);
      expect(tester.takeException(), null);
    },
  );
}

class _ControlledImage extends ImageProvider<_ControlledImage> {
  final streams = <_ImageCompleter>[];

  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _ControlledImage key,
    ImageDecoderCallback decode,
  ) {
    final stream = _ImageCompleter();
    streams.add(stream);
    return stream;
  }
}

class _ImageCompleter extends ImageStreamCompleter {
  void complete(int width, int height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFF407C87), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    setImage(ImageInfo(image: image));
  }

  void fail() => reportError(exception: StateError('Sample image unavailable'));
}
