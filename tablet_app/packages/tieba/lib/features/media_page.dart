import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../platform/media_actions.dart';
import '../widgets/common.dart';

Future<void> shareLink(
  BuildContext context,
  String url, {
  String? title,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: url,
      title: title,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });
  final List<String> images;
  final int initialIndex;
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _controller;
  late int _index;
  bool _sharing = false;
  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    try {
      final url = widget.images[_index];
      final response = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw StateError('Empty image response');
      }
      if (!mounted) return;
      final mime =
          response.headers.value('content-type')?.split(';').first ??
          'image/jpeg';
      final extension = mime.contains('png')
          ? 'png'
          : mime.contains('gif')
          ? 'gif'
          : mime.contains('webp')
          ? 'webp'
          : 'jpg';
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(data),
              mimeType: mime,
              name: 'tieba-image.$extension',
            ),
          ],
          fileNameOverrides: ['tieba-image.$extension'],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) notifyUser(context, error.toString());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _saveImage() async {
    setState(() => _sharing = true);
    try {
      await MediaActions.saveImage(widget.images[_index]);
      if (mounted) notifyUser(context, context.l10n.imageSaved);
    } catch (error) {
      if (mounted) notifyUser(context, error.toString());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: GlassAppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${_index + 1} / ${widget.images.length}'),
      actions: [
        if (MediaActions.canSaveToPhotos)
          IconButton(
            onPressed: _sharing ? null : _saveImage,
            icon: const Icon(Icons.download_rounded),
            tooltip: context.l10n.saveImage,
          ),
        IconButton(
          onPressed: _sharing ? null : _shareImage,
          tooltip: context.l10n.share,
          icon: _sharing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share_rounded),
        ),
      ],
    ),
    body: PageView.builder(
      controller: _controller,
      itemCount: widget.images.length,
      onPageChanged: (index) => setState(() => _index = index),
      itemBuilder: (context, index) => InteractiveViewer(
        minScale: .8,
        maxScale: 5,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.images[index],
            fit: BoxFit.contain,
            placeholder: (_, _) => const CircularProgressIndicator.adaptive(),
            errorWidget: (_, _, error) =>
                ErrorPanel(error: error, onRetry: () => setState(() {})),
          ),
        ),
      ),
    ),
  );
}

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.url});
  final String url;
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController _controller;
  late Future<void> _ready;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ready = _controller.initialize();
    _controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: GlassAppBar(
      title: Text(context.l10n.video),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          onPressed: () => shareLink(context, widget.url),
          icon: const Icon(Icons.ios_share),
        ),
      ],
    ),
    body: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorPanel(
            error: snapshot.error!,
            onRetry: () => setState(() => _ready = _controller.initialize()),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
            VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              padding: const EdgeInsets.all(20),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  onPressed: () => _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play(),
                  iconSize: 40,
                  tooltip: _controller.value.isPlaying
                      ? context.l10n.pause
                      : context.l10n.play,
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${_duration(_controller.value.position)} / ${_duration(_controller.value.duration)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

String _duration(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class AudioBubble extends StatefulWidget {
  const AudioBubble({super.key, required this.url, this.label = ''});
  final String url, label;
  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _loaded = false, _busy = false;
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_player.playing) {
      await _player.pause();
      return;
    }
    setState(() => _busy = true);
    try {
      if (!_loaded) {
        await _player.setUrl(widget.url);
        _loaded = true;
      }
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      _player.play().catchError((Object error) {
        if (mounted) notifyUser(context, error.toString());
      });
    } catch (error) {
      if (mounted) notifyUser(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
    stream: _player.playerStateStream,
    builder: (context, snapshot) => FilledButton.tonalIcon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(
        snapshot.data?.playing == true
            ? Icons.pause_rounded
            : Icons.graphic_eq_rounded,
      ),
      label: Text(widget.label.isEmpty ? context.l10n.audio : widget.label),
    ),
  );
}
