import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'core/session.dart';
import 'core/library.dart';
import 'core/site.dart';
import 'ui/home.dart';
import 'ui/reader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    WidgetsBinding.instance.ensureSemantics();
  }
  runApp(const ClearForumApp());
}

class ClearForumApp extends StatefulWidget {
  const ClearForumApp({super.key, this.library});
  final ReadingLibrary? library;
  @override
  State<ClearForumApp> createState() => _ClearForumAppState();
}

class _ClearForumAppState extends State<ClearForumApp> {
  late final ReadingLibrary _library;
  @override
  void initState() {
    super.initState();
    _library =
        widget.library ?? ReadingLibrary(sample: !DeviceSession.supported);
    _library.load().catchError((Object _) {});
  }

  @override
  void dispose() {
    if (widget.library == null) _library.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff087ff5),
          brightness: brightness,
        ).copyWith(
          surface: dark ? const Color(0xff080808) : Colors.white,
          primary: dark ? const Color(0xff68b2ff) : const Color(0xff066bd6),
          surfaceContainerLow: dark
              ? const Color(0xff101012)
              : const Color(0xfff2f3f5),
          surfaceContainer: dark
              ? const Color(0xff232326)
              : const Color(0xfff1f2f4),
          outlineVariant: dark
              ? const Color(0xff3a3a3e)
              : const Color(0xffdfe1e5),
          onSurfaceVariant: dark
              ? const Color(0xffa7a7ad)
              : const Color(0xff777b83),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white12 : Colors.black12,
        thickness: .5,
        space: 1,
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: dark ? const Color(0xffeeeeee) : const Color(0xff151515),
        displayColor: dark ? Colors.white : Colors.black,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LibraryScope(
    library: _library,
    child: MaterialApp(
      title: 'simp lite',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: kIsWeb && Uri.base.queryParameters['appearance'] == 'light'
          ? ThemeMode.light
          : kIsWeb && Uri.base.queryParameters['appearance'] == 'dark'
          ? ThemeMode.dark
          : ThemeMode.system,
      home: kIsWeb && Uri.base.queryParameters['demo'] == 'thread'
          ? ReaderPage(
              source: DemoSource(),
              url: ForumSite.base.resolve('/threads/quiet-reading.101/'),
              demo: true,
            )
          : const HomePage(),
    ),
  );
}
