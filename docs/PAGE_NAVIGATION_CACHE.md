# Native pagination and reading cache

## Navigation

The bottom toolbar groups Previous / Page X / Next into one leading native Liquid Glass surface. A flexible native toolbar spacer separates the trailing Refresh button into its own glass surface. Page X opens a native selection sheet: scroll the page list or enter an exact page number. The current page is checked, first/last boundaries disable unavailable directions, and selecting the current page does nothing.

Page ranges come from the forum's numbered navigation, next link and compact `data-last` metadata. Arbitrary page jumps retain `order` and prefix filter query parameters, remove post fragments, validate the range and stay within supported read-only site routes. Thread/forum routes use `page-N`; routes such as watched threads use `?page=N`. The reader does not derive a page count from post count.

## Back and cache behavior

- A mounted reader keeps its loaded model and scroll position when another page or media viewer covers it. Reappearance does not repeat loading or the initial anchor jump.
- Recreated readers and revisited numbered pages first consult an in-memory LRU cache. It holds at most 20 parsed page snapshots and a 16 MiB estimated text/metadata cost. The cost is a cache budget, not an exact bound on total app memory.
- Cache keys include page number and filter queries. Page-1 aliases, fragment differences and query ordering share a snapshot. Explicit post/category links still take precedence over a saved reading position.
- Recreated views restore the nearest saved post/list row; already mounted views retain their native scroll offset. Positions are not persisted across process termination, and a rebuilt layout does not promise pixel-identical placement after image loading or rotation.
- Refresh and pull-to-refresh deliberately bypass snapshots and replace them only after a successful response. Cache hits update Recent reading without another last-page request or advancing the read baseline from stale data. Home update checks run once per Home lifetime, plus explicit refresh; returning to Home no longer starts a batch.
- Background maximum-floor checks remain fresh network reads and do not replace or evict the reader's snapshots. Merely closing Site browser does not reload. Capturing a page from it invalidates prior session snapshots; clearing the forum session does the same.

## Memory lifecycle

iOS memory warnings purge cached snapshots and decoded image cache entries, cancel image work, and release inactive reader models and poster tasks. The visible reader stays usable. Page network requests are also tied to their task cancellation. Existing image cache limits remain 80 entries / 64 MiB estimated decoded size under `NSCache`; iOS can evict those entries sooner.

This is a memory cache, not an offline archive: an evicted page, a new page or a page opened after app termination must be fetched again. Cached HTML, account cookies and media bodies are not written into a new disk cache. Bookmarks and reading history retain their existing storage independently.

Apple references: [native toolbar grouping and flexible spacers](https://developer.apple.com/videos/play/wwdc2025/323/), [scroll position](https://developer.apple.com/documentation/swiftui/scrollposition), [responding to memory warnings](https://developer.apple.com/documentation/uikit/responding-to-memory-warnings), [NSCache cost-limit semantics](https://developer.apple.com/documentation/foundation/nscache/totalcostlimit).

## Validation

Swift core regression coverage includes page/filter URL construction, compact page ranges, cache aliasing, isolation of filters, LRU eviction, cost limits, snapshot replacement, position retention and invalidation. No simulator checks are run. Physical-device acceptance:

1. Open a thread with multiple pages. Verify the leading glass group and separate trailing Refresh button, select a distant page, and test first/last boundaries.
2. Select pages with a tag filter active. Verify the filter remains in the URL and the list remains filtered.
3. Read several floors, open another thread/image/video and return. Verify there is no content reload or initial-anchor jump. Revisit a numbered page and check its saved floor.
4. With an already cached page, disconnect the network and return to it. Explicit refresh should attempt the network; navigation to uncached pages still requires connectivity.
5. Return to Home and verify no automatic update batch; its Refresh button must still update the thread badges.
6. Test both light/dark mode, landscape, large text and selection-sheet dismissal. Memory-pressure UI behavior remains a device check; core tests cover deterministic cache eviction separately.

## Verified delivery

- Version `0.2.0 (1010)`, source `cfd50ab81b84ec8d9e3b5782b6e20e51b16a1151`.
- [macOS run 36519314043](https://github.com/SyIar/clear-forum-flutter/actions/runs/36519314043) passed all 21 Swift core tests, media probe/support checks, arm64 Release compilation and packaging. No simulator checks ran.
- IPA: `D:\workspace\sideloadly-setup\SimpLite-0.2.0-1010-unsigned.ipa`.
- SHA-256: `de4f67b0682929b65b7b618e743ab384824974c1fbf51bb8bb0372f6a8b29d05`; size `3,372,887` bytes.
- Verified downloaded source/run metadata, checksum, ZIP integrity, arm64 executable, bundle identity, version, display name, AppIcon assets and MediaProbe.js. No Flutter runtime is included. The install-folder copy has the same checksum.
- Not installed during this task. Toolbar layout, selection-sheet interaction, retained scroll position and memory-pressure UI behavior await physical-device acceptance.
