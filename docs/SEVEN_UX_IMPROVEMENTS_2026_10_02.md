# Reading and download workflow improvements

## Delivered scope

1. Hosted-file browsers share one listing header and 44-point row actions. Enqueuing a file or album keeps the user in the browser; progress and completed-file export remain available in place.
2. The global download drawer groups video, Gofile, and other host tasks into In progress, Needs attention, and Completed, sorted by creation time. Saved files support preview, sharing, and Files export. Video jobs retain their source title and thread link.
3. File-host batch plans, stable item IDs, saved paths, skipped items, errors, and opaque resume tokens persist in Application Support. System background sessions can finish the current file; metadata traversal and the next file wait for the app to become active. Reopening prioritizes reconnecting the previous transfer before new queued files. Temporary link failures can be retried with refreshed metadata. Receipts recover a completed move interrupted before queue persistence.
4. Forum and novel readers offer Return to reading after explicit jumps, without immediately replacing the saved anchor. Forums show a new-content divider based on the previous maximum visible floor. Tieba also retains its maximum read floor when returning to earlier pages.
5. Novel reading settings provide text size, line spacing, paragraph spacing, side margins, and System/Paper/Night backgrounds. App controls keep the system font; these preferences affect novel content only.
6. Home update checks show counts, results, last-check time, and an explicit fresh-skip state. Updates only filters existing rows without reordering them. The existing hourly policy stays intact. An inset animated side rail replaces the broad overlay over row text.
7. Followed novels automatically cache a publication when its body becomes visible. The next five chapter numbers, including split publications, can also be cached explicitly. Catalog rows mark offline content. Offline text persists across launches with 50/100/250 MB limits, least-recently-read eviction, and a clear-cache control separate from reading progress. Existing continuous chapter reading and 90% prefetch remain available.

## Follow-up interaction changes

- Simp home keeps update information in a small popover anchored to the existing lower-right control. Opening it never starts a check. It shows progress, the current title, results, last successful check, and the updates-only filter. Its Refresh action retries eligible failures and stale items while skipping successes less than one hour old. Automatic checks retain the same hourly policy.
- Simp bookmark and recent-reading rows always retain the navigation chevron; checking, success and failure never replace that affordance. Row update badges and request animations remain separate.
- Read caching only applies to followed books. Visibility, rather than fetching or speculative preloading, triggers the cache. Saving a publication does not mark its other chapters read. Cache failures do not interrupt reading.
- A search icon at the chapter catalog's upper left opens global offline body-text search across all currently followed books. Searches scan immutable cache snapshots on a cancellable background task, with a 300 ms debounce and a 200-result limit. They do not fetch pages, touch cache recency, or change reading progress. Results identify the book, publication, chapter and matching paragraph. Selecting a result uses the cached publication and its paragraph anchor; same-book jumps retain the return-to-reading action, and another book opens a new reader. Evicted or invalid cache files are skipped with a visible notice.
- Search regression cases cover relaunch, multiple books, styled runs, Unicode matching, bundled chapter anchors, result limits, author validation, corrupt files and eviction during a search.
- The chapter catalog replaces numeric input with a normalized progress slider. It starts at the currently visible chapter (chapter 30 of 100 is 30%), previews the target while dragging, and navigates only on release. Missing catalog chapters show a notice instead of skipping silently. A single-chapter book disables scrubbing.

## Storage and operating limits

- Download task history and tokens stay outside the Files-visible download directory and are excluded from backup. Paths are validated and rebased after the app container changes. A corrupt queue is preserved and reported instead of silently overwritten.
- Resume depends on the server and iOS accepting the saved connection. Expired resume data prompts a fresh transfer; a partial HTTP response is not accepted as a complete file. Force-quitting prevents background execution until the app is reopened.
- Video downloads retain the existing foreground/pause/resume behavior. The system background transfer change applies to Gofile and hosted files. At most three recent local video export copies totaling up to 1 GB are retained; removing these copies does not delete Photos assets.
- Offline novel caching stores parsed text, not remote illustrations or attachments. Network access is still needed to discover newly published chapters. Cache clearing does not remove followed books, catalogs, or reading positions.

## Validation

- Core regression tests cover cache relaunch, author isolation, LRU eviction, the next-five selection, safe paths, resumed response validation, queue serialization, and refreshed file identity.
- Tieba regression coverage checks that returning to an earlier page preserves the maximum read floor while updating the actual resume anchor.
- Local checks cover Swift syntax, repository policy, localization, icon mapping, Tieba integration, and Gofile/media bridge behavior. Local syntax checks are not an iOS compilation.
- macOS CI performs the Swift suites, native font/media checks, and the full Release iOS device build. Device behavior involving iOS suspension, real host expiry, Photos permissions, and VoiceOver still needs a physical-device pass.

## Device acceptance paths

- Enqueue individual files and an album; verify in-place feedback, drawer groups, pause/continue, completion preview/export, and reopen recovery.
- Background during an active host transfer, then return; confirm that its current file is saved once and the next queued file starts only when active.
- Jump to a far forum page or novel chapter, then use Return to reading; verify the original anchor and high-water floor remain intact.
- Cache a followed novel, disable networking, reopen the app, and read cached chapters. Change appearance and clear only the cache.
- Refresh two libraries within an hour and use Updates only; check that fresh items are skipped, failed checks remain retryable, and row order stays stable.
