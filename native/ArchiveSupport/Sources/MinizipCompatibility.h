// Declarations from the minizip-ng C headers shipped with ZipArchive 2.6.0.
// That package exports these symbols but only exposes SSZipCommon.h to SwiftPM.
// Keep the dependency pinned; see README.md and the bundled minizip license.
#if __has_include(<ZipArchive/ZipArchive.h>)
#import <ZipArchive/ZipArchive.h>
#else
#import <ZipArchive.h>
#endif

extern void *unzOpen(const char *path);
extern int unzClose(void *file);
extern int unzGoToFirstFile(void *file);
extern int unzGoToNextFile(void *file);
extern int unzGetCurrentFileInfo64(void *file, unz_file_info64 *info, char *filename,
  unsigned long filenameSize, void *extra, unsigned long extraSize, char *comment, unsigned long commentSize);
extern int unzOpenCurrentFilePassword(void *file, const char *password);
extern int unzReadCurrentFile(void *file, void *buffer, uint32_t length);
extern int unzCloseCurrentFile(void *file);
extern void *unzGetHandle_MZ(void *file);
extern int32_t mz_zip_entry_get_compress_stream(void *handle, void **stream);
extern int32_t mz_stream_close(void *stream);

// Public mz_stream layout from mz_strm.h, not the private ZIP handle layout.
typedef struct FLMinizipStream {
  void *vtable;
  struct FLMinizipStream *base;
} FLMinizipStream;
