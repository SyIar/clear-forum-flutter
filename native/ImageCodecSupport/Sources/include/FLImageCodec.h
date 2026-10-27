#pragma once
#include <stddef.h>
#include <stdint.h>

// Bounded, non-interlaced, 8-bit PNG scanlines, without color conversion or premultiplication.
uint8_t *FLPNGDecode(const uint8_t *compressed, size_t size, int width, int height,
                    int colorType, const uint8_t *palette, size_t paletteSize,
                    const uint8_t *transparency, size_t transparencySize);
uint32_t FLImageCRC(const uint8_t *bytes, size_t size);
// Returns a verified exact RGBA lossless WebP. Free both functions' results with FLImageFree.
uint8_t *FLWebPEncode(const uint8_t *rgba, int width, int height,
                     const uint8_t *icc, size_t iccSize, const uint8_t *exif, size_t exifSize,
                     size_t *outputSize);
void FLImageFree(void *bytes);
