import 'package:flutter/material.dart';

import '../platform/app_icons.dart';
import '../platform/image_cache_actions.dart';
import '../widgets/common.dart';

class ImageCacheTile extends StatefulWidget {
  const ImageCacheTile({super.key});
  @override
  State<ImageCacheTile> createState() => _ImageCacheTileState();
}

class _ImageCacheTileState extends State<ImageCacheTile> {
  late Future<int?> _bytes;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _bytes = ImageCacheActions.sizeBytes();
  }

  Future<void> _clear() async {
    if (_busy ||
        !await confirmAction(
          context,
          context.l10n.clearImageCache,
          context.l10n.clearImageCacheConfirm,
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    await performAction(
      context,
      ImageCacheActions.clear,
      requiresLogin: false,
      success: context.l10n.cacheCleared,
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _bytes = ImageCacheActions.sizeBytes();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int?>(
    future: _bytes,
    builder: (context, snapshot) => ListTile(
      leading: const Icon(Icons.cached_rounded),
      title: Text(context.l10n.imageCache),
      subtitle: Text(
        snapshot.hasData
            ? '${(snapshot.data! / (1024 * 1024)).toStringAsFixed(1)} MB'
            : context.l10n.cacheSizeUnknown,
      ),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cleaning_services_outlined),
      onTap: _busy ? null : _clear,
    ),
  );
}

class AppIconPage extends StatefulWidget {
  const AppIconPage({super.key});
  @override
  State<AppIconPage> createState() => _AppIconPageState();
}

class _AppIconPageState extends State<AppIconPage> {
  late Future<(bool, String)> _state;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _state = _load();
  }

  Future<(bool, String)> _load() async {
    final supported = await AppIcons.supported();
    return (supported, supported ? await AppIcons.current() : 'default');
  }

  Future<void> _select(String value) async {
    if (_busy) return;
    setState(() => _busy = true);
    await performAction(
      context,
      () => AppIcons.set(value),
      requiresLogin: false,
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _state = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(title: Text(context.l10n.appIcon)),
    body: FutureBuilder<(bool, String)>(
      future: _state,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorPanel(
            error: snapshot.error!,
            onRetry: () => setState(() => _state = _load()),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (!snapshot.data!.$1) {
          return EmptyPanel(
            icon: Icons.apps_rounded,
            message: context.l10n.iconUnavailable,
          );
        }
        return ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            for (final option in [
              ('default', context.l10n.iconDefault, const Color(0xFF167D8D)),
              ('blue', context.l10n.iconBlue, const Color(0xFF355CCE)),
              ('dark', context.l10n.iconDark, const Color(0xFF17222C)),
            ])
              SurfaceCard(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: option.$3,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.forum_rounded, color: Colors.white),
                  ),
                  title: Text(option.$2),
                  trailing: snapshot.data!.$2 == option.$1
                      ? Icon(Icons.check_rounded, color: context.colors.primary)
                      : null,
                  onTap: _busy || snapshot.data!.$2 == option.$1
                      ? null
                      : () => _select(option.$1),
                ),
              ),
          ],
        );
      },
    ),
  );
}
