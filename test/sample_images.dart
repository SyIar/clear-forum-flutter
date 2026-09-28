import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> preloadSampleImages(WidgetTester tester) async {
  final context = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final name in ['landscape', 'portrait', 'panorama']) {
      await precacheImage(
        ResizeImage(
          AssetImage('assets/demo/$name.png'),
          width: 1200,
          height: 2400,
          policy: ResizeImagePolicy.fit,
        ),
        context,
      );
    }
  });
}
