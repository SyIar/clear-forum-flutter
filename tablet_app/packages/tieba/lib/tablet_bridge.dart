import 'package:flutter/material.dart';

/// Host-supplied library keeps the package independent of the shared downloader.
class TabletBridge {
  static WidgetBuilder? downloads;
  static Future<void> Function(String)? download;
  static String downloadsLabel = 'Downloads';
}

class ThreadPaneScope extends InheritedWidget {
  const ThreadPaneScope({super.key, required this.open, required super.child});
  final void Function(Widget) open;
  static ThreadPaneScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThreadPaneScope>();
  @override
  bool updateShouldNotify(ThreadPaneScope oldWidget) => open != oldWidget.open;
}

class TabletThreadHost extends StatefulWidget {
  const TabletThreadHost({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<TabletThreadHost> createState() => _TabletThreadHostState();
}

class _TabletThreadHostState extends State<TabletThreadHost> {
  Widget? _detail;
  int _generation = 0;
  final _masterKey = GlobalKey();
  final _detailKey = GlobalKey();
  void _open(Widget detail) => setState(() {
    _detail = detail;
    _generation++;
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      final detail = KeyedSubtree(
        key: _detailKey,
        child: _detail == null
            ? const Center(child: Icon(Icons.menu_book_outlined, size: 64))
            : Navigator(
                key: ValueKey(_generation),
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: (_) => _detail!),
              ),
      );
      final master = KeyedSubtree(
        key: _masterKey,
        child: ThreadPaneScope(
          open: _open,
          child: Builder(builder: widget.builder),
        ),
      );
      return PopScope(
        canPop: wide || _detail == null,
        onPopInvokedWithResult: (popped, result) {
          if (!popped && _detail != null) setState(() => _detail = null);
        },
        child: Row(
          children: [
            Offstage(
              offstage: !wide && _detail != null,
              child: SizedBox(
                width: wide
                    ? (constraints.maxWidth * .34).clamp(208, 340)
                    : constraints.maxWidth,
                child: master,
              ),
            ),
            if (wide) const VerticalDivider(width: 1),
            if (wide || _detail != null)
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: detail),
                    if (!wide && _detail != null)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top,
                        left: 0,
                        child: IconButton.filledTonal(
                          onPressed: () => setState(() => _detail = null),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
