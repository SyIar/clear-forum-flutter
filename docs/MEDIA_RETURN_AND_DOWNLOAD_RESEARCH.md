# Media return gestures and downloads

Date: 2026-09-29

Status: research and proposed design, not implemented. Reviewed the native source at `47e2185` (the documentation commit following build 1016) and current Apple documentation. No simulator, device gesture trace, user-media download, or new IPA build was performed for this investigation.

The sections below record the original investigation. The subsequent implementation and revised image requirement are tracked in [MEDIA_VIEWER_DELIVERY.md](MEDIA_VIEWER_DELIVERY.md).

## Findings from the current implementation

`native/App/MediaViewer.swift` presents a new full-screen `MediaNavigationController` whose only root controller is the image or video viewer. It is not a media destination pushed onto the reader's navigation stack. Returning uses a custom `UIScreenEdgePanGestureRecognizer`, `UIPercentDrivenInteractiveTransition`, and `MediaSlideAnimator`.

The following conditions are directly visible in the source:

- The gesture must start near the physical left screen edge. A rightward drag beginning farther inside the image or video is not a return gesture.
- Recognition requires positive horizontal velocity greater than the magnitude of vertical velocity. A sufficiently diagonal start is rejected.
- Completing a return requires at least 33% of the container width, or at least 24 pt of travel with a release velocity of 700 pt/s or more.
- Even after passing the distance threshold, any negative horizontal velocity at release cancels the return. A small reverse movement before lifting the finger can therefore undo an otherwise sufficient swipe.
- The width-relative distance grows in landscape.
- Recognition is blocked during a transition or while the media navigation controller presents another controller. Blocking behind an active share sheet is appropriate; a nested system video presentation requires separate observation.

These conditions explain plausible ways for the reported repeated swipes to occur. They are code findings, not a measurement of which condition rejected each swipe on the user's phone. Distinguish a gesture that never starts from a transition that starts and then snaps back.

`ZoomImage` in `native/App/RichBodyView.swift` uses `UIScrollView` for zooming and panning. `MediaPlayerController` embeds `AVPlayerViewController` and retains a `WKWebView` fallback. These views introduce gesture arbitration, but it has not been demonstrated that a particular child recognizer causes the reported failure. The existing `shouldBeRequiredToFailBy` delegate follows Apple's documented pattern for prioritizing an edge gesture over descendant gestures; its name must not be mistaken for a reversed priority bug.

There is no source evidence that device performance is the principal cause. Faster rendering cannot change the recognition and completion rules above.

## Recommended return behavior

Prefer putting the image and video viewers on the reader's existing native navigation path and using system push/pop transitions. Keep the reader instance, loaded page, image references, and scroll position as the underlying destination. Do not create a second one-controller navigation stack and expect its root controller to pop.

Apple exposes `interactiveContentPopGestureRecognizer` on iOS 26 and later. It supports horizontal return gestures across the navigation controller's content area, complementing the screen-edge recognizer. The project's iOS 26 deployment target can use this API. Native navigation is a better fit for the requested interactive, horizontal, cancelable return than continuing to duplicate navigation animation and completion decisions in a modal dismissal.

This still requires deliberate interaction rules:

- At the image's minimum zoom, allow ordinary horizontal return gestures where they do not compete with another control.
- When the image is zoomed, preserve image panning in the content area and retain edge return. Pinch zoom must continue to work.
- On video, preserve the scrubber, playback controls, and pinch gestures. A drag on the progress slider must not navigate back.
- Keep the app's current immersive toggle in the same controller; it hides chrome without restarting playback. Test AVKit/WebKit's own full-screen presentations separately rather than assuming a recognizer on the parent covers them.
- Stop playback and release resources only after a completed pop. Canceling an interactive return must leave the same playback session alive.
- Keep a visible back button outside immersive mode and retain existing page-cache behavior. Returning must not schedule a new page request.

This is a project-specific recommendation, not a claim that system navigation automatically resolves every child gesture conflict. Implementation must preserve system gesture delegates and avoid private target/action or KVC tricks.

A smaller fallback is to retain the current modal transition, add a deliberately bounded leading-edge activation region, and revise completion logic so tiny reverse velocities do not always cancel. It touches less navigation code, but leaves custom transition/gesture maintenance in the app. Do not enable a blanket full-screen custom pan that steals image panning or video seeking. Exact custom thresholds would require device tuning; they are not established by this research.

## Download layout

| Viewer | Proposed controls |
| --- | --- |
| Image | A single floating native Liquid Glass download icon at bottom right. |
| Video | One floating native Liquid Glass capsule at bottom right: download on the left, full-screen toggle on the right. |

Use icons, with accessible labels and individual hit targets of at least 44 pt. The download side can show bounded progress or an indeterminate spinner, offer cancellation, and briefly show a success checkmark. Keep the full-screen side usable while downloading. Position the video group above the transport/scrubber area, preserving the purpose of the current 76 pt bottom offset and checking landscape separately. A shared `UIGlassEffect` surface can provide the requested grouped appearance without another dependency.

## Saving images

