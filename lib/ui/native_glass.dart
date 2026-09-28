import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool get usesNativeGlass =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class NativeGlassAction {
  const NativeGlassAction({
    required this.id,
    required this.label,
    required this.symbol,
    this.onPressed,
    this.selected = false,
    this.showLabel = false,
    this.destructive = false,
    this.menu = const [],
  });
  final String id, label, symbol;
  final VoidCallback? onPressed;
  final bool selected, showLabel, destructive;
  final List<NativeGlassAction> menu;

  Map<String, Object?> toMap() => {
    'id': id,
    'label': label,
    'symbol': symbol,
    'enabled': onPressed != null || menu.isNotEmpty,
    'selected': selected,
    'showLabel': showLabel,
    'destructive': destructive,
    'menu': menu.map((item) => item.toMap()).toList(),
  };
}

/// One native view owns both the material and its controls.
class NativeGlassControl extends StatefulWidget {
  const NativeGlassControl({
    super.key,
    required this.kind,
    required this.actions,
    required this.fallback,
    this.title = '',
    this.selectedIndex = 0,
    this.height = 56,
  });
  final String kind, title;
  final List<NativeGlassAction> actions;
  final int selectedIndex;
  final double height;
  final Widget fallback;
  @override
  State<NativeGlassControl> createState() => _NativeGlassControlState();
}

class _NativeGlassControlState extends State<NativeGlassControl> {
  MethodChannel? _channel;
  static const _viewType = 'dev.sylar.clearforum/glass';
  Map<String, Object?> get _configuration => {
    'kind': widget.kind,
    'title': widget.title,
    'actions': widget.actions.map((action) => action.toMap()).toList(),
    'selectedIndex': widget.selectedIndex,
    'dark': Theme.of(context).brightness == Brightness.dark,
    'tint': Theme.of(context).colorScheme.primary.toARGB32(),
    'textScale': MediaQuery.textScalerOf(context).scale(16) / 16,
    'visible': ModalRoute.of(context)?.isCurrent ?? true,
  };

  @override
  void didUpdateWidget(NativeGlassControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  Future<void> _update() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>('update', _configuration);
    } on MissingPluginException {
      // A platform view may be disposed while an appearance update is queued.
    } on PlatformException catch (_) {
      if (mounted) rethrow;
    }
  }

  void _created(int id) {
    _channel = MethodChannel('$_viewType/$id');
    _channel!.setMethodCallHandler((call) async {
      if (!mounted ||
          call.method != 'action' ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      final id = call.arguments;
      for (final action in widget.actions) {
        for (final candidate in [action, ...action.menu]) {
          if (candidate.id == id) {
            candidate.onPressed?.call();
            return;
          }
        }
      }
    });
    // Creation parameters may be older than the current widget state.
    _update();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!usesNativeGlass) return widget.fallback;
    return SizedBox(
      height: widget.height,
      child: UiKitView(
        viewType: _viewType,
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
        // No eager recognizer: vertical drags remain available to Flutter.
      ),
    );
  }
}
