import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class GlassAccessibility extends StatefulWidget {
  const GlassAccessibility({super.key, required this.child});
  final Widget child;

  @override
  State<GlassAccessibility> createState() => _GlassAccessibilityState();
}

class _GlassAccessibilityState extends State<GlassAccessibility>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('org.tblite.flutter/appearance');
  bool _reduceTransparency = false;
  bool _reduceMotion = false;

  bool get _native => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_native) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') _apply(call.arguments);
      });
      _read();
    }
  }

  void _apply(Object? value) {
    if (!mounted || value is! Map) return;
    final transparency = value['reduceTransparency'] == true;
    final motion = value['reduceMotion'] == true;
    if (transparency == _reduceTransparency && motion == _reduceMotion) return;
    setState(() {
      _reduceTransparency = transparency;
      _reduceMotion = motion;
    });
  }

  Future<void> _read() async {
    try {
      _apply(await _channel.invokeMapMethod<String, Object?>('settings'));
    } on MissingPluginException {
      // Flutter previews do not have the optional iOS accessibility bridge.
    } on PlatformException {
      // MediaQuery high-contrast settings still provide an opaque fallback.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_native && state == AppLifecycleState.resumed) _read();
  }

  @override
  Widget build(BuildContext context) => GlassAccessibilityScope(
    reduceTransparency: _reduceTransparency,
    reduceMotion: _reduceMotion,
    child: widget.child,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_native) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

class GlassAccessibilityScope extends InheritedWidget {
  const GlassAccessibilityScope({
    super.key,
    required this.reduceTransparency,
    required this.reduceMotion,
    required super.child,
  });
  final bool reduceTransparency, reduceMotion;

  static GlassAccessibilityScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassAccessibilityScope>();

  @override
  bool updateShouldNotify(GlassAccessibilityScope oldWidget) =>
      reduceTransparency != oldWidget.reduceTransparency ||
      reduceMotion != oldWidget.reduceMotion;
}
