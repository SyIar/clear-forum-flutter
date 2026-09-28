import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';

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

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.block,
    this.onPlay,
    this.imageProvider = networkImageProvider,
  });
  final BodyBlock block;
  final VoidCallback? onPlay;
  final ReaderImageProvider imageProvider;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
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
              child: block.posterUrl == null
                  ? ColoredBox(
                      color: colors.surfaceContainer,
                      child: const Center(
                        child: Icon(Icons.image_outlined, size: 26),
                      ),
                    )
                  : _AutoImage(
                      url: block.posterUrl!,
                      label: 'Video thumbnail',
                      imageProvider: imageProvider,
                      compact: true,
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
                onTap: block.url == null ? null : onPlay,
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
  final Map<Uri, double> _ratios = {};
  double _ratio(BodyBlock block) =>
      (_ratios[block.url] ?? block.aspectRatio ?? 1).clamp(.01, 100.0);

  @override
  void didUpdateWidget(covariant ImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.blocks.map((block) => block.url).toSet();
    _ratios.removeWhere((url, _) => !current.contains(url));
  }

  void _resolved(BodyBlock block, double ratio) {
    final normalized = ratio.clamp(.01, 100.0);
    if (!mounted ||
        _ratio(block) == normalized ||
        !widget.blocks.contains(block)) {
      return;
    }
    setState(() => _ratios[block.url!] = normalized);
  }

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
                                onRatio: (ratio) => _resolved(row[i], ratio),
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
    this.onRatio,
    this.compact = false,
    this.fullSize = false,
  });
  final Uri url;
  final String label;
  final ReaderImageProvider imageProvider;
  final ValueChanged<double>? onRatio;
  final bool compact;
  final bool fullSize;
  @override
  State<_AutoImage> createState() => _AutoImageState();
}

class _AutoImageState extends State<_AutoImage> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
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

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    final provider = ResizeImage(
      widget.imageProvider(widget.url),
      width: widget.fullSize ? 2048 : 1200,
      height: widget.fullSize ? 4096 : 2400,
      policy: ResizeImagePolicy.fit,
    );
    if (_provider == provider) return;
    _detach();
    _provider = provider;
    if (widget.onRatio == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      final ratio = info.image.width / info.image.height;
      info.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_stream, stream)) {
          widget.onRatio?.call(ratio);
          _detach();
        }
      });
    }, onError: (Object error, StackTrace? stack) {});
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
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