The current `MediaViewerItem.image` contains only a `UIImage`. `ImageStore` decodes the first image frame with `kCGImageSourceThumbnailMaxPixelSize = 2048` and discards the response bytes. Saving that object would save the display preview, potentially losing source resolution, animation, and file metadata.

Carry the source URL and appropriate request context into the image viewer alongside its existing preview. On a download tap, fetch the source file to disk without re-encoding it through `UIImage`, then add the resource to Photos. Do not pre-download every original or hold full-size originals in the decoded image memory cache. If the forum HTML exposes only a thumbnail URL, that alone does not establish the original upload URL; save the available resource accurately and do not label it as an original that was never obtained.

The first download requests `PHPhotoLibrary` authorization for `.addOnly`, with `NSPhotoLibraryAddUsageDescription` in the native target. The current native project has no such usage description. PhotoKit can create an asset from a local image/video resource via `PHAssetCreationRequest` inside `performChanges`. Retain the local file until the Photos operation completes. Show success only after its completion reports success. Formats Photos cannot import can be exported through a Files document picker.

## Saving videos

The current `startPlayer(_:cookies:)` already receives a validated HTTPS candidate and domain/path-filtered provider cookies. `TurboResolver` returns a signed candidate URL; generic embeds may produce one through the media probe, or remain in the working web-player fallback.

Downloads should be independent of playback. Preserve the exact successful source context as transient state, use `URLSessionDownloadTask` to stream a complete file to disk, validate the HTTP result and actual resource type, then import a compatible video into Photos. A resolved URL is only a download candidate: successful playback alone does not prove complete-file download or Photos compatibility.

| Source | Feasibility and boundary |
| --- | --- |
| Direct MP4/MOV or another compatible complete video file | Download to disk and import into Photos after checking the response and file. |
| Turbo signed HTTPS candidate | Reuse the resolver and applicable provider session. A stale signed URL can require resolving again. Complete-file downloading and Photos import still need a real-device acceptance check. |
| Generic embed with a usable HTTPS file candidate | Use the same file download path; keep the existing working playback fallback unchanged. |
| Generic embed working only inside WebKit, with no reusable source | Cannot promise download merely because the web player works. Show a clear unavailable state rather than downloading its HTML page. |
| HLS `.m3u8` | Apple's `AVAssetDownloadURLSession` supports offline HLS assets. This is a separate offline-playback path, not a promise of a single video file importable into Photos. Saving to Photos may require obtaining or producing a compatible standalone file. |
| `blob:` or a protected/unexportable stream | Not a normal HTTPS file download; exclude from the first direct-file implementation. |

Keep download ownership outside the viewer so returning to the thread does not implicitly cancel a user-started transfer. Bound concurrent downloads and temporary storage; expose cancel/retry and handle space or permission failures. Background continuation requires a background URLSession and lifecycle recovery and must not be claimed for an ordinary foreground task. If added, preserve the source's expiry/session constraints and note that force-quitting the app is not a guaranteed continuation path.

Continue the existing session isolation: send only cookies applicable to the media provider and target URL, re-evaluate redirected requests, and never forward forum account cookies to an external media host. Do not log complete signed URLs or credentials. These are implementation boundaries, not additional account setup for the user.

For an initial implementation, prioritize source-image files and available complete video files saved to Photos, with Files export for unsupported Photos formats. Leave HLS offline management and media conversion as explicit separate work; no backend proxy or third-party decoder is needed for the first scope.

## Physical-device acceptance

No simulator is required. Check small/slow/diagonal swipes, a canceled swipe followed by a completed swipe, portrait/landscape, minimum/maximum image zoom, native video playback, web fallback, immersive mode, and the player's own full-screen mode. Confirm that returning preserves the reader's position and visible images and that canceled returns preserve playback.

For saving, check a source image larger than 2048 px, an animated image where supported, a compatible complete video, denial of add-only permission, insufficient space, an expired source, interrupted download, cancellation, and leaving the viewer while downloading. Confirm the saved asset appears in Photos and is readable/playable; HTTP completion alone is insufficient.

## Primary references

- [UIScreenEdgePanGestureRecognizer](https://developer.apple.com/documentation/uikit/uiscreenedgepangesturerecognizer): edge-origin gesture behavior.
- [UIGestureRecognizerDelegate](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate): Apple's descendant-gesture failure-priority example.
- [interactiveContentPopGestureRecognizer](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivecontentpopgesturerecognizer): native content-area interactive pop; Apple's linked Markdown metadata specifies iOS 26 availability.
- [PHAccessLevel.addOnly](https://developer.apple.com/documentation/photos/phaccesslevel/addonly) and [NSPhotoLibraryAddUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription): additions-only Photos permission.
- [PHAssetCreationRequest](https://developer.apple.com/documentation/photos/phassetcreationrequest): creation from resource data/files.
- [URLSessionDownloadTask](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask): disk download, progress, completion, and lifecycle behavior.
- [AVAssetDownloadURLSession](https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession): offline HLS asset downloads.
- [UIDocumentPickerViewController export initializer](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:)): Files export.
- [UIGlassEffect](https://developer.apple.com/documentation/uikit/uiglasseffect): native glass surface and interaction support.
