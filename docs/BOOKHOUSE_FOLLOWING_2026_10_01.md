# Bookhouse followed novels

Search results support a context-menu action to follow a numbered novel publication. The source posting account and normalized book title form the matching boundary; the literary author extracted only for catalog presentation does not replace that account. The selected post verifies the account ID when available. Reading a publication checks both name and ID again.

The Bookhouse home includes a followed-books section with resume position, latest chapter, update badge, per-book request feedback, manual refresh and swipe-to-unfollow. Initial follow collects search pages serially. Re-entering the home or foreground checks stale catalogs at a 15-minute interval. This is foreground checking, not an iOS background schedule. Failed or incomplete checks preserve the previous catalog and reading position. Catalog scans are bounded to 50 pages and 5,000 matching publications; at most 100 books can be followed.

The supplied search structure was verified with public metadata only. It has 100 results on page 1, five on page 2 and no results on page 3. The empty page still renders a Next link. Empty parsed results now terminate pagination. Featured entries are excluded. Chapter ranges overlap, so catalog lookup prefers the narrowest matching publication. Missing chapters never silently advance to a later number.

The followed reader keeps the current novel typography and adds a chapter catalog, numeric jump and previous/next navigation. Recognizable body headings locate individual chapters inside bundled posts. At the bottom, an intentional upward pull continues to the next publication without growing the navigation stack. Body headings, rather than a possibly broad publication title, determine where continuation begins. An unrecognized target heading opens the publication beginning with an explicit notice. Links to unrelated posts keep using the ordinary reader.

The first visible paragraph determines the chapter and position. A short debounce, scroll-idle, navigation and background saves persist it. Catalog checks merge into the latest record to avoid overwriting concurrent reading progress. Reopening restores the paragraph. Loading or restoring a viewport does not process stale visibility callbacks. Maximum-read chapter remains separate from the current resume chapter, so revisiting earlier content does not mark later unread chapters read. Existing library data gains an optional followed-books field and remains compatible.

Regression coverage includes numeric/fullwidth/Chinese chapter parsing, same-book/account matching, duplicate and overlapping publications, update baselines, reading-position preservation, chapter anchors, account mismatch, persisted-data migration and the site's empty-page Next-link behavior. Synthetic fixtures contain no downloaded prose. No simulator is used; chapter transitions, restoration and context-menu behavior require physical-device acceptance.

## Build 1063 validation

- Source: `705cf6ad63436856e1a640d80fd5ae8d378ee298`.
- [Native iOS CI run 36836082033](https://github.com/SyIar/clear-forum-flutter/actions/runs/36836082033) passed using Xcode 26.3 and the generic iPhoneOS Release destination.
- ForumCore: 337 tests passed, including seven followed-reading tests and the new empty-terminal-page pagination regression. TiebaCore: 20 tests passed.
- Repository, localization, fonts, design-system resources, media-probe and Gofile bridge checks passed.
- Opening a known followed chapter from search, bookmarks or history also activates followed-reading mode.
- Delivered `ForumLite-0.3.0-1063-unsigned.ipa` (56,159,486 bytes). SHA-256: `9005764960e24b911fc800c1ac267751fca2f94685415919dbd05ea8191d1386`.
- Verified source/run/build metadata, archive CRC, arm64 iPhoneOS executable, bundled fonts and localization, ForumUI/Pika and ChunUI resources. The IPA is unsigned for sideloading; physical-device UI acceptance remains pending.
