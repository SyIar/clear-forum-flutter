# Per-item refresh feedback and Bookhouse reading/search

## Refresh activity

Simp/South tracked thread checks and South followed-author checks publish transient, per-item phases. The visible row displays a spinner and a repeating, low-opacity ChunUI blue sweep during the real request. Successful checks show a checkmark; a newly increased maximum or newly discovered unread topic triggers one brighter completion sweep. Previously unread content does not repeatedly trigger the completion effect when unchanged. Existing unread badges and reading baselines are preserved.

The modifier renders the pinned ChunUI `glimmSweep` shader inside the row. It runs at most 30 frames per second while visible and active. Offscreen rows, background scenes and Reduce Motion do not run the sweep. The status indicator has fixed dimensions and the effect uses an overlay, so refresh feedback does not move the list. Errors, cancellations and obsolete requests end the checking state without pretending success. Refreshes remain serial; author request coalescing and visit-token guards are retained.

## Toolbar alignment

The reader's top-right buttons now occupy fixed 44-point columns in one `ToolbarItem` with one shared glass capsule. UIKit no longer distributes separate toolbar items differently for `Button` and `Menu`. The menu indicator and the system's extra shared background are hidden. Icons remain 22-point Pika artwork. Bookhouse uses the same group, adding a search button.

## Bookhouse typography

Only Bookhouse post bodies opt into the novel text style: the default font increases from 17 to 20 points, extra line spacing increases from 2 to 7 points, and paragraph gaps decrease from 16 to 8 points. Font size and line spacing follow Dynamic Type. CJK characters retain Source Han Serif; Latin text retains the system face. Catalogs, headings, bylines and application controls keep their own styles. Paragraph IDs and lazy rendering are unchanged for reading-position tracking.

## Bookhouse search

The existing GET search flow is reachable directly from the Bookhouse reader toolbar as well as the module home. Keyword entry remains general, with `test` used for verification. Search results open in the native reader; the browser fallback preserves the submitted keywords and can import a captured search result back into the native list.

The supplied source has two distinct lists. Only `.thread-list > li` belongs to the search results; the separate `.post-list .post-item` section contains unrelated featured posts. Posting names come from the direct `font` sibling and dates from `i`/`time`. Result cards use the same title/author/tag formatting as the Bookhouse catalog. Pagination compares semantic queries while ignoring form decoration (`submit`, `action`, `bbsdr`), preserving keyword/author/category/root-post filters. The UI shows the current page without claiming a total the website does not provide. An empty result container is distinguished from an unrelated error page.

The user-supplied HTML and live response remain in local attachments/artifacts. Tests use synthetic, non-content fixtures for featured-list exclusion, metadata extraction, query-preserving pagination and empty/error pages.

## Validation

Windows Swift syntax checks, localization checks, repository policy and icon-resource checks passed. They do not replace the macOS compiler. No simulator is used; on-device sweep visibility, toolbar spacing and reading comfort remain for user acceptance.

## References

- [Pinned ChunUI sweep source](https://github.com/liseami/ChunUI/blob/b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb/Sources/ChunUI/Effects/CCSweepLight.swift), inspected from the existing local upstream source snapshot.
- [Apple toolbar shared background API](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)).
- [Bookhouse search form](https://www.cool18.com/bbs4/index.php?action=search&bbsdr=bbs4&act=threadsearch&app=forum&keywords=test), checked against the supplied source and an HTTP 200 live response.
