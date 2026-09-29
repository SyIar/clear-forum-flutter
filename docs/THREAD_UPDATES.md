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

Image and video viewers share a UIKit presentation owned by the reader, outside recycled post cells. A native `UIScreenEdgePanGestureRecognizer` drives `UIPercentDrivenInteractiveTransition`: the viewer moves horizontally with the finger, revealing the reader with subtle parallax. A sufficiently long swipe or deliberate flick completes the return; short, cancelled or reversed gestures animate back into the viewer. The Back button uses the same horizontal animation. This replaces the previous release-only gesture and default modal dismissal.

The edge gesture takes precedence over descendant pan gestures only at the screen edge. Image pinch/double-tap zoom and video scrubbing keep their existing handlers. Resolver/audio/WebKit cleanup runs only after successful dismissal, not during an interactive cancellation. The reader remembers completed load requests so reappearing after media dismissal neither reloads the thread nor repeats its initial anchor jump. Reduce Motion removes background parallax and shortens the transition.

The video status-label row is removed. Loading/retry/error states remain in the main content area. A lower-right native UIKit `.glass()` button toggles `Full screen` / `Exit full screen`, hiding/restoring the navigation and status bars while expanding the existing player or web view. It sits above the AVKit transport region and retains the same player, web session and playback position. It uses public layout APIs, with no private AVKit fullscreen selectors, forced orientation or second player. Edge return remains available in this mode.

References: [Apple interactive transitions](https://developer.apple.com/documentation/uikit/uipercentdriveninteractivetransition), [Apple gesture delegate precedence](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate), [UIKit glass buttons](https://developer.apple.com/documentation/uikit/uibutton/configuration-swift.struct/glass()), [XenForo pagination markup example](https://xenforo.com/community/threads/problems-with-xenforo-com.204448/).

## Device acceptance

No simulator is used at the user's request. Cloud core tests cover terminal-page detection, stable thread identity, legacy storage migration, persistence and read/update transitions. Arm64 Release compilation validates the app target; the user verifies device behavior:

1. Image: slowly drag from the left edge at normal/zoomed scale; the page must track the finger. Release a short drag and reverse a long drag to verify cancellation. Complete a return and use the Back button; both must animate horizontally. Pinch, double tap and sharing still work.
2. Video: repeat edge return/cancellation during loading/playback/error. Cancellation must preserve playback; a completed return must stop it and leave the thread at its prior position. Reopen and verify refresh remains functional. Test both Turbo and a generic provider.
3. Video fullscreen: toggle the lower-right button during playback and pause, in portrait and landscape. Verify the title/status bars hide and restore, playback position is retained, native controls remain reachable, and edge return works while fullscreen. Also check a generic provider using its web fallback. Native AVKit's own fullscreen controls remain available independently.
4. Home: open a thread, check its recorded maximum, return and tap the glass refresh button. After new floors appear, verify `Updated` and old/new numbers in both bookmark/recent rows.
5. Open an updated thread, return, and verify its baseline is advanced and the badge cleared. Restart the app and verify persistence.
6. Offline/expired-session checks must retain the previous counters and report failure, never fabricate an update.

Live authenticated counts and touch arbitration remain pending physical-device acceptance.

## Directory thumbnails and breadcrumbs

The user's open directory DOM was inspected on 2026-09-28. Its `.structItem-cell--icon .dcThumbnail img` uses a transparent `data:` placeholder in `src`; the real cover is the inline `background-image` URL. The parser now reads that URL, then lazy/normal image attributes, and excludes `.structItem-cell--iconEnd` (the latest poster's avatar). Native rows load the cover automatically, show progress and preserve the compact pinned-row presentation.

Six of the inspected 21 rows contained legacy HTTP cover URLs. Thumbnail resolution upgrades these URLs to HTTPS, retaining their path/query and rejecting credentials or nonstandard HTTP ports. The app does not disable App Transport Security or fall back to insecure image requests.

A representative legacy CDN URL returned HTTP 200 with `Content-Type: image/jpeg` to an HTTPS HEAD request with the forum Referer and a browser-compatible User-Agent. Directory thumbnail requests use those headers without cookies; media posters and body-image requests retain their previous defaults. This verifies URL/header compatibility, not rendering on the iPhone.

The first `.p-breadcrumbs` trail is rendered as a compact, horizontally scrollable native button row in both forum and thread views. Internal readable destinations retain their category fragments. Root category anchors come from `.block--category .u-anchorTarget[id]`; navigation scrolls to the first forum in that category. The user clarified that this request concerns the hierarchy trail, not the numeric page navigation, whose layout is unchanged. No browser cookies or raw authenticated page dumps are committed.

## Clickable title tags

Directory `.structItem-title .labelLink` and thread `h1.p-title-value .labelLink` are preserved as compact clickable tag strips before the title. Tags have independent buttons rather than nesting buttons in a thread-row button. Header tags are removed from the plain title to avoid duplicate text in the title, bookmarks and history.

Live DOM verification showed `?prefix_id[0]=N` in directory links and `?prefix_id=N` in thread-heading links. These are XenForo forum prefix filters, not arbitrary text searches. Both forms are accepted only on read-only forum routes with bounded numeric values; existing rejection of mutations, foreign origins and duplicate query keys remains. A live `News` prefix link returned the expected one-thread `forum_view`, so the result remains in the native reader. Pagination retains the filter query.

Additional device acceptance: tap a tag in each view, verify the filtered native directory, navigate its pages if present, and use Back to return to the original thread/list. Long tag lists scroll horizontally without widening the page.

## Verified delivery

- Native version: `0.2.0 (1007)`; source `14c9923f1a287f6cf8bf63990481adeb731b3e62`.
- [macOS run 36436554872](https://github.com/SyIar/clear-forum-flutter/actions/runs/36436554872) passed all 16 Swift core tests, existing media probe/support checks, arm64 Release compilation and packaging. No simulator checks ran.
- Local IPA: `D:\workspace\sideloadly-setup\SimpLite-0.2.0-1007-unsigned.ipa`.
- SHA-256: `6ff4402b23b0b8864d60ed7675c3ad275fe517e0ad42b5cc15f43d36718ac5a2`; size `3,305,977` bytes.
- Downloaded source/run metadata, ZIP integrity, arm64 executable, bundle identity, display name/version, AppIcon assets and MediaProbe.js were verified. No Flutter runtime is packaged. The copied install-folder file has the same checksum.
- Not installed during this task. Physical-device gestures, live update refresh and rendering remain pending the user's acceptance.
