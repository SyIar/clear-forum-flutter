# forum lite 0.3.0 (1028)

## Delivery

- [GitHub Actions run 36582491736](https://github.com/SyIar/clear-forum-flutter/actions/runs/36582491736) succeeded on 2026-09-29.
- Source commit: `a51cfcc4b11a565a219a6e0685310c2c4632687d`.
- Native SwiftUI/UIKit, arm64 iPhoneOS Release, Xcode 26.3. No simulator run.
- Display name: `forum lite`; bundle ID: `dev.sylar.clearforum`.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1028-unsigned.ipa`.
- Size: `4,860,634` bytes.
- SHA-256: `af709738cb19a7ef0c575cd5892b10d8bb5790579480253891a08a04f4056993`.

The artifact and delivery copy match the CI checksum. ZIP CRC, source/run metadata, version/build, device platform, arm64 executable, icon assets, media/Gofile resources, dependency notice and Photos usage description passed local verification. Both `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are Boolean true in the final IPA. No Flutter runtime is bundled. The IPA has not been signed or installed during this task.

## Included changes since build 1027

- One floating download control and management sheet for video downloads and Gofile batches, with shared pause, continue and clear-finished controls.
- Gofile batches continue after leaving their pages while the app stays in the foreground; directory discovery is retained at app scope. Reopening the same folder page uses its existing batch.
- Gofile Helper uses native navigation and edge-back gestures. Finished tasks stay in their list sections so completion does not remove the row that opened the details.
- Explicit Files sharing configuration fixes the missing On My iPhone / forum lite directory. Packaging now rejects an app without both document-sharing flags.
- Permanent instructional paragraphs were removed from downloads, home empty states, following and poll cards. Necessary guidance uses an information button and popover; actionable errors remain visible.
- South Following preserves display names from posts and repairs legacy account identifiers without marking topics read.

## Validation

- All 179 Swift Core tests passed, including the two added Following regressions.
- All 9 Gofile JavaScript tests, media observer checks and Swift media-policy checks passed.
- Repository policy, Xcode device compilation, final app checks, packaging and artifact upload passed.
- Local verification confirmed the downloaded IPA and delivery copy are identical.
- Existing non-blocking warnings remain for an old bar-button style, absent AppIntents metadata and iPad orientation declarations.

Physical-device acceptance remains pending: mixed download controls, leaving and reopening Gofile pages, background pause/resume behavior, Files access to existing downloads, information popovers and repaired Following names. Build success is not a claim that these device interactions were tested.
