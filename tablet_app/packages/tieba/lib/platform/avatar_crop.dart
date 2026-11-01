import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class PreparedAvatar {
  const PreparedAvatar(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

class AvatarCropRegion {
  const AvatarCropRegion({
    required this.left,
    required this.top,
    required this.size,
  });
  final int left, top, size;

  factory AvatarCropRegion.fromViewport({
    required int imageWidth,
    required int imageHeight,
    required double viewport,
    required double zoom,
    required double offsetX,
    required double offsetY,
  }) {
    if (imageWidth <= 0 ||
        imageHeight <= 0 ||
        viewport <= 0 ||
        !viewport.isFinite ||
        !zoom.isFinite ||
        zoom < 1 ||
        !offsetX.isFinite ||
        !offsetY.isFinite) {
      throw ArgumentError('Invalid avatar crop geometry');
    }
    final scale =
        math.max(viewport / imageWidth, viewport / imageHeight) * zoom;
    final size = (viewport / scale)
        .round()
        .clamp(1, math.min(imageWidth, imageHeight))
        .toInt();
    return AvatarCropRegion(
      left: (-offsetX / scale).round().clamp(0, imageWidth - size).toInt(),
      top: (-offsetY / scale).round().clamp(0, imageHeight - size).toInt(),
      size: size,
    );
  }
}

Future<PreparedAvatar> prepareAvatarImage(Uint8List bytes) =>
    compute(_prepare, bytes);

PreparedAvatar _prepare(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw ArgumentError('Invalid avatar size');
  }
  if (bytes.length < 16) {
    throw const FormatException('Unsupported avatar image');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null ||
      info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 40000000) {
    throw const FormatException('Unsupported avatar image');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) throw const FormatException('Avatar decoding failed');
  var oriented = img.bakeOrientation(decoded);
  if (math.max(oriented.width, oriented.height) > 2048) {
    oriented = oriented.width >= oriented.height
        ? img.copyResize(oriented, width: 2048)
        : img.copyResize(oriented, height: 2048);
  }
  final background = img.Image(
    width: oriented.width,
    height: oriented.height,
    numChannels: 3,
  );
  img.fill(background, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(background, oriented);
  return PreparedAvatar(
    img.encodeJpg(background, quality: 96),
    background.width,
    background.height,
  );
}

Future<Uint8List> cropAvatarJpeg(
  PreparedAvatar image,
  AvatarCropRegion region,
) => compute(_crop, (image, region));

Uint8List _crop((PreparedAvatar, AvatarCropRegion) request) {
  final (source, region) = request;
  final decoded = img.decodeJpg(source.bytes);
  if (decoded == null ||
      region.left < 0 ||
      region.top < 0 ||
      region.size < 1 ||
      region.left + region.size > decoded.width ||
      region.top + region.size > decoded.height) {
    throw ArgumentError('Avatar crop is outside the image');
  }
  final cropped = img.copyCrop(
    decoded,
    x: region.left,
    y: region.top,
    width: region.size,
    height: region.size,
  );
  return img.encodeJpg(
    img.copyResize(
      cropped,
      width: 512,
      height: 512,
      interpolation: img.Interpolation.cubic,
    ),
    quality: 92,
  );
}
