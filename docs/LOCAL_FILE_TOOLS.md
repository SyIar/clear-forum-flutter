# Local file tools

## ZIP extraction

ZIP entries in Local files and completed-download previews open an archive action page. Extract ZIP expands the archive into a sibling folder and opens the completed folder in the existing browser. The source ZIP is preserved. Existing destination names receive a numeric suffix, and no existing folder or file is overwritten.

Extraction uses pinned [ZipArchive 2.6.0](https://github.com/ZipArchive/ZipArchive/tree/2.6.0) through the ArchiveSupport streaming bridge with 256 KiB chunks on a worker task. Traditional password ZIPs and WinZip AES ZIPs prompt for a password on the extraction page. Incorrect passwords can be retried, and the original archive remains intact. Passwords are neither logged nor saved; the input is cleared on submission and view dismissal. A shared manager keeps one extraction running across view dismissal, shows byte progress, and supports cancellation. An iOS background-time expiration cancels safely; this is not a persistent background extraction queue. Unsupported archives retain Save to Files and Share actions.

The extractor validates all entry paths, rejects symlinks, checks complete ZIP/ZIP64 enumeration, verifies CRC and expanded sizes, and publishes only a fully extracted staging folder. The limits are 50,000 entries, 128 GiB of expanded data, and available disk space with a 64 MiB reserve. Cancelled or failed operations remove staging data and retain the original ZIP. An abrupt process termination can leave system temporary data for iOS to purge; unfinished extractions do not automatically restart.

ZipArchive's MIT license and minizip's zlib license are bundled. See `native/ArchiveSupport/README.md` for the pinned streaming interface and explicit AES authentication validation. Multi-volume archives, RAR/7z, PKWARE strong encryption, and different passwords per entry are outside the supported workflow. ZIPFoundation remains test-only.

## Compact folder paths

The file browser combines a chain of single child directories into one row such as `Downloads / Archive / Pictures`. One tap opens the deepest directory, and Back returns to the previous visible list. Compaction stops at any files (including hidden files), multiple children, an empty folder, an inaccessible item, or a symbolic link. Work runs off the UI thread and is bounded to 64 directory hops per row. Searching matches the combined path. Long-press deletion still names and removes the outer folder represented by the row; path compaction never moves files or changes storage analysis.

## Storage analysis and deletion

The chart icon on every Local files toolbar opens analysis for that folder. Analysis enumerates regular files recursively, including hidden files, without reading payloads. It displays total logical file size and lists individual files largest-first, showing relative paths. This measures local Documents files, not app caches, Photos, APFS allocation, or the total installed app size. Symbolic links and unavailable entries are skipped and reported.

Files can be deleted from analysis or the ordinary long-press menu; folders can be deleted from the ordinary long-press menu. A confirmation names the item and states that deletion is permanent. Deletion revalidates the selected path, type, size, and modification date, rejects the Documents root and symbolic-link traversal, and refreshes both the folder and storage analysis after success. A folder's nested symlinks are removed as links; their targets are never traversed. Items overlapping unfinished download directories or active archive sources must first have the related work stopped.

## Validation

Synthetic Swift tests cover nested/Unicode ZIP paths, ZIP64, cancellation, CRC corruption, encrypted-entry truncation, traditional/AES password requests and retries, empty entries, damaged authentication trailers, extraction limits, collisions, recursive sizes, stable size sorting, scoped deletion, changed files, folder compaction boundaries, and symlink isolation. Device acceptance still needs real encrypted ZIPs, a large extraction, closing/reopening its view, opening extracted media, and confirming/cancelling file and folder removal.
