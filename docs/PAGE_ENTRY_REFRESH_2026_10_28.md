# Refresh South and Bookhouse pages on entry

South reader tasks now fetch the current page when a destination appears, including a return from a pushed page. New destinations no longer stop at the in-memory page snapshot. Explicit page changes also fetch fresh content; reappearing destinations and manual refreshes preserve the visible row when it still exists. Initial links keep their fragment or start at the title. South offline sessions retain their local-only behavior.

Bookhouse catalog and reading destinations similarly refresh on appearance. Existing snapshots can supply scroll position but cannot satisfy an online entry refresh. Followed-book reading progress and explicit return points are retained. A failed network connection may fall back to a saved chapter; cancellation, authentication, verification and parsing errors are not converted into offline success. Explicit cached-search destinations remain local. Seamless chapter prefetch and cached adjacent navigation are unchanged.

South and Bookhouse search results reload their current results URL when returning from a result. An empty search form does not submit automatically. South home checks eligible tracked items again on re-entry. Bookhouse's existing appearance task already does this. Successful update checks still have the one-hour cooldown, and the existing automatic failed-attempt cooldown is unchanged. Simp's entry behavior is unchanged.

The reload is tied to destination appearance, not every SwiftUI body evaluation or app foreground transition. Existing cancellation and request identifiers prevent a response for an abandoned destination from replacing current content.

## Validation

- Local Swift syntax parsing and repository checks; these are not compilation or device UI validation.
- macOS CI runs the existing core test suites and compiles the native iOS app.
- Device acceptance: open a South directory, enter a post and return; verify a new directory request and preserved row. Reopen a previously viewed post and confirm a fresh request.
- Repeat for Bookhouse catalogs, search results and followed-book reading. Check preserved chapter/paragraph, adjacent prefetch, and airplane-mode access to cached chapters.
- Verify South downloaded threads and cached-search destinations do not require connectivity, and repeatedly entering home does not bypass the one-hour update cooldown.

No new runtime text, localization keys or LEO configuration are required.
