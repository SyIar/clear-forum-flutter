# Video player controls

## Layout

- Keep the NavigationStack system back button and interactive return gesture.
- Top right: download, then refresh. No overflow menu and no Details action.
- Download uses a clockwise ring starting at twelve o'clock, with an integer percentage in its center. It uses received bytes versus the response's expected byte count. Unknown length and source preparation use an indeterminate indicator, not a fabricated percentage.
- Tapping an active ring offers cancellation. At transfer completion, keep 100 while Photos imports; show a checkmark only after a successful import. Import failures retain the existing Save to Files recovery action.
- Bottom right: one native Liquid Glass fullscreen button. Hiding the navigation bar does not recreate the player or cancel a download.
- Loading has only a centered activity indicator. Playback diagnostics, elapsed time, buffer percentage, throughput, and the report/copy screen are removed from the native player UI and its diagnostic event collection.
- Playback errors show a concise message and Open in browser, presented inside the app with SFSafariViewController. Refresh remains in the top bar.

## Playback and downloads

The user's build 1023 report confirmed successful Turbo and non-Turbo downloads to Photos. The transfer, validation, isolated media cookies, Turbo source refresh, and Photos import paths are preserved. The viewer and its navigation button observe the same download instance, including after returning to an active transfer. Refreshing playback does not cancel a download.

The report also showed a 25-second application buffering timer interrupting an otherwise prepared AVPlayer item. Remove that timer; waitingToPlay is not itself an error. AVPlayer retains control of buffering and resumption, and actual item/transport failures still produce an error. A network path monitor displays an offline message only after an unsatisfied path persists for three seconds while loading/buffering. It leaves the player alive, ignores short path changes, and permits playback recovery. A satisfied path alone is not treated as proof that the remote server is reachable.

Non-Turbo provider pages still support real Play gestures and the existing webpage fallback when the native candidate fails. Their ready webpage may appear when interaction is required; no extra application buffering text is shown. Turbo does not automatically open a provider advertising page on failure.

## Sources and validation

- [Apple: automaticallyWaitsToMinimizeStalling](https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling) documents waiting for sufficient media and automatic resumption.
- [Apple: NWPathMonitor.currentPath](https://developer.apple.com/documentation/network/nwpathmonitor/currentpath) describes observation of the available network path.
- [Apple: UIButton.Configuration](https://developer.apple.com/documentation/uikit/uibutton/configuration-swift.struct) provides native glass button configurations.

Local syntax parsing is not compilation. Cloud validation runs the existing Swift Core and media checks, then an arm64 iPhoneOS Release build. No simulator. Device acceptance should cover the clockwise progress ring, cancel/continue, Photos completion, refresh during a download, slow buffering, offline recovery, provider fallback, fullscreen, and the existing return gesture.
