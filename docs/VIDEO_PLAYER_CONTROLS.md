# Video player controls

## Gallery gestures (2026-10-10)

Forum image sheets use horizontal native paging instead of left/right arrow
buttons. Paging commits the title and share target together, and a cancelled
swipe keeps the original selection. A zoomed image keeps horizontal dragging
until it is zoomed out; downward sheet resizing/dismissal remains native.
Only the selected image and immediate neighbors stay in the controller cache;
neighbors retain previews and release full-resolution images and transfers.
Previous/next accessibility actions remain available without visible arrows.

In the local video gallery, tapping the canvas toggles the header, fullscreen
button, play button, time, and progress slider together. Hidden controls neither
intercept touches nor remain in the accessibility tree. Tapping again restores
them without pausing or seeking. The slider still owns scrubbing exclusively;
horizontal file paging and downward dismissal continue to use canvas drags.
VoiceOver can activate the video canvas to restore controls. Remote videos
continue using AVKit's existing transport controls.

Device acceptance: swipe both ways and cancel a partial swipe; test the first,
last, and single-image cases, a slow image load, zoom/pan and sharing after a
swipe; hide/reveal video controls while playing and paused; scrub, then change
files or dismiss. CI compilation does not replace these touch checks.

## Local gallery live scrubbing (2026-10-02)

The downloaded-file viewer updates the AVPlayer picture while the progress
slider is dragged. Playback pauses during dragging; after the final frame is
resolved, it resumes only if it was playing before the drag. Seeking remains
exclusive to the slider, preserving horizontal gallery paging and downward
dismissal on the canvas.

Use one outstanding seek and retain only the latest requested time, following
[Apple QA1820](https://developer.apple.com/library/archive/qa/qa1820/_index.html).
This avoids repeated cancellation and a backlog of obsolete seeks. Exact seeks
show the requested frame; decoding speed still depends on the video format and
keyframe spacing. There is no generated thumbnail strip or network prefetch.

Core tests cover coalescing, release ordering, duplicate targets, accessibility
changes, invalidation and failed callbacks. Switching files, closing the viewer,
or backgrounding invalidates pending callbacks, so they cannot resume a hidden
player. Actual frame latency and gesture feel require device testing.

## Layout

- Keep the NavigationStack system back button and interactive return gesture.
- The navigation title is always `Video` for every provider and direct stream; it never displays a CDN or provider hostname.
- Top right: download, then refresh. No overflow menu and no Details action.
- Download uses a clockwise ring starting at twelve o'clock, with an integer percentage in its center. It uses received bytes versus the response's expected byte count. Unknown length and source preparation use an indeterminate indicator, not a fabricated percentage.
- Tapping an active ring opens the global download manager, with pause, continue and cancel per task. At transfer completion, keep 100 while Photos imports; show a checkmark only after a successful import. Import failures retain the Save to Files recovery action in the manager.
- Bottom right: one native Liquid Glass fullscreen button. Hiding the navigation bar does not recreate the player or cancel a download.
- Loading has only a centered activity indicator. Playback diagnostics, elapsed time, buffer percentage, throughput, and the report/copy screen are removed from the native player UI and its diagnostic event collection.
- Playback errors show a concise message and Open in browser, presented inside the app with SFSafariViewController. Refresh remains in the top bar.

## Playback and downloads

The user's build 1023 report confirmed successful Turbo and non-Turbo downloads to Photos. The transfer, validation, isolated media cookies, Turbo source refresh, and Photos import paths are preserved. The viewer and its navigation button observe the same download instance, including after returning to an active transfer. Refreshing playback does not cancel a download.

The current unbuilt changes add an app-owned queue, a floating native glass progress button and resumable transfers. See [Global video downloads](GLOBAL_VIDEO_DOWNLOADS.md) for lifecycle, persistence, limitations and pending device checks. These changes are not part of the user's build 1023 acceptance.

The report also showed a 25-second application buffering timer interrupting an otherwise prepared AVPlayer item. Remove that timer; waitingToPlay is not itself an error. AVPlayer retains control of buffering and resumption, and actual item/transport failures still produce an error. A network path monitor displays an offline message only after an unsatisfied path persists for three seconds while loading/buffering. It leaves the player alive, ignores short path changes, and permits playback recovery. A satisfied path alone is not treated as proof that the remote server is reachable.

Non-Turbo provider pages still support real Play gestures and the existing webpage fallback when the native candidate fails. Their ready webpage may appear when interaction is required; no extra application buffering text is shown. Turbo does not automatically open a provider advertising page on failure.

## Sources and validation

- [Apple: automaticallyWaitsToMinimizeStalling](https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling) documents waiting for sufficient media and automatic resumption.
- [Apple: NWPathMonitor.currentPath](https://developer.apple.com/documentation/network/nwpathmonitor/currentpath) describes observation of the available network path.
- [Apple: UIButton.Configuration](https://developer.apple.com/documentation/uikit/uibutton/configuration-swift.struct) provides native glass button configurations.

Local syntax parsing is not compilation. Cloud validation runs the existing Swift Core and media checks, then an arm64 iPhoneOS Release build. No simulator. Device acceptance should cover the clockwise progress ring, cancel/continue, Photos completion, refresh during a download, slow buffering, offline recovery, provider fallback, fullscreen, and the existing return gesture.
