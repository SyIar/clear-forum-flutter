import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'downloads.dart';
import 'strings.dart';

bool isImage(String path) => RegExp(
  r'\.(png|jpe?g|gif|webp|avif|heic)(?:\?|$)',
  caseSensitive: false,
).hasMatch(path);
bool isVideo(String path) => RegExp(
  r'\.(mp4|m4v|mov|mkv|webm|m3u8)(?:\?|$)',
  caseSensitive: false,
).hasMatch(path);

/// A gallery may still hold the PNG path when background conversion finishes.
Widget _convertedImageFallback(String original) => FutureBuilder<String>(
  future: DownloadManager.instance.resolvedPath(original),
  builder: (context, snapshot) {
    final resolved = snapshot.data;
    if (resolved != null && resolved != original) {
      return Image.file(
        File(resolved),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image_outlined, color: Colors.white),
      );
    }
    return const Icon(Icons.broken_image_outlined, color: Colors.white);
  },
);

class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.headers = const {},
  });
  final List<String> items;
  final int initialIndex;
  final Map<String, String> headers;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _chrome = false;
  double _drag = 0;
  @override
  void dispose() {
    _pages.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      onTap: () => setState(() => _chrome = !_chrome),
      onVerticalDragStart: (_) => _drag = 0,
      onVerticalDragUpdate: (details) => _drag += details.delta.dy,
      onVerticalDragEnd: (details) {
        if (_drag > 100 && (details.primaryVelocity ?? 0) >= 0) {
          Navigator.maybePop(context);
        }
      },
      child: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final path = widget.items[i];
              if (isVideo(path)) {
                return i == _index
                    ? VideoSurface(
                        key: ValueKey(path),
                        path: path,
                        headers: widget.headers,
                      )
                    : const SizedBox();
              }
              return Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: path.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: path,
                          httpHeaders: widget.headers,
                          fit: BoxFit.contain,
                          errorWidget: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white,
                          ),
                        )
                      : Image.file(
                          File(path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              _convertedImageFallback(path),
                        ),
                ),
              );
            },
          ),
          if (_chrome)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: tr('Close'),
                      ),
                      Expanded(
                        child: Text(
                          '${_index + 1} / ${widget.items.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (widget.items[_index].startsWith('http'))
                        IconButton(
                          tooltip: tr('Download'),
                          onPressed: () async {
                            await DownloadManager.instance.resolve(
                              Uri.parse(widget.items[_index]),
                            );
                          },
                          icon: const Icon(
                            Icons.download_outlined,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class VideoSurface extends StatefulWidget {
  const VideoSurface({super.key, required this.path, this.headers = const {}});
  final String path;
  final Map<String, String> headers;
  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  late final VideoPlayerController _controller = widget.path.startsWith('http')
      ? VideoPlayerController.networkUrl(
          Uri.parse(widget.path),
          httpHeaders: widget.headers,
        )
      : VideoPlayerController.file(File(widget.path));
  Timer? _hide;
  bool _controls = true, _full = false;
  String? _error;
  double? _seek;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      await _controller.play();
      _schedule();
    } catch (_) {
      if (mounted) setState(() => _error = tr('Page unavailable'));
    }
  }

  void _update() {
    if (mounted) setState(() {});
  }

  void _schedule() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _controls = false);
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _controller.removeListener(_update);
    _controller.dispose();
    super.dispose();
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _controls = !_controls);
        _schedule();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (value.isInitialized)
            AspectRatio(
              aspectRatio: value.aspectRatio,
              child: VideoPlayer(_controller),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.white))
          else
            const CircularProgressIndicator(),
          if (_controls && value.isInitialized) ...[
            IconButton.filled(
              onPressed: () {
                value.isPlaying ? _controller.pause() : _controller.play();
                _schedule();
              },
              iconSize: 36,
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: tr('Play'),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Text(
                          _time(value.position),
                          style: const TextStyle(color: Colors.white),
                        ),
                        Expanded(
                          child: Slider(
                            value:
                                (_seek ??
                                        value.position.inMilliseconds
                                            .toDouble())
                                    .clamp(
                                      0,
                                      value.duration.inMilliseconds.toDouble(),
                                    ),
                            max: value.duration.inMilliseconds.toDouble().clamp(
                              1,
                              double.infinity,
                            ),
                            onChangeStart: (v) {
                              _hide?.cancel();
                              _seek = v;
                            },
                            onChanged: (v) => setState(() => _seek = v),
                            onChangeEnd: (v) async {
                              await _controller.seekTo(
                                Duration(milliseconds: v.round()),
                              );
                              if (mounted) setState(() => _seek = null);
                              _schedule();
                            },
                          ),
                        ),
                        Text(
                          _time(value.duration),
                          style: const TextStyle(color: Colors.white),
                        ),
                        IconButton(
                          tooltip: tr(
                            _full ? 'Exit full screen' : 'Full screen',
                          ),
                          onPressed: () {
                            setState(() => _full = !_full);
                            SystemChrome.setEnabledSystemUIMode(
                              _full
                                  ? SystemUiMode.immersiveSticky
                                  : SystemUiMode.edgeToEdge,
                            );
                          },
                          icon: Icon(
                            _full ? Icons.fullscreen_exit : Icons.fullscreen,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
