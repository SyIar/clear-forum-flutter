#include "FLImageCodec.h"
#include <webp/encode.h>
#include <webp/decode.h>
#include <webp/mux.h>
#include <zlib.h>
#include <stdlib.h>
#include <string.h>

void FLImageFree(void *bytes) { free(bytes); }
uint32_t FLImageCRC(const uint8_t *bytes, size_t size) {
  return (uint32_t)crc32(0, bytes, (uInt)size);
}
static int validSize(int width, int height) {
  return width > 0 && height > 0 && width <= 16383 && height <= 16383 &&
         (uint64_t)width * height <= 16000000;
}
static int paeth(int a, int b, int c) {
  int p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}
uint8_t *FLPNGDecode(const uint8_t *compressed, size_t size, int width, int height,
                    int colorType, const uint8_t *palette, size_t paletteSize,
                    const uint8_t *transparency, size_t transparencySize) {
  if (!validSize(width, height) || !compressed || size > 80 * 1024 * 1024) return NULL;
  int channels = colorType == 0 || colorType == 3 ? 1 : colorType == 2 ? 3 : colorType == 4 ? 2 : colorType == 6 ? 4 : 0;
  if (!channels || (colorType == 3 && (!palette || paletteSize == 0 || paletteSize > 768 || paletteSize % 3))) return NULL;
  if ((colorType == 0 && transparencySize && transparencySize != 2) ||
      (colorType == 2 && transparencySize && transparencySize != 6) ||
      (colorType == 3 && transparencySize > paletteSize / 3) ||
      ((colorType == 4 || colorType == 6) && transparencySize)) return NULL;
  size_t stride = (size_t)width * channels, length = (stride + 1) * height;
  uint8_t *scanlines = malloc(length), *rgba = NULL;
  if (!scanlines) return NULL;
  z_stream stream = {0};
  stream.next_in = (Bytef *)compressed; stream.avail_in = (uInt)size;
  stream.next_out = scanlines; stream.avail_out = (uInt)length;
  if (inflateInit(&stream) != Z_OK) goto finish;
  int status = inflate(&stream, Z_FINISH);
  int valid = status == Z_STREAM_END && stream.total_out == length && stream.total_in == size;
  inflateEnd(&stream);
  if (!valid) goto finish;
  rgba = malloc((size_t)width * height * 4);
  if (!rgba) goto finish;
  for (int y = 0; y < height; ++y) {
    uint8_t *row = scanlines + (stride + 1) * y + 1;
    uint8_t *prior = y ? row - stride - 1 : NULL;
    int filter = row[-1];
    if (filter > 4) goto invalid;
    for (size_t x = 0; x < stride; ++x) {
      int a = x >= (size_t)channels ? row[x - channels] : 0;
      int b = prior ? prior[x] : 0;
      int c = prior && x >= (size_t)channels ? prior[x - channels] : 0;
      row[x] += filter == 1 ? a : filter == 2 ? b : filter == 3 ? (a + b) / 2 : filter == 4 ? paeth(a, b, c) : 0;
    }
    for (int x = 0; x < width; ++x) {
      uint8_t *p = row + x * channels, *out = rgba + ((size_t)y * width + x) * 4;
      out[3] = 255;
      if (colorType == 3) {
        if ((size_t)p[0] * 3 + 2 >= paletteSize) goto invalid;
        memcpy(out, palette + p[0] * 3, 3);
        if (p[0] < transparencySize) out[3] = transparency[p[0]];
      } else if (colorType == 0 || colorType == 4) {
        out[0] = out[1] = out[2] = p[0];
        if (colorType == 4) out[3] = p[1];
        else if (transparencySize == 2 && transparency[0] == 0 && p[0] == transparency[1]) out[3] = 0;
      } else {
        memcpy(out, p, 3);
        if (colorType == 6) out[3] = p[3];
        else if (transparencySize == 6 && !transparency[0] && !transparency[2] && !transparency[4] &&
                 p[0] == transparency[1] && p[1] == transparency[3] && p[2] == transparency[5]) out[3] = 0;
      }
    }
  }
  goto finish;
invalid:
  free(rgba); rgba = NULL;
finish:
  free(scanlines); return rgba;
}

static int encodingProgress(int percent, const WebPPicture *picture) {
  (void)percent;
  const FLImageContinue *callback = picture->user_data;
  return !callback || !*callback || (*callback)();
}
uint8_t *FLWebPEncode(const uint8_t *rgba, int width, int height,
                     const uint8_t *icc, size_t iccSize, const uint8_t *exif, size_t exifSize,
                     FLImageContinue shouldContinue, size_t *outputSize) {
  *outputSize = 0;
  if (!rgba || !validSize(width, height)) return NULL;
  WebPConfig config;
  WebPPicture picture;
  if (!WebPConfigInit(&config) || !WebPPictureInit(&picture)) return NULL;
  config.lossless = 1; config.exact = 1; config.near_lossless = 100;
  config.quality = 60; config.method = 4; config.thread_level = 0;
  WebPMemoryWriter writer;
  WebPMemoryWriterInit(&writer);
  picture.use_argb = 1; picture.width = width; picture.height = height;
  picture.writer = WebPMemoryWrite; picture.custom_ptr = &writer;
  picture.progress_hook = encodingProgress; picture.user_data = &shouldContinue;
  WebPMux *mux = NULL;
  WebPData assembled = {0};
  uint8_t *output = NULL, *decoded = NULL;
  if (!WebPPictureImportRGBA(&picture, rgba, width * 4) || !WebPEncode(&config, &picture)) goto finish;
  WebPData encoded = {writer.mem, writer.size};
  mux = WebPMuxCreate(&encoded, 1);
  if (!mux) goto finish;
  WebPData profile = {icc, iccSize}, metadata = {exif, exifSize};
  if (iccSize && WebPMuxSetChunk(mux, "ICCP", &profile, 1) != WEBP_MUX_OK) goto finish;
  if (exifSize && WebPMuxSetChunk(mux, "EXIF", &metadata, 1) != WEBP_MUX_OK) goto finish;
  if (WebPMuxAssemble(mux, &assembled) != WEBP_MUX_OK) goto finish;
  int w = 0, h = 0;
  decoded = WebPDecodeRGBA(assembled.bytes, assembled.size, &w, &h);
  if (!decoded || w != width || h != height || memcmp(decoded, rgba, (size_t)width * height * 4)) goto finish;
  output = malloc(assembled.size);
  if (output) { memcpy(output, assembled.bytes, assembled.size); *outputSize = assembled.size; }
finish:
  WebPFree(decoded); WebPDataClear(&assembled); WebPMuxDelete(mux);
  WebPMemoryWriterClear(&writer); WebPPictureFree(&picture);
  return output;
}
