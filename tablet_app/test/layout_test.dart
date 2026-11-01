import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forum_tablet/forum_app.dart';
import 'package:forum_tablet/library.dart';
import 'package:forum_tablet/session.dart';
import 'package:forum_tablet/site.dart';
import 'package:forum_tablet/strings.dart';
import 'package:tieba_lite/tablet_bridge.dart';
import 'package:tieba_lite/core/app_controller.dart';
import 'package:tieba_lite/core/session_store.dart';
import 'package:tieba_lite/core/settings_store.dart';
import 'package:tieba_lite/core/local_store.dart';
import 'package:tieba_lite/core/models.dart';
import 'package:tieba_lite/l10n/app_localizations.dart';
import 'package:tieba_lite/widgets/content_cards.dart';

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
  testWidgets('Tieba cards fit the portrait directory at enlarged text size', (
    tester,
  ) async {
    final app = AppController(
      sessions: SessionStore(),
      settings: SettingsStore(),
      local: LocalStore(),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: SizedBox(
                width: 218,
                child: ThreadCard(
                  thread: ThreadSummary(
                    title: 'A long thread title in the directory',
                    author: const UserProfile(name: 'A long user name'),
                    forum: const Forum(name: 'A long forum name'),
                    replyCount: 99999,
                    createdAt: DateTime(2026, 10, 1),
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Tieba thread pane retains its detail across tablet rotation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 960);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: TabletThreadHost(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  ThreadPaneScope.of(context)!
                      .open(const Scaffold(body: Text('Thread detail'))),
              child: const Text('Directory'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Directory'));
    await tester.pumpAndSettle();
    for (final size in [
      const Size(640, 960),
      const Size(960, 640),
      const Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.text('Thread detail'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  for (final module in [Module.simp, Module.south, Module.bookhouse]) {
    testWidgets('${module.name} keeps list and reader visible after rotation', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 960);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final site = ForumSite(module);
      final store = LibraryStore(
        await SharedPreferences.getInstance(),
        site: site,
      );
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
      await tester.tap(find.text(tr('Browse forums')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open fixture'));
      await tester.pumpAndSettle();
      expect(find.text('Open fixture'), findsOneWidget);
      expect(find.text('A readable paragraph.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(tr('Downloads')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(tr('Home')));
      await tester.pumpAndSettle();
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
