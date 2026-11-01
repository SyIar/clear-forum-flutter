import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/settings_store.dart';
import 'draft_attachments.dart';

class ThemeBackdrop extends StatefulWidget {
  const ThemeBackdrop({super.key, required this.settings, required this.child});
  final SettingsStore settings;
  final Widget child;

  @override
  State<ThemeBackdrop> createState() => _ThemeBackdropState();
}

class _ThemeBackdropState extends State<ThemeBackdrop> {
  String _identifier = '';
  Future<Uint8List>? _image;

  void _resolve() {
    final identifier = widget.settings.getString('themeBackground');
    if (identifier == _identifier) return;
    _identifier = identifier;
    _image = identifier.isEmpty
        ? null
        : DraftAttachments.restoreImage(identifier)
              .then((file) => file.readAsBytes());
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ThemeBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blur = widget.settings
        .getDouble('themeBackgroundBlur')
        .clamp(0.0, 20.0);
    final shade = widget.settings
        .getDouble('themeBackgroundShade', fallback: .2)
        .clamp(0.0, .8);
    return ColoredBox(
      color: Theme.of(context).canvasColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_image != null)
            FutureBuilder<Uint8List>(
              future: _image,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: blur,
                    sigmaY: blur,
                    tileMode: TileMode.clamp,
                  ),
                  child: Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    color: (dark ? Colors.black : Colors.white).withValues(
                      alpha: shade,
                    ),
                    colorBlendMode: BlendMode.srcATop,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                );
              },
            ),
          widget.child,
        ],
      ),
    );
  }
}
