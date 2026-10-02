#import "ArchiveSupport.h"
#import "MinizipCompatibility.h"
#import <CoreFoundation/CoreFoundation.h>
#import <zlib.h>

NSString *const FLZipErrorDomain = @"ForumLite.Zip";
static BOOL Fail(NSError **error, NSInteger code) {
  if (error) *error = [NSError errorWithDomain:FLZipErrorDomain code:code userInfo:nil];
  return NO;
}

@interface FLZipEntry ()
@property(nonatomic, readwrite) NSString *path;
@property(nonatomic, readwrite) uint64_t size;
@property(nonatomic, readwrite) BOOL directory;
@property(nonatomic, readwrite) BOOL encrypted;
@property(nonatomic, readwrite) BOOL unsafe;
@property(nonatomic, readwrite) NSDate *modified;
@end
@implementation FLZipEntry
@end

@implementation FLZipReader {
  void *_archive;
  BOOL _first;
  BOOL _opened;
  BOOL _encrypted;
  uint16_t _aesVersion;
  uint32_t _expectedCRC;
  uint32_t _crc;
  uint64_t _size;
  uint64_t _read;
}
- (instancetype)initWithPath:(NSString *)path error:(NSError **)error {
  self = [super init];
  if (self) {
    _archive = unzOpen(path.fileSystemRepresentation);
    if (!_archive) { Fail(error, -103); return nil; }
    _first = YES;
  }
  return self;
}
- (void)dealloc {
  if (_opened) unzCloseCurrentFile(_archive);
  if (_archive) unzClose(_archive);
}
- (BOOL)rewindWithError:(NSError **)error {
  if (_opened) return Fail(error, -103);
  _first = YES;
  return YES;
}
- (FLZipEntry *)nextEntryWithError:(NSError **)error {
  if (_opened) { Fail(error, -103); return nil; }
  int status = _first ? unzGoToFirstFile(_archive) : unzGoToNextFile(_archive);
  _first = NO;
  if (status == -100) return nil;
  if (status != 0) { Fail(error, status); return nil; }
  unz_file_info64 info = {0};
  if (unzGetCurrentFileInfo64(_archive, &info, NULL, 0, NULL, 0, NULL, 0) != 0 ||
      info.size_filename == 0 || info.size_filename > 4096 || info.disk_num_start != 0) {
    Fail(error, -103); return nil;
  }
  NSMutableData *name = [NSMutableData dataWithLength:info.size_filename];
  NSMutableData *extra = [NSMutableData dataWithLength:info.size_file_extra];
  if (unzGetCurrentFileInfo64(_archive, &info, name.mutableBytes, name.length,
      extra.mutableBytes, extra.length, NULL, 0) != 0 || memchr(name.bytes, 0, name.length)) {
    Fail(error, -103); return nil;
  }
  NSString *path = [[NSString alloc] initWithData:name encoding:NSUTF8StringEncoding];
  if (!path && !(info.flag & (1 << 11))) {
    path = [[NSString alloc] initWithData:name encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSLatinUS)];
  }
  if (!path) { Fail(error, -103); return nil; }
  _aesVersion = 0;
  const uint8_t *bytes = extra.bytes;
  for (NSUInteger pos = 0; pos < extra.length;) {
    if (extra.length - pos < 4) { Fail(error, -103); return nil; }
    uint16_t kind = bytes[pos] | (bytes[pos + 1] << 8);
    uint16_t count = bytes[pos + 2] | (bytes[pos + 3] << 8);
    pos += 4;
    if (count > extra.length - pos) { Fail(error, -103); return nil; }
    if (kind == 0x9901) {
      if (count != 7 || bytes[pos + 2] != 'A' || bytes[pos + 3] != 'E' ||
          bytes[pos + 4] < 1 || bytes[pos + 4] > 3) { Fail(error, -103); return nil; }
      _aesVersion = bytes[pos] | (bytes[pos + 1] << 8);
      if (_aesVersion != 1 && _aesVersion != 2) { Fail(error, -109); return nil; }
    }
    pos += count;
  }
  _encrypted = (info.flag & 1) != 0;
  if ((info.flag & (1 << 6)) || (_aesVersion && !_encrypted)) { Fail(error, -109); return nil; }
  _expectedCRC = info.crc;
  _size = info.uncompressed_size;
  FLZipEntry *entry = [FLZipEntry new];
  entry.path = path; entry.size = _size; entry.encrypted = _encrypted;
  uint32_t type = (info.external_fa >> 16) & 0170000;
  entry.directory = [path hasSuffix:@"/"] || type == 0040000 || (info.external_fa & 0x10) != 0;
  entry.unsafe = type != 0 && type != 0100000 && type != 0040000;
  NSDateComponents *date = [NSDateComponents new];
  date.year = ((info.dos_date >> 25) & 127) + 1980; date.month = (info.dos_date >> 21) & 15;
  date.day = (info.dos_date >> 16) & 31; date.hour = (info.dos_date >> 11) & 31;
  date.minute = (info.dos_date >> 5) & 63; date.second = (info.dos_date & 31) * 2;
  entry.modified = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateFromComponents:date];
  return entry;
}
- (BOOL)openEntryWithPassword:(NSString *)password error:(NSError **)error {
  if (_opened) return Fail(error, -103);
  if (_encrypted && !password) return Fail(error, -108);
  if (password && [password rangeOfString:@"\0"].location != NSNotFound) return Fail(error, -108);
  int status = unzOpenCurrentFilePassword(_archive, _encrypted ? password.UTF8String : NULL);
  if (status != 0) return Fail(error, status);
  _opened = YES; _crc = 0; _read = 0;
  return YES;
}
- (NSData *)readChunkWithError:(NSError **)error {
  if (!_opened) { Fail(error, -103); return nil; }
  NSMutableData *chunk = [NSMutableData dataWithLength:256 * 1024];
  int count = unzReadCurrentFile(_archive, chunk.mutableBytes, (uint32_t)chunk.length);
  if (count < 0) { Fail(error, count); return nil; }
  if ((uint64_t)count > _size - _read) { Fail(error, -103); return nil; }
  _read += count;
  _crc = (uint32_t)crc32(_crc, chunk.bytes, (uInt)count);
  chunk.length = count;
  return chunk;
}
- (BOOL)finishEntryWithError:(NSError **)error {
  if (!_opened) return Fail(error, -103);
  int status = 0;
  if (_read != _size || (_aesVersion != 2 && _crc != _expectedCRC)) status = -105;
  // minizip's compat close does not close its AES stream. Explicitly verify its
  // authentication trailer before unzCloseCurrentFile destroys that stream.
  if (status == 0 && _aesVersion) {
    void *stream = NULL;
    if (mz_zip_entry_get_compress_stream(unzGetHandle_MZ(_archive), &stream) != 0 ||
        !stream || !((FLMinizipStream *)stream)->base) status = -103;
    else status = mz_stream_close(((FLMinizipStream *)stream)->base);
  }
  int closeStatus = unzCloseCurrentFile(_archive);
  _opened = NO;
  if (status == 0) status = closeStatus;
  return status == 0 ? YES : Fail(error, status);
}
@end
