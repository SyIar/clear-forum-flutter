import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'common.dart';

class _NetworkImages {
  static final unmetered = ValueNotifier<bool?>(null);
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static bool _started = false;
  static void start() {
    if (_started) return;
    _started = true;
    if (kIsWeb) {
      unmetered.value = true;
      return;
    }
    final connectivity = Connectivity();
    void update(List<ConnectivityResult> values) => unmetered.value =
        values.contains(ConnectivityResult.wifi) ||
        values.contains(ConnectivityResult.ethernet);
    connectivity.checkConnectivity().then(update).catchError((Object _) {
      unmetered.value = false;
    });
    _subscription = connectivity.onConnectivityChanged.listen(
      update,
      onError: (Object _) {
        unmetered.value = false;
      },
    );
    assert(_subscription != null);
  }
}

class PolicyImage extends StatefulWidget {
  const PolicyImage({
    super.key,
    required this.original,
    this.thumbnail = '',
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });
  final String original, thumbnail;
  final BoxFit fit;
  final double? width, height;
  @override
  State<PolicyImage> createState() => _PolicyImageState();
}

class _PolicyImageState extends State<PolicyImage> {
  bool _requested = false;
  Timer? _defer;
  @override
  void initState() {
    super.initState();
    _NetworkImages.start();
  }

  @override
  void didUpdateWidget(PolicyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.original != widget.original) _requested = false;
  }

  @override
  void dispose() {
    _defer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final mode = settings.getString('imageLoadType', fallback: '0');
    if (!_requested &&
        !settings.getBool('loadPictureWhenScroll', fallback: true) &&
        Scrollable.recommendDeferredLoadingForContext(context)) {
      _defer ??= Timer(const Duration(milliseconds: 200), () {
        _defer = null;
        if (mounted) setState(() {});
      });
      return SizedBox(
        width: widget.width,
        height: widget.height ?? 96,
        child: ColoredBox(color: context.colors.surfaceContainerHighest),
      );
    }
    return ValueListenableBuilder<bool?>(
      valueListenable: _NetworkImages.unmetered,
      builder: (context, unmetered, _) {
        final automatic = switch (mode) {
          '3' => false,
          '1' => unmetered == true,
          '0' => unmetered == true || widget.thumbnail.isNotEmpty,
          _ => true,
        };
        if (!_requested && !automatic) {
          return GestureDetector(
            onTap: () => setState(() => _requested = true),
            child: Container(
              width: widget.width,
              height: widget.height ?? 96,
              color: context.colors.surfaceContainerHighest,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, color: context.colors.outline),
                    const SizedBox(height: 5),
                    Text(
                      context.l10n.tapToLoad,
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final source =
            !_requested &&
                mode == '0' &&
                unmetered != true &&
                widget.thumbnail.isNotEmpty
            ? widget.thumbnail
            : widget.original;
        return CachedNetworkImage(
          imageUrl: source,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          color:
              Theme.of(context).brightness == Brightness.dark &&
                  settings.getBool('imageDarkenWhenNightMode', fallback: true)
              ? Colors.white70
              : null,
          colorBlendMode: BlendMode.modulate,
          placeholder: (_, _) => SizedBox(
            width: widget.width,
            height: widget.height ?? 96,
            child: ColoredBox(color: context.colors.surfaceContainerHighest),
          ),
          errorWidget: (_, _, _) => SizedBox(
            width: widget.width,
            height: widget.height ?? 70,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: context.colors.outline,
              ),
            ),
          ),
        );
      },
    );
  }
}
