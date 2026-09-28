import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/media_posters.dart';
import 'media_widgets.dart';

class RichBody extends StatelessWidget {
  const RichBody({
    super.key,
    required this.blocks,
    required this.onLink,
    this.onMedia,
    this.imageProvider = networkImageProvider,
    this.posterLoader,
  });
  final List<BodyBlock> blocks;
  final ValueChanged<Uri> onLink;
  final ValueChanged<BodyBlock>? onMedia;
  final ReaderImageProvider imageProvider;
  final PosterLoader? posterLoader;

  Iterable<List<BodyBlock>> _groups() sync* {
    var images = <BodyBlock>[];
    for (final block in blocks) {
      if (block.kind == BlockKind.image && block.url != null) {
        images.add(block);
      } else {
        if (images.isNotEmpty) yield images;
        images = [];
        yield [block];
      }
    }
    if (images.isNotEmpty) yield images;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final group in _groups())
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: _content(context, group),
        ),
    ],
  );

  Widget _content(BuildContext context, List<BodyBlock> group) {
    final block = group.first;
    return switch (block.kind) {
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
            RichBody(
              blocks: block.children,
              onLink: onLink,
              onMedia: onMedia,
              imageProvider: imageProvider,
              posterLoader: posterLoader,
            ),
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
            child: RichBody(
              blocks: block.children,
              onLink: onLink,
              onMedia: onMedia,
              imageProvider: imageProvider,
              posterLoader: posterLoader,
            ),
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
      BlockKind.image =>
        block.url == null
            ? const SizedBox.shrink()
            : ImageGallery(blocks: group, imageProvider: imageProvider),
      BlockKind.embeddedMedia => MediaCard(
        block: block,
        imageProvider: imageProvider,
        posterLoader: posterLoader,
        onPlay: onMedia == null ? null : () => onMedia!(block),
      ),
      BlockKind.link => Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: block.url == null ? null : () => onLink(block.url!),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.link, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        block.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (block.url != null)
                        Text(
                          block.url!.host,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new, size: 16),
              ],
            ),
          ),
        ),
      ),
    };
  }
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
