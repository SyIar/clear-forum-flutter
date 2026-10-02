# Bookhouse next-publication prefetch

## Behavior

- Start one speculative request when visible body blocks reach 90% of the last loaded publication. Progress is measured within that publication's rendered block range, excluding earlier retained chapters. This is an approximate reading threshold, not a pixel percentage; paragraphs can have different heights.
- Reuse the existing bounded page cache. Reaching the edge consumes the prefetched page or awaits the same in-flight request, then uses the existing chapter-join checks. Prefetch does not append content, navigate, mark the next chapter as read, or update reading history.
- Preserve catalog ordering, including upper/lower parts and overlapping chapter bundles. There is no speculative request at the final chapter or across a catalog gap.
- A failed speculative request stays silent and is not repeated on subsequent visibility changes for the same target. The normal edge load can retry and present its usual error if needed.
- Cancel speculation when jumping, refreshing, leaving the reader, entering the background, changing the browser session, or receiving a memory warning. Replaced or canceled requests cannot publish stale results into the reader.

## Verification

- Five regression tests cover the 89%/90% boundary, retained-publication isolation, last-chapter behavior, upper/lower ordering, request reuse, failed-attempt suppression, and cancellation with a late response.
- Local Swift grammar, repository-language policy, localization, and diff checks passed. These checks are not Apple compilation or execution of the Swift tests.
- Apple CI verification is pending. No simulator is used.
