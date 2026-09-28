import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/media_posters.dart';

typedef ReaderImageProvider = ImageProvider Function(Uri url);

ImageProvider networkImageProvider(Uri url) => NetworkImage(url.toString());

ImageProvider sampleImageProvider(Uri url) =>
    url.host == 'sample.invalid' &&
        url.pathSegments.isNotEmpty &&
        {
          'landscape.png',
          'portrait.png',
          'panorama.png',
        }.contains(url.pathSegments.last)
    ? AssetImage('assets/demo/${url.pathSegments.last}')
    : networkImageProvider(url);

class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.block,
    this.onPlay,
    this.imageProvider = networkImageProvider,
    this.posterLoader,
  });
  final BodyBlock block;
  final VoidCallback? onPlay;
  final ReaderImageProvider imageProvider;
  final PosterLoader? posterLoader;
  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  Future<Uri?>? _poster;
  @override
  void initState() {
    super.initState();
    _loadPoster();
  }

  @override
  void didUpdateWidget(covariant MediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block ||
        oldWidget.posterLoader != widget.posterLoader) {
      _loadPoster();
    }
  }

  void _loadPoster() {
    _poster = widget.block.posterUrl != null
        ? Future.value(widget.block.posterUrl)
        : widget.posterLoader?.call(widget.block);
  }

  ImageProvider _posterProvider(Uri url) =>
      widget.imageProvider == networkImageProvider
      ? NetworkImage(
          url.toString(),
          headers: {
            if (widget.block.url != null)
              'Referer': '${widget.block.url!.origin}/',
          },
        )
      : widget.imageProvider(url);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final block = widget.block;
      final colors = Theme.of(context).colorScheme;
      final previewWidth = (constraints.maxWidth * .34).clamp(64.0, 128.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: previewWidth,
            height: 96,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FutureBuilder<Uri?>(
                future: _poster,
                initialData: widget.block.posterUrl,
                builder: (context, snapshot) => snapshot.data == null
                    ? ColoredBox(
                        color: colors.surfaceContainer,
                        child: Center(
                          child:
                              snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.image_outlined, size: 26),
                        ),
                      )
                    : _AutoImage(
                        url: snapshot.data!,
                        label: 'Video thumbnail',
                        imageProvider: _posterProvider,
                        compact: true,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: colors.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: block.url == null ? null : widget.onPlay,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 96),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          block.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          block.url == null
                              ? 'Video unavailable'
                              : 'Tap to play',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: block.url == null
                                ? colors.onSurfaceVariant
                                : colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class ImageGallery extends StatefulWidget {
  const ImageGallery({
    super.key,
    required this.blocks,
    this.imageProvider = networkImageProvider,
  });
  final List<BodyBlock> blocks;
  final ReaderImageProvider imageProvider;
  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<ImageGallery> {
  // Reserve geometry from markup. Decoding must not resize a lazy list child:
  // rebuilding an off-screen row would otherwise repeatedly correct the scroll.
  double _ratio(BodyBlock block) => (block.aspectRatio ?? 1).clamp(.01, 100.0);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width < 280
          ? 1
          : width < 600
          ? 2
          : 3;
      final rows = <List<BodyBlock>>[];
      var row = <BodyBlock>[];
      for (final block in widget.blocks) {
        final ratio = _ratio(block);
        if (ratio > 2 || ratio < .55) {
          if (row.isNotEmpty) rows.add(row);
          rows.add([block]);
          row = [];
        } else {
          row.add(block);
          if (row.length == columns) {
            rows.add(row);
            row = [];
          }
        }
      }
      if (row.isNotEmpty) rows.add(row);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                height:
                    ((width - 6 * (row.length - 1)) /
                            row.fold<double>(
                              0,
                              (sum, block) => sum + _ratio(block),
                            ))
                        .clamp(64.0, row.length == 1 ? 420.0 : 260.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        flex: math.max(1, (_ratio(row[i]) * 1000).round()),
                        child: Semantics(
                          button: true,
                          label:
                              'Open image ${widget.blocks.indexOf(row[i]) + 1}',
                          child: GestureDetector(
                            onTap: () => _open(row[i]),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _AutoImage(
                                key: ValueKey(row[i]),
                                url: row[i].url!,
                                label: row[i].label,
                                imageProvider: widget.imageProvider,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  void _open(BodyBlock block) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Image')),
          body: SafeArea(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: SizedBox.expand(
                child: _AutoImage(
                  url: block.url!,
                  label: block.label,
                  imageProvider: widget.imageProvider,
                  fullSize: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoImage extends StatefulWidget {
  const _AutoImage({
    super.key,
    required this.url,
    required this.label,
    required this.imageProvider,
    this.compact = false,
    this.fullSize = false,
  });
  final Uri url;
  final String label;
  final ReaderImageProvider imageProvider;
  final bool compact;
  final bool fullSize;
  @override
  State<_AutoImage> createState() => _AutoImageState();
}

class _AutoImageState extends State<_AutoImage> {
  ImageProvider? _provider;
  var _attempt = 0;
  var _retrying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AutoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url ||
        widget.imageProvider != oldWidget.imageProvider ||
        widget.fullSize != oldWidget.fullSize) {
      _resolve();
    }
  }

  void _resolve() {
    final provider = ResizeImage(
      widget.imageProvider(widget.url),
      width: widget.fullSize ? 2048 : 1200,
      height: widget.fullSize ? 4096 : 2400,
      policy: ResizeImagePolicy.fit,
    );
    if (_provider == provider) return;
    _provider = provider;
  }

  Future<void> _retry() async {
    if (_retrying) return;
    _retrying = true;
    final provider = _provider;
    await provider?.evict();
    if (!mounted) return;
    setState(() {
      _provider = null;
      _attempt++;
      _retrying = false;
      _resolve();
    });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Image(
      key: ValueKey(_attempt),
      image: _provider!,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      semanticLabel: widget.label,
      frameBuilder: (context, child, frame, synchronous) =>
          frame != null || synchronous
          ? child
          : Center(
              child: MediaQuery.disableAnimationsOf(context)
                  ? const Icon(Icons.image_outlined)
                  : const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
      errorBuilder: (context, error, stack) => Center(
        child: widget.compact
            ? const Icon(Icons.image_not_supported_outlined)
            : TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry image'),
              ),
      ),
    ),
  );
}
