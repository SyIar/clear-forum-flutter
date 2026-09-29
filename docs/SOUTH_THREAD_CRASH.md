# South thread navigation crash, 2026-09-29

## Confirmed cause

The user's device produced three identical build 1018 crash reports at 15:40:16, 15:40:22, and 15:40:28. Each was a main-thread `EXC_BREAKPOINT / SIGTRAP`, through SwiftUI's assertion path into `ReaderView.body`. A further user-triggered reproduction at 15:50:17 produced this explicit fatal message:

> SwiftUICore/EnvironmentObject.swift:93: Fatal error: No ObservableObject of type LibraryStore found. A View.environmentObject(_:) for LibraryStore may be missing as an ancestor of this view.

The app's root destination supplied per-site environment objects, but a nested reader destination did not have a guaranteed `LibraryStore` ancestor when NavigationStack hosted it. The toolbar accesses that object while rendering the new reader, before a recoverable page error can appear. This is a navigation dependency failure, not evidence of invalid cookies or HTML parsing failure.

## Fix

`ReaderView` now requires `LibraryStore` and `ForumSession` in its initializer and observes them directly. Both the root route and nested reader route pass the existing site-specific instances. The reader supplies those same objects to descendant rich-content views. No fallback instance, default forum, global current-session switch, or cookie reset is introduced.

The required initializer lets the compiler reject any reader creation site that omits its dependencies. All reader entry sites were audited. This also protects Simp's nested reader navigation from the same missing-object path.

## Evidence boundary and validation

Crash reports and the filtered live log are stored only on the user's computer under `D:/workspace/sideloadly-setup/logs/forum-crashes/`. No raw device report, device identifier, account information, cookie, or page capture is included in the repository. No simulator is run. Native device compilation is followed by user verification of directory -> thread -> another page -> back, for both forums.

The browser tool blocked South page inspection under its site-safety policy. That restriction was respected. The fix is based on the actual app crash logs and local source, not an unperformed website inspection.

Reference: [Apple EnvironmentObject](https://developer.apple.com/documentation/swiftui/environmentobject) requires the matching observable object to be supplied by an ancestor.

## Build 1019 delivery

- Source commit: `6b71ec55eba191f2d4a7061a8aa5dbb47e08a999`.
- [GitHub Actions run 36539161138](https://github.com/SyIar/clear-forum-flutter/actions/runs/36539161138): 65 Swift Core tests, media checks, native arm64 iPhoneOS Release compilation, and packaging passed. No simulator.
- Version `0.3.0 (1019)`, display name `forum lite`, bundle ID `dev.sylar.clearforum`.
- Local IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1019-unsigned.ipa`.
- Size: `4,145,616` bytes. SHA-256: `2728a5d92fb8afe540ae2941588a4369e3a21efba87c48254a2c15d09f0095e4`.
- Verified source/run metadata, checksum, ZIP CRC, version/bundle identity, arm64 executable, app icon declaration/assets, Photos usage description, MediaProbe resource, no Flutter runtime, and matching delivery copy.
- Also includes the generated FORUM/LITE icon and [playback loading feedback](PLAYBACK_LOADING.md).
- Not installed during this task. Device acceptance of the fixed navigation and provider-specific buffer/speed data remains pending.
