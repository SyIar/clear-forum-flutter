# forum lite 0.3.0 (1030)

## Delivery

- [GitHub Actions run 36588266348](https://github.com/SyIar/clear-forum-flutter/actions/runs/36588266348) succeeded on 2026-09-29.
- Source commit: `be30d1d21297b8e416fd47537da18cddb9b7b16b`.
- Native SwiftUI/UIKit, arm64 iPhoneOS Release, Xcode 26.3.
- Display name: `forum lite`; bundle ID: `dev.sylar.clearforum`.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1030-unsigned.ipa`.
- Size: `4,959,763` bytes.
- SHA-256: `2b989c242128e8d4dfea9b434aa432813b5eb6b9ef35f13429f37f8e6cac36d3`.

## Included changes since build 1028

- Both forum homes open native search screens. Simp supports keywords, title-only search, date/relevance ordering, result snippets and pagination. South supports title search, any/all words, ordering and time ranges, using the supplied form and result HTML.
- Search results open the native reader; returning retains the result list. South parses the initial POST response directly and preserves the search identity when paging.
- South pinned threads share a compact card and matching expanded sheet.
- Persistent sign-in captions are hidden in both forum readers. Home uses the standard bookmark symbol for Add bookmark.

## Validation

- All 192 Swift Core tests passed in macOS CI.
- All 9 Gofile JavaScript tests, media observer checks, Swift media-policy checks and repository policy checks passed.
- Xcode device Release compilation, packaging and artifact upload passed.
- Local verification passed: CI checksum, exact source/run metadata, version/build, ZIP CRC, arm64 executable, icon assets, media/Gofile resources, dependency notice and Photos usage description.
- `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are Boolean true. No Flutter runtime is bundled. The delivery copy matches the downloaded artifact.
- Existing warnings remain for an old bar-button style, absent AppIntents metadata and iPad orientation declarations.

The IPA has not been signed or installed during this task. Physical-device acceptance remains pending for authenticated search submission, site verification flows, paging, result navigation and return, bookmark visibility, and the pinned-thread layout. CI success does not replace these interaction checks.
