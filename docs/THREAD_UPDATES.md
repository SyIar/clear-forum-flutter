# Thread update tracking and media return

## Behavior

- Opening a successfully loaded thread records its current maximum floor number as the local read baseline. This is the thread's maximum at visit time, not a claim that every floor was individually read.
- The reader uses numbered post links on the final page. When viewing an earlier page, it follows the last-page navigation link using the existing session. It does not infer totals from page size, count article elements, or confuse global post IDs with floor numbers.
- Home checks distinct threads in Bookmarks and Recent reading on entry. The lower-right native SwiftUI `.glass` refresh button and pull-to-refresh explicitly repeat the check.
- A successful background check updates `latestMaximum` only. If it exceeds `seenMaximum`, every Home row for that thread displays `Updated` and the old/new floor numbers. Opening the thread again records the new baseline.
- Legacy entries retain their links and order. A refresh can discover a latest floor, but a baseline is established only when the user opens the thread. Existing unknown baselines are not silently marked read.
- Thread IDs deduplicate different pages, fragments and renamed slugs. Forums are excluded. Records persist locally in `reading_library_v1`; only threads retained in bookmarks or the recent ten entries keep tracking data.
- Checks are serial and fetch HTML only. They never fetch image/video bodies, navigate to posting endpoints, or alter the local reading URL. Session/verification/rate-limit errors stop the batch and preserve previous state. Individual inaccessible threads also retain their previous state.
- Last-page discovery follows at most two additional pages to handle a newly added page during checking; incomplete discovery is reported as unknown rather than a guessed count. In-flight checks cannot overwrite a newer visit's baseline.

## Media return

Image and video viewers are full-screen modal roots, so there is no navigation predecessor for UIKit's normal interactive pop. A native `UIScreenEdgePanGestureRecognizer` now recognizes a single-finger rightward swipe from the left edge and invokes the existing close action after sufficient movement or a deliberate flick. Short/cancelled/reversed gestures do not dismiss. The transition uses the existing modal dismissal, not a custom interactive pop animation.

The edge gesture takes precedence over descendant pan gestures only at the screen edge. Central image paging, image pinch/double-tap zoom and video scrubbing keep their existing handlers. Video return follows the same resolver/audio/WebKit cleanup as its Back button. The underlying thread is not reloaded on media dismissal.

References: [Apple gesture delegate precedence](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate), [XenForo pagination markup example](https://xenforo.com/community/threads/problems-with-xenforo-com.204448/).

## Device acceptance

No simulator is used at the user's request. Cloud core tests cover terminal-page detection, stable thread identity, legacy storage migration, persistence and read/update transitions. Arm64 Release compilation validates the app target; the user verifies device behavior:

1. Image: left-edge return at normal/zoomed scale; central drag, pinch and double tap still work; short edge gestures remain in the viewer.
2. Video: edge return during loading/playback/error; playback stops and the previous thread stays at the same position. Reopen and verify refresh remains functional.
3. Home: open a thread, check its recorded maximum, return and tap the glass refresh button. After new floors appear, verify `Updated` and old/new numbers in both bookmark/recent rows.
4. Open an updated thread, return, and verify its baseline is advanced and the badge cleared. Restart the app and verify persistence.
5. Offline/expired-session checks must retain the previous counters and report failure, never fabricate an update.

Live authenticated counts and touch arbitration remain pending physical-device acceptance.

## Directory thumbnails and breadcrumbs

The user's open directory DOM was inspected on 2026-09-28. Its `.structItem-cell--icon .dcThumbnail img` uses a transparent `data:` placeholder in `src`; the real cover is the inline `background-image` URL. The parser now reads that URL, then lazy/normal image attributes, and excludes `.structItem-cell--iconEnd` (the latest poster's avatar). Native rows load the cover automatically, show progress and preserve the compact pinned-row presentation.

Six of the inspected 21 rows contained legacy HTTP cover URLs. Thumbnail resolution upgrades these URLs to HTTPS, retaining their path/query and rejecting credentials or nonstandard HTTP ports. The app does not disable App Transport Security or fall back to insecure image requests.

A representative legacy CDN URL returned HTTP 200 with `Content-Type: image/jpeg` to an HTTPS HEAD request with the forum Referer and a browser-compatible User-Agent. Directory thumbnail requests use those headers without cookies; media posters and body-image requests retain their previous defaults. This verifies URL/header compatibility, not rendering on the iPhone.

The first `.p-breadcrumbs` trail is rendered as a compact, horizontally scrollable native button row in both forum and thread views. Internal readable destinations retain their category fragments. Root category anchors come from `.block--category .u-anchorTarget[id]`; navigation scrolls to the first forum in that category. The user clarified that this request concerns the hierarchy trail, not the numeric page navigation, whose layout is unchanged. No browser cookies or raw authenticated page dumps are committed.
