#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const FLZipErrorDomain;

@interface FLZipEntry : NSObject
@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly) uint64_t size;
@property(nonatomic, readonly) BOOL directory;
@property(nonatomic, readonly) BOOL encrypted;
@property(nonatomic, readonly) BOOL unsafe;
@property(nonatomic, readonly, nullable) NSDate *modified;
@end

/// Single-worker streaming reader. No passwords are retained after openEntry.
@interface FLZipReader : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;
- (BOOL)rewindWithError:(NSError **)error NS_SWIFT_NAME(rewind());
/// A nil entry with no error denotes the end of the directory.
- (FLZipEntry * _Nullable_result)nextEntryWithError:(NSError **)error NS_SWIFT_NAME(nextEntry());
- (BOOL)openEntryWithPassword:(nullable NSString *)password error:(NSError **)error NS_SWIFT_NAME(openEntry(password:));
- (nullable NSData *)readChunkWithError:(NSError **)error NS_SWIFT_NAME(readChunk());
- (BOOL)finishEntryWithError:(NSError **)error NS_SWIFT_NAME(finishEntry());
@end
NS_ASSUME_NONNULL_END
