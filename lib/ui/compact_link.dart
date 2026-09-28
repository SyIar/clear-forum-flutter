import 'package:flutter/material.dart';

class CompactLink extends StatelessWidget {
  const CompactLink({
    super.key,
    required this.url,
    required this.label,
    required this.onTap,
  });
  final Uri url;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = label.trim().replaceAll(RegExp(r'\s+'), ' ');
    final caption = text.startsWith('https://') ? text.substring(8) : text;
    return Tooltip(
      message: url.toString(),
      child: Semantics(
        link: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, maxWidth: 280),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: .65),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link, size: 13, color: colors.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        caption.isEmpty ? url.host : caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
