import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forum_tablet/forum_app.dart';
import 'package:forum_tablet/library.dart';
import 'package:forum_tablet/session.dart';
import 'package:forum_tablet/site.dart';
import 'package:forum_tablet/strings.dart';

class FixtureSession extends ForumSession {
  FixtureSession(super.site);
  @override
  Future<PageCapture> fetch(Uri url, {bool offline = false}) async {
    final thread =
        url.path == '/read.php' ||
        url.queryParameters['act'] == 'threadview' ||
        url.path.startsWith('/threads/');
    return PageCapture(url, switch (site.module) {
      Module.south =>
        thread
            ? '<h1 id="subject_tpc">A long example thread title</h1><table class="js-post"><tr><td><a href="u.php?uid=1">Author</a><div class="tpc_content">A readable paragraph.</div></td></tr></table>'
            : '<title>Board</title><div id="ajaxtable"><h3><a href="read.php?tid=1">Open fixture</a></h3></div>',
      Module.simp =>
        thread
            ? '<h1 class="p-title-value">A long example thread title</h1><article class="message--post"><div class="message-body"><div class="bbWrapper">A readable paragraph.</div></div></article>'
            : '<div class="structItem--thread"><div class="structItem-title"><a href="/threads/fixture.1/">Open fixture</a></div></div>',
      _ =>
        thread
            ? '<h1 class="main-title">A long example thread title</h1><div id="content-section"><pre>A readable paragraph.</pre></div>'
            : '<ul class="thread-list"><li><a href="?app=forum&act=threadview&tid=1">Open fixture</a></li></ul>',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppStrings.load);
  for (final module in [Module.simp, Module.south, Module.bookhouse]) {
    testWidgets('${module.name} keeps list and reader visible after rotation', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 960);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = LibraryStore(await SharedPreferences.getInstance());
      final site = ForumSite(module);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh')],
          home: ForumShell(
            site: site,
            library: store,
            session: FixtureSession(site),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open fixture'));
      await tester.pumpAndSettle();
      expect(find.text('Open fixture'), findsOneWidget);
      expect(find.text('A readable paragraph.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(960, 640);
      await tester.pumpAndSettle();
      expect(find.text('Open fixture'), findsOneWidget);
      expect(find.text('A readable paragraph.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.text('A readable paragraph.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
