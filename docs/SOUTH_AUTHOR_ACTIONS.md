# South avatar actions and local author blocking

Implemented locally on 2026-09-29. No packaging or cloud build was started, per the user's batch-optimization instruction.

## Interaction

Tapping a South post avatar opens a native action dialog:

1. **View full-size avatar** opens the existing image viewer and automatically fetches the available original file, retaining pinch, double-tap, share, and native back navigation. Explicit original-image attributes take precedence over the displayed avatar source. The app does not invent higher-resolution URLs or upscale a small server image as a claimed HD original. No extra loading text is added beside the magnifier.
2. **View author threads** opens `u.php?action-topic-uid-<uid>.html` in the native reader. Pagination and page selection preserve the author and the read-only `topic` action.
3. **Block author** stores the UID and display name locally. Matching topic rows and post floors disappear immediately, including in cached pages. Simp content and the server account's own ignore list are unaffected.

South's home toolbar and the reader overflow menu provide **Blocked authors**. **Unblock** restores locally hidden content without deleting bookmarks, history, or cached source pages. Missing UIDs are never inferred from display names; history and block actions are disabled when no valid UID is available.

## Parsing and state

The supplied HTML has 50 unique thread rows under `#u-contentmain .u-table`, a profile name under `#u-top .u-h1`, and a pager ending at page 11. Parsing is restricted to that main table area; account menus, sidebars, skin selectors, and other users' pagination are excluded. The route UID owns these topics, not the currently signed-in account. Directory rows also retain the topic creator UID separately from the subtitle and last-reply metadata.

Only `u.php` with `action=topic`, a positive numeric UID, and an optional valid page is accepted as a new reader route. Both legacy hyphen URLs and query aliases are supported. Profile edits, friendship actions, other `u.php` actions, duplicate parameters, and external origins remain outside the reader whitelist.

`LibraryDocument.blockedAuthors` is persisted in the existing South-specific local library. Older documents default to an empty blocklist. Clearing login cookies does not clear this library. Thread presentation metadata retains a known original author, allowing matching Bookmarks and Recent reading rows to be hidden as well. Existing saved entries without owner metadata can be identified when their thread or directory is next loaded.

Filtering happens at display time. The raw page cache, site pagination, original floor numbers, and maximum-floor update tracking remain intact. Empty visible pages keep their navigation controls. Blocked authors' free purchase offers are excluded both when scanning the page and immediately before a refreshed offer is submitted; refreshed raw pages remain intact for later unblocking.

## Validation

- Local HTML structure audit confirmed 50 unique main-table threads and 11 pages without copying account data or source HTML into the repository.
- Tree-sitter syntax parsing passed for 55 Swift files. This is not compilation or type checking.
- Repository language/credential policy and whitespace checks passed.
- Added synthetic Swift Core regression cases covering routes, history parsing, original avatar selection, UID matching, creator versus last-reply author, persistence/migration, per-site isolation, reversible filtering, and excluded purchase offers.
- Swift tests have not been executed. No simulator, iOS build, IPA, or installation was performed. Full compilation and device acceptance remain pending the user's explicit batch-build instruction.

Device acceptance: open all three avatar actions, browse author-history pages, block one author, check their topics and replies disappear across navigation/back, restart the app, unblock from home, and verify restored content and unchanged original floor numbers.
