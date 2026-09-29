# Home presentation and media return retention

The compact logo/compass banner is included in [build 1027](BUILD_1027.md); device presentation awaits acceptance.

## Changes

- Included in [build 1030](BUILD_1030.md): both forum readers omit the persistent login-status caption. Home uses the standard `bookmark` symbol for Add bookmark; the action and accessibility label are unchanged.
- Both forum homes show a compact logo banner without the `Open forum` caption or automatic navigation chevron. Tapping the logo opens the native reader. A separate 44-point native glass `safari` compass opens that forum's original start page in the app's existing site browser, sharing its isolated login session. Choosing `Read page` returns to native reading; `Done` returns home. Purchase and poll pages are fetched afresh to preserve their original form markup.
- Thread rows in Bookmarks and Recent reading reuse the directory thumbnail and `ForumTagStrip`. Each tag opens its original prefix-filter URL independently of the thread row.
- `LibraryDocument.presentations` stores thumbnail URLs and tags by stable thread ID. Older `reading_library_v1` records remain valid. Custom bookmark titles, saved page URLs, read baselines, and history order are preserved.
- Visiting a directory supplies its row metadata; opening a thread supplies heading tags and `og:image`. The existing Home update check also fills metadata for older bookmarks. No additional per-row network crawler is added. Missing metadata does not erase known values, and removing the last saved/history reference prunes its presentation.
- Site-wide header logos are excluded from thread covers. Home uses the bundled logo, so that entry does not need an image request.
- Same-URL image tasks preserve an existing decoded image when SwiftUI restarts the task after a media viewer closes. Cancelled loads cannot replace newer view state. Poster resolution also keeps an existing result.
- A reader presenting its own image/video viewer retains its parsed page during a memory warning. Older hidden readers, the bounded page cache, and the shared image cache still participate in memory cleanup. iOS can reclaim caches, so revisiting evicted content may still require a request.
- The player fullscreen control is a 48-point circular native glass icon. Enter/exit labels remain available to VoiceOver without visible text.

## Asset source

The Home asset is an unmodified copy of the website header image observed in the user's open forum tab on 2026-09-29:

`https://simpcity.cr/data/assets/logo_default/simpcityMainLogo.png`

No cookies, account information, page captures, or thread media are bundled.

## Verification scope

The reported image reload after returning from video was intermittent and was not reproduced locally. These changes address two source-level lifecycle paths that could reset the page or image. Physical-device acceptance is still required; no simulator validation is performed.

Core regression coverage includes older library migration, metadata persistence across changed slugs/pages, independent preservation of bookmark titles/read state, metadata pruning, safe tag destinations, and rejection of site logos as thread covers.

## Verified delivery

- Version `0.2.0 (1011)`, source `5142f9fbddaa6ad3dc375cf0dab486f19c7d575b`.
- [macOS run 36520991873](https://github.com/SyIar/clear-forum-flutter/actions/runs/36520991873) passed all 24 Swift core tests, media probe/support checks, arm64 Release compilation and packaging.
- IPA: `D:\workspace\sideloadly-setup\SimpLite-0.2.0-1011-unsigned.ipa`.
- SHA-256: `10df7a9242a243139dac1810b08b2accdca500eddf3c5614ef487dc862f8aaf5`; size `3,520,723` bytes.
- Verified source/run metadata, checksum, ZIP integrity, arm64 executable, bundle identity, display name/version, bundled `ForumLogo` asset and `MediaProbe.js`. No Flutter runtime is included. The install-folder copy has the same checksum.
- Not installed during this task. Physical-device checks: existing bookmark/history covers and tag navigation; the simpler Home header in both appearances; icon-only fullscreen toggle; page 48 to video and back without image flicker. The intermittent reload report remains unconfirmed on-device.
