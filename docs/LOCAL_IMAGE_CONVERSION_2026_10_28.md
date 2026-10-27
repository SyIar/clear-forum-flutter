# Local images: lossless conversion and arrival order

## User behavior

- Local Files has a native image conversion toolbar button. It queues the current folder and all descendants, and opens progress. The Documents root covers the entire library.
- Completed PNG downloads from both file-host download queues are automatically queued. ZIP extraction queues its completed output folder. No unfinished transfer is transformed.
- One utility worker processes one image at a time. Closing the progress sheet keeps work running. Moving the app to the background pauses the worker; returning resumes persisted requests. This is not an unrestricted iOS background execution entitlement.
- Cancel clears pending requests and cancels the current worker before original removal. Files already converted remain converted.
- Browser and gallery snapshots use descending ingestion date, then natural filename for ties. New completed downloads and extracted files get an explicit arrival attribute. Historical/imported files without that attribute fall back to filesystem creation date; past ingestion times cannot be reconstructed exactly. Content modification dates are not used for ordering. Conversion preserves arrival date.

## Format decision and limits

Use lossless WebP (`lossless=1`, `exact=1`, `near_lossless=100`). JPEG's normal encoding is lossy. HEIC quality 1 is not a guarantee of mathematical losslessness. JPEG XL also has a lossless mode, but adding another encoder is unnecessary for this bounded PNG feature.

- [Google WebP FAQ](https://developers.google.com/speed/webp/faq): lossless WebP and alpha support, including Safari/iOS support. Reported average savings are not guarantees for any image.
- [cwebp documentation](https://developers.google.com/speed/webp/docs/cwebp): exact mode is necessary to retain RGB beneath fully transparent alpha. Near-lossless preprocessing must not be enabled.
- [WebP container](https://developers.google.com/speed/webp/docs/riff_container): ICC and EXIF containers.
- [libwebp Swift package wrapper](https://github.com/SDWebImage/libwebp-Xcode/tree/1.6.0): pinned 1.6.0 encoder/decoder/mux, without any UI framework. Upstream BSD license is included in ThirdPartyNotices.txt.

The first implementation supports static, noninterlaced 8-bit PNG, at most 16 million pixels, 16,383 per dimension and 80 MiB input. Palette and gray pixels are expanded exactly; incompatible color profiles are skipped. Raw PNG scanlines are decoded without alpha premultiplication, resizing or color conversion. ImageIO supplies the interpreted RGB ICC profile. EXIF is retained. APNG, 16-bit images, interlaced PNG, and unhandled ancillary chunks (including text, XMP and physical-resolution metadata) stay as PNG. These skips deliberately protect source information. JPEG, existing WebP and other formats are untouched.

The encoded WebP is decoded with libwebp and compared byte-for-byte against RGBA, including invisible RGB. ImageIO must also accept it. Only strictly smaller files are published. A colliding WebP is never overwritten. A tagged, verified duplicate from interrupted publication can be completed on retry.

## Persistence and path compatibility

- Request roots are stored in Application Support/FileDownloadState/lossless-image-conversion.json. Restarting rescans the remaining roots; no directory-sized pixel buffer is kept.
- New bytes are staged in the app temporary directory, synchronized and verified. Original content is rechecked before publication and removal. Failed encodes/writes/cancellation preserve the original. A process exit between publication and removal may temporarily leave both copies.
- Extended attributes store arrival time and original name/hash/size plus output hash. They are not separate visible files.
- Old download queue and gallery paths resolve to the converted sibling only when the origin attribute matches. Download receipts validate converted content before recovery. Existing source files always take precedence. Live download views are invalidated after conversion so preview/export/share use the new path.
- App deletion refuses paths overlapping an active conversion request. Symbolic links and paths outside Documents are rejected by the existing catalog.

## Text configuration

No Chinese runtime strings or encoded Chinese literals were added. Existing translated controls reuse their established keys. New conversion-specific labels have English defaults because this repository has no LEO client or configuration endpoint. Do not add hardcoded Chinese translations to work around the user's LEO requirement. A future LEO integration must supply the translated labels before enabling Chinese text for this feature.

## Validation

macOS CI compiles the actual codec and runs tests for all five PNG filters, transparent pixel round-trip, decoder support, smaller-only replacement, arrival preservation, recursive discovery, collisions, corrupt data, unsupported metadata/bit depth/animation, and interrupted-publication recovery. Windows checks validate Swift syntax, repository policy, localization references and native UI constraints; these are not an iOS build. Device validation should include WebP thumbnails/gallery, manual cancellation, relaunch, ZIP output, and both file-host preview/export routes.
