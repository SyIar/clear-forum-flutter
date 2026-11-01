import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'common.dart';

class BlockedContent extends StatefulWidget {
  const BlockedContent({super.key, required this.blocked, required this.child});
  final bool blocked;
  final Widget child;
  @override
  State<BlockedContent> createState() => _BlockedContentState();
}

class _BlockedContentState extends State<BlockedContent> {
  bool _revealed = false;
  @override
  void didUpdateWidget(BlockedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blocked != widget.blocked) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    if (!widget.blocked || _revealed) return widget.child;
    if (settings.getBool('hideBlockedContent') ||
        !settings.getBool('showBlockTip', fallback: true)) {
      return const SizedBox.shrink();
    }
    return SurfaceCard(
      child: ListTile(
        leading: const Icon(Icons.visibility_off_outlined),
        title: Text(
          context.l10n.contentHidden,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: TextButton(
          onPressed: () => setState(() => _revealed = true),
          child: Text(context.l10n.showContent),
        ),
      ),
    );
  }
}
