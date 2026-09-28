import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'core/session.dart';
import 'core/library.dart';
import 'ui/home.dart';

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
      title: 'simpcity ultimate',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    ),
  );
}
