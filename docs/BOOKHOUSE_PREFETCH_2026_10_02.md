# Bookhouse next-publication prefetch

## Behavior

- Start one speculative request when visible body blocks reach 90% of the last loaded publication. Progress is measured within that publication's rendered block range, excluding earlier retained chapters. This is an approximate reading threshold, not a pixel percentage; paragraphs can have different heights.
- Reuse the existing bounded page cache. Reaching the edge consumes the prefetched page or awaits the same in-flight request, then uses the existing chapter-join checks. Prefetch does not append content, navigate, mark the next chapter as read, or update reading history.
- Preserve catalog ordering, including upper/lower parts and overlapping chapter bundles. There is no speculative request at the final chapter or across a catalog gap.
- A failed speculative request stays silent and is not repeated on subsequent visibility changes for the same target. The normal edge load can retry and present its usual error if needed.
- Cancel speculation when jumping, refreshing, leaving the reader, entering the background, changing the browser session, or receiving a memory warning. Replaced or canceled requests cannot publish stale results into the reader.
- Bookhouse catalog and search-result rows use the open-book `notebook` vector from the existing pinned ChunUI/Pika revision, including featured entries. Other forums keep their existing row icons.

## Verification

- Five regression tests cover the 89%/90% boundary, retained-publication isolation, last-chapter behavior, upper/lower ordering, request reuse, failed-attempt suppression, and cancellation with a late response.
- Local Swift grammar, repository-language policy, localization, and diff checks passed. These checks are not Apple compilation or execution of the Swift tests.
- CI run 69 was superseded after the catalog icon request and canceled to avoid producing an outdated package.
- CI run [70](https://github.com/SyIar/clear-forum-flutter/actions/runs/36972959602), source `116dc1e51084c1c8b2ee3c79ea908b1af375343f`, passed 366 ForumCore tests and 20 Tieba tests, including all five new prefetch tests.
- The same run passed the repository, localization, font, design-system, media, and bridge checks and compiled the generic iPhoneOS Release app with Xcode 26.3. It generated unsigned build 1070 with both prefetch and the bookhouse catalog icon. No simulator or physical-device UI check was performed.

## Delivery

- Local package: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1070-unsigned.ipa` (56,255,421 bytes).
- SHA-256: `461598527f72a5c9b61dfa3d38c0642006dacffb01124660a6c3ba9332e1757e`.
- Verified archive CRC, package checksum, source/run/build metadata, arm64 iPhoneOS executable, unsigned state, application identity, fonts, localization, updated ForumUI/Pika mapping/assets, and ChunUI bundle resources before copying the package to the delivery directory.
