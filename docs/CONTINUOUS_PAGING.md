# Continuous reader paging

## Behavior

The same native reader supports Simp and South threads, directories, and author-topic lists. Pulling beyond the top loads the previous page and prepends its content. Pulling beyond the bottom appends the next page. No adjacent page means no request. The former pull-to-refresh gesture is removed; the bottom-right Refresh action and explicit page selection remain available.

- Require a user-controlled scroll phase and at least 56 points of overscroll. Momentum, initial layout, and image size changes while idle cannot start a request. A drag can start at most one request; another page requires a new drag.
- Fetch while the edge is being pulled, then commit after the scroll phase becomes idle. Show a small overlaid spinner without inserting a loading row that changes content height.
- Keep existing post/block IDs and reuse identical blocks in overlapping posts. Deduplicate repeated posts and directory rows, including sticky threads. Do not repeat page titles or insert full-page separators.
- Retain a visible content ID in the scroll-position binding and disable insertion animations. Prepending and pruning keep that reading anchor instead of navigating to the start of the incoming page. When starting at the title/header, use the first visible content row as the anchor. Physical offset stability with variable image heights remains a device acceptance check.
- The bottom `Page X`, sharing/bookmark URL, page selector, and saved reading position follow the page owning the top visible row. Explicit page navigation or Refresh resets the continuous window to the selected page.
- Failed adjacent requests keep all existing content and offer a small Retry notice at the affected edge. They do not replace the reader with an error page or initiate a refresh.

## Data and request boundaries

`ReaderPageWindow` stores individual `ForumPage` snapshots and creates a combined presentation only for rendering. The normal cache and purchase service always receive a single raw page, never the aggregate. Adjacent responses must match the expected URL, page number, kind, and filters. South author filters and Simp tag/order filters stay separate. Duplicate and skipped-page insertions are rejected.

Only one adjacent request is active. Request ID and session-generation checks discard results after navigation, cancellation, browser/session changes, or leaving the screen. Pending content is also dropped in those cases. Media return retains the existing continuous window under the same rules as the previous reader.

South purchases use the offer's source page. An unlock updates that snapshot and its cached copy, retaining unchanged content identities. It does not move the user's active URL or replace the other stitched pages. Newly loaded retained South pages remain eligible for the existing zero-SP automatic purchase flow; positive prices still need an explicit tap.

## Memory

Keep at most five live page snapshots, subject to the existing parsed-content cost estimator and a 16 MiB soft budget. The active page is always retained even if it alone exceeds the cost budget. Remove the farthest end when over budget; do not discard the protected reading page. The normal bounded LRU cache supplies older pages when revisited. If the user moves away before an adjacent response arrives, it may be cached without remaining in the live window. No unbounded HTML history or per-page web views are retained.

## Rationale and validation

Use native [scroll geometry observations](https://developer.apple.com/documentation/swiftui/scrollgeometry) and [scroll phase observations](https://developer.apple.com/documentation/swiftui/view/onscrollphasechange(_:)) instead of taking over the scroll view's pan gesture. [SwiftUI scroll-position identity](https://developer.apple.com/documentation/swiftui/scrollposition) supplies the anchor when content is inserted or removed. These APIs fit the existing SwiftUI reader and avoid replacing its navigation or media gesture handling.

Synthetic Swift Core cases cover ordered prepend/append, stable block IDs, first/last-page boundaries, duplicate/skipped-page responses, source/filter isolation, South URL aliases, repeated sticky rows, repeated media posts, bounded eviction, purchase-source updates, and one request per intentional edge drag.

Local Swift syntax parsing, repository policy checks, and diff checks pass. Swift compilation and test execution have not been performed for this batch. Simulator testing, cloud builds, and packaging remain paused. Device acceptance should include pages 48 -> 47 -> 48, rapid direction changes, image-heavy pages, all-blocked pages, purchase gates across two pages, a failed request followed by Retry, and returning from image/video viewers.
