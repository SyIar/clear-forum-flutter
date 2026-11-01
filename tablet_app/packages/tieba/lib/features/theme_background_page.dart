import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_controller.dart';
import '../platform/draft_attachments.dart';
import '../widgets/common.dart';

class ThemeBackgroundPage extends StatefulWidget {
  const ThemeBackgroundPage({super.key});
  @override
  State<ThemeBackgroundPage> createState() => _ThemeBackgroundPageState();
}

class _ThemeBackgroundPageState extends State<ThemeBackgroundPage> {
  bool _busy = false;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() => _busy = true);
    final settings = AppScope.read(context).settings;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        imageQuality: 90,
      );
      if (file == null) return;
      final retained = await DraftAttachments.retainImage(file);
      await settings.setString('themeBackground', retained);
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.operationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return Scaffold(
      appBar: GlassAppBar(title: Text(context.l10n.backgroundTheme)),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(),
          SurfaceCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.wallpaper_rounded),
                  title: Text(context.l10n.chooseBackground),
                  onTap: _busy || kIsWeb ? null : _choose,
                ),
                if (settings.getString('themeBackground').isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.hide_image_outlined),
                    title: Text(context.l10n.removeBackground),
                    onTap: _busy
                        ? null
                        : () => settings.setString('themeBackground', ''),
                  ),
                _slider(
                  context.l10n.backgroundBlur,
                  'themeBackgroundBlur',
                  0,
                  20,
                  0,
                ),
                _slider(
                  context.l10n.surfaceOpacity,
                  'themeSurfaceOpacity',
                  .2,
                  1,
                  .85,
                ),
                _slider(
                  context.l10n.backgroundShade,
                  'themeBackgroundShade',
                  0,
                  .8,
                  .2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    String key,
    double min,
    double max,
    double fallback,
  ) {
    final settings = AppScope.of(context).settings;
    final value = settings.getDouble(key, fallback: fallback).clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(title: Text(label), trailing: Text(value.toStringAsFixed(2))),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: 20,
          onChanged: _busy ? null : (value) => settings.setDouble(key, value),
        ),
      ],
    );
  }
}
