# forum lite 0.3.0 (1027)

## Delivery

- [GitHub Actions run 36578382954](https://github.com/SyIar/clear-forum-flutter/actions/runs/36578382954) succeeded on 2026-09-29.
- Source commit: `3ab8454b1830faf626946df0efeaf00865ad0768`.
- Native SwiftUI/UIKit, arm64 iPhoneOS Release, Xcode 26.3. No simulator run.
- Display name: `forum lite`; bundle ID: `dev.sylar.clearforum`.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1027-unsigned.ipa`.
- Size: `4,821,163` bytes.
- SHA-256: `4085e6fa6a50e427c30b92ba0a1f501255c5657f591534b0ef9a3883b00253d9`.

The download and delivery copy both passed checksum verification. ZIP CRC, source/run metadata, version/build, device platform, arm64 executable, icon assets, media/Gofile scripts, dependency notice and Photos usage description were verified. No Flutter runtime is bundled. Signing and installation were not requested in this turn; device acceptance remains pending.

## Included changes since build 1023

- Simplified South and Simp home banners: logo opens the native reader; the separate glass `safari` compass opens the original forum page using that forum's existing browser session. No visible `Open forum` caption or automatic chevron.
- South home author subtitles, local author following, three recent topics per author and persistent `New` reading status. Home bookmark controls are icon-only.
- Global video download queue, floating glass progress control, per-item management and resumable transfers where supported. Background behavior remains checkpoint/pause and resume on foreground, not uninterrupted force-quit downloads.
- Native Gofile file browser, access/password states, validated downloads and recursive serial folder downloads.
- South author-only views, avatar actions and local blocking; compact pinned topics, fixed-height emoticons, bare-URL linking, purchase recovery and page-content preservation.
- Continuous previous/next page loading at reader boundaries and the accumulated media-viewer refinements.

See the feature documents for behavior and device checks: [Home](HOME_PRESENTATION.md), [Following](SOUTH_FOLLOWING.md), [Video downloads](GLOBAL_VIDEO_DOWNLOADS.md), [Gofile](GOFILE_VIEWER.md), [Continuous paging](CONTINUOUS_PAGING.md).

## Validation and build fixes

- 177 Swift Core tests passed with zero failures.
- Media observer and Swift media-policy checks passed; all 9 Gofile JavaScript tests passed.
- Repository language/credential policy, Xcode device compilation, packaging and artifact upload passed.
- Build 1025 found one incorrect test expectation for Foundation `URL.path`'s trailing slash. The expectation was corrected; app URL behavior was unchanged.
- Build 1026 exposed a main-actor accessor in Gofile session deinitialization and a ReaderView type-check timeout. Cleanup now uses separately owned file URLs instead of reading `@Published` state in deinit; the reader uses smaller opaque view expressions with the same bindings and actions.
- Build 1027 includes both fixes. Remaining Xcode warnings concern an existing deprecated bar-button style, absent AppIntents metadata and iPad orientation declarations; compilation and packaging succeeded.

The current build proves compilation and automated checks. Live login, gestures, UI layout, provider downloads and Photos behavior still require the user's iPhone test.
