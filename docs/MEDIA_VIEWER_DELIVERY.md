# Native media viewer update

Date: 2026-09-29. Build 1018 compiled and packaged successfully. Physical-device acceptance remains with the user.

## Revised user request

- Use system horizontal return navigation for image/video pages.
- Add a native Liquid Glass video group at bottom right: download, then full screen.
- Restore Details for playback/download troubleshooting.
- Do not add an image download button. Use a magnifying-glass button to load and inspect the source image without the app's 2048 px preview downsampling.

## Implementation

MediaViewerDestination is now a destination in the reader's existing NavigationStack, using the system back button and interactive push/pop. The independent one-root modal navigation controller, custom edge-pan thresholds, and custom slide animator were removed. Image panning at minimum zoom yields to navigation; zoomed panning remains available and gives system edge return priority. System gesture delegates are not replaced. The reader model remains mounted and retains the existing page/image caching rules. Canceled returns do not dismantle the media controller or stop playback.

The image inspector starts with the existing preview. The bottom-right magnifier downloads the image source to a temporary file and opens it without re-encoding or a 2048 px thumbnail operation. Loading/progress, actual source dimensions, retry, pinch and double-tap zoom are available. Explicit original-image attributes or direct enclosing image links are retained by both forum parsers; otherwise the available image URL is used. A source that is itself a thumbnail cannot be promoted to an original upload by the app. Original here means the available source file without additional app compression, not recovery of compression already applied by the website. The inspector uses UIImage display, so animated formats are not promised full animation support. A 100 MiB file cap and 80-megapixel decode guard bound memory exposure; oversized sources report a limit instead of silently downsampling. Temporary originals are removed when the inspector is released.

The native player now lives in native/App/MediaPlayerController.swift. The legacy Flutter player source remains frozen in ios/Runner; the native project no longer compiles that copy. Turbo/media policy and probe remain shared.

The video group is one UIGlassEffect surface containing separate download and full-screen controls, above AVKit's transport region. Downloads show progress, allow cancellation before the Photos import, and show completed/failed states. Download work is retained independently of its viewer, supports at most two active transfers, and reconnects a reopened viewer to the active job for that source. These are foreground URLSession tasks: returning to another app page does not cancel them, but uninterrupted background/force-quit downloading is not promised.

Photos permission is requested only after a download tap, using addOnly. Turbo obtains a fresh signed candidate through a separate TurboResolver without restarting playback. Other sources use the successfully initialized AVKit candidate and matching provider cookies. Shared/forum cookie storage is not used. Redirects rebuild applicable cookies, and non-HTTPS/invalid destinations are rejected. Files stream to disk with a 4 GiB cap. HTTP errors, partial responses, empty files, HTML/JSON and identified HLS playlists cannot be reported as a saved video. Local video tracks are checked before importing the file into Photos. Only a successful Photos completion displays Saved to Photos. Unsupported imports can export the downloaded file to Files.

HLS offline packaging/conversion and web-only players without an available HTTPS media candidate remain unsupported for Photos downloads. Their working playback paths are preserved. Details includes whether a source is available, resolver/download stages, bounded HTTP/MIME/byte/error metadata, and Photos results. Copy is an explicit local-only action with five-minute pasteboard expiry; URLs, cookies and page content are omitted.

## Validation and device checks

Local checks: Swift syntax parsing, repository policy, media probe regression checks and diff whitespace checks. These are not Xcode compilation. Core tests add response validation, HLS recognition, explicit original-image selection, and source/preview separation in both forum parsers. The existing macOS/device-build workflow remains the compilation gate; no simulator is used.

Device acceptance:

1. Open image/video from a scrolled thread. Try slow, short, diagonal, canceled and repeated returns. Confirm native follow-through and unchanged thread position/images.
2. Pinch and pan an enlarged image, then edge-return. Tap the magnifier, confirm loading and source dimensions, zoom into details, and return while loading or decoding.
3. Test video scrubbing, native playback, web fallback, portrait/landscape and the app's immersive toggle. Check the group does not cover the scrubber. Test the system player's own full-screen transition separately.
4. Download a compatible complete video, grant add-only permission and verify playback of the saved asset in Photos. Test denial, cancellation, leaving/reopening the viewer, a stale Turbo source and unsupported HLS/web-only sources.
5. If downloading fails, open Details and use Copy after failure. Actual provider downloading and Photos success require this physical-device check; compilation does not establish those outcomes.

## Verified delivery

- Version `0.3.0 (1018)`, display name `forum lite`, unchanged bundle ID `dev.sylar.clearforum`.
- Source `55a56489ffae4dba0ab36c5739c3a3bbc376ea42`.
- [GitHub Actions run 36536066731](https://github.com/SyIar/clear-forum-flutter/actions/runs/36536066731) completed successfully: 60 Swift core tests, media checks, arm64 iPhoneOS Release compilation and packaging. No simulator was used.
- Local IPA: `D:\workspace\sideloadly-setup\ForumLite-0.3.0-1018-unsigned.ipa`.
- Size: `2,526,196` bytes. SHA-256: `90f8423f1e9bd817d9e8000de5bf6ff3273a87b8050e20ddf8e9c3a862d9ef87`.
- Verified source/run metadata, checksum, ZIP CRC, version/bundle identity, add-only Photos usage description, arm64 device executable, app assets, MediaProbe resource, no Flutter runtime, and matching install-folder copy.
- Not installed during this task. Swipe behavior, original-image display and real-provider download/Photos results require the user's device test.
