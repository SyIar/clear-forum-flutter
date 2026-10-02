# Local file tools

## ZIP extraction

ZIP entries in Local files and completed-download previews open an archive action page. Extract ZIP expands the archive into a sibling folder and opens the completed folder in the existing browser. The source ZIP is preserved. Existing destination names receive a numeric suffix, and no existing folder or file is overwritten.

Extraction uses pinned [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/tree/0.9.20) with 256 KiB chunks on a worker task. A shared manager keeps one extraction running across view dismissal, shows byte progress, and supports cancellation. An iOS background-time expiration cancels safely; this is not a persistent background extraction queue. Unsupported or encrypted archives can still be exported with Save to Files or Share.

The extractor validates all entry paths, rejects symlinks, checks complete ZIP/ZIP64 enumeration, verifies CRC and expanded sizes, and publishes only a fully extracted staging folder. The limits are 50,000 entries, 128 GiB of expanded data, and available disk space with a 64 MiB reserve. Cancelled or failed operations remove staging data and retain the original ZIP. An abrupt process termination can leave system temporary data for iOS to purge; unfinished extractions do not automatically restart.

The MIT license is bundled as `ZIPFoundation-LICENSE.md`. The library's documented entry streaming/progress APIs are used; password support is not claimed.

## Storage analysis and deletion

The chart icon on every Local files toolbar opens analysis for that folder. Analysis enumerates regular files recursively, including hidden files, without reading payloads. It displays total logical file size and lists individual files largest-first, showing relative paths. This measures local Documents files, not app caches, Photos, APFS allocation, or the total installed app size. Symbolic links and unavailable entries are skipped and reported.

Files can be deleted from analysis or the ordinary long-press menu; folders can be deleted from the ordinary long-press menu. A confirmation names the item and states that deletion is permanent. Deletion revalidates the selected path, type, size, and modification date, rejects the Documents root and symbolic-link traversal, and refreshes both the folder and storage analysis after success. A folder's nested symlinks are removed as links; their targets are never traversed. Items overlapping unfinished download directories or active archive sources must first have the related work stopped.

## Validation

Synthetic Swift tests cover nested/Unicode ZIP paths, ZIP64, cancellation, CRC corruption, encrypted-entry truncation, extraction limits, collisions, recursive sizes, stable size sorting, scoped deletion, changed files, and symlink isolation. Device acceptance still needs a real ZIP, a large extraction, closing/reopening its view, opening extracted media, and confirming/cancelling file and folder removal.
