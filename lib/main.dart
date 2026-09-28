import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'core/session.dart';
import 'ui/reader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    WidgetsBinding.instance.ensureSemantics();
  }
  runApp(const ClearForumApp());
}

class ClearForumApp extends StatelessWidget {
  const ClearForumApp({super.key});
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Clear Forum',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: const WelcomePage(),
  );
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});
  void _open(BuildContext context, bool demo) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ReaderPage(source: demo ? DemoSource() : DeviceSession(), demo: demo),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.chrome_reader_mode_outlined,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 28),
                Text(
                  'A little less noise.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Clear Forum',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your forum. A clean, compact reading space.\nYour sign-in stays on this device.',
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                if (DeviceSession.supported)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _open(context, false),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Open forum'),
                    ),
                  ),
                if (!DeviceSession.supported)
                  const Text(
                    'Live sign-in is available in the iPhone app. This preview uses sample content.',
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _open(context, true),
                    child: const Text('Explore sample reader'),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'No account is needed for the sample.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
