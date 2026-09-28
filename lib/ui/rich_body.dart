import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';

class RichBody extends StatelessWidget {
  const RichBody({super.key, required this.blocks, required this.onLink});
  final List<BodyBlock> blocks;
  final ValueChanged<Uri> onLink;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final block in blocks)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: switch (block.kind) {
            BlockKind.paragraph => _RunText(runs: block.runs, onLink: onLink),
            BlockKind.quote => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (block.label.isNotEmpty)
                    Text(
                      block.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  RichBody(blocks: block.children, onLink: onLink),
                ],
              ),
            ),
            BlockKind.spoiler => ExpansionTile(
              key: ValueKey(block),
              tilePadding: const EdgeInsets.symmetric(horizontal: 10),
              title: Text(block.label, style: const TextStyle(fontSize: 14)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: RichBody(blocks: block.children, onLink: onLink),
                ),
              ],
            ),
            BlockKind.code => Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SelectableText(
                block.label,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            BlockKind.image => _ReaderImage(
              key: ValueKey(block.url),
              block: block,
            ),
            BlockKind.embeddedMedia => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.video_library_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          block.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Text(
                          'Playback is not supported in this reader.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            BlockKind.link => TextButton(
              onPressed: block.url == null ? null : () => onLink(block.url!),
              child: Text(block.label),
            ),
          },
        ),
    ],
  );
}

class _RunText extends StatefulWidget {
  const _RunText({required this.runs, required this.onLink});
  final List<TextRun> runs;
  final ValueChanged<Uri> onLink;
  @override
  State<_RunText> createState() => _RunTextState();
}

class _RunTextState extends State<_RunText> {
  final List<TapGestureRecognizer> _recognizers = [];
  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    return Text.rich(
      TextSpan(
        children: widget.runs.map((run) {
          TapGestureRecognizer? recognizer;
          if (run.url != null) {
            recognizer = TapGestureRecognizer()
              ..onTap = () => widget.onLink(run.url!);
            _recognizers.add(recognizer);
          }
          return TextSpan(
            text: run.text,
            recognizer: recognizer,
            style: TextStyle(
              fontWeight: run.bold ? FontWeight.w600 : null,
              fontStyle: run.italic ? FontStyle.italic : null,
              color: run.url == null
                  ? null
                  : Theme.of(context).colorScheme.primary,
              decoration: run.url == null ? null : TextDecoration.underline,
            ),
          );
        }).toList(),
      ),
      style: const TextStyle(fontSize: 16, height: 1.4),
    );
  }
}

class _ReaderImage extends StatefulWidget {
  const _ReaderImage({super.key, required this.block});
  final BodyBlock block;
  @override
  State<_ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<_ReaderImage> {
  bool _load = false;
  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    if (!_load) {
      return OutlinedButton.icon(
        onPressed: () => setState(() => _load = true),
        icon: const Icon(Icons.image_outlined),
        label: Text(
          'Load image \u00b7 ${block.url?.host ?? ''}',
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 600),
      child: Image.network(
        block.url.toString(),
        fit: BoxFit.contain,
        cacheWidth: 1200,
        errorBuilder: (_, _, _) => const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Image unavailable. It may require its original page.'),
        ),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}
