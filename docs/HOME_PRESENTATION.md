# Home presentation and media return retention

## Changes

- Home has one `Open forum` entry with the site's original skyline logo. The introductory copy is removed. The application icon and bundle identifier are unchanged.
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
