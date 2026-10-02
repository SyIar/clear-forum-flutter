# Follow novels by their declared author

## Problem

The catalog/search presentation extracted the literary author, but followed-book records, catalog filtering, and reader acceptance still compared the posting account and its ID. Reposted chapters from other accounts were excluded, and the followed-book byline showed the uploader. The chapter parser also omitted split publications such as `(26 upper)` and `(26 lower)` in the site's localized notation.

## Behavior

- Use the author clause from the selected title as the followed book's literary identity. Search by book name and traverse every results page within the existing bounded catalog limit. Include numbered results with the same normalized book name and declared author, regardless of uploader or account ID.
- Verify loaded reading pages against the same literary identity and catalog URL. A different declared author, an undeclared author, an unrelated book, or a URL outside the catalog is not accepted for a declared-author book.
- If the title does not declare an author, retain the existing posting-account fallback. A verified seed page can supply a previously missing literary identity.
- Migrate old records from their saved seed titles when decoding the library. Preserve record ID, seed URL, reading position, and maximum read chapter. Clear the obsolete account ID and old refresh timestamps once for migrated literary-author books so the incomplete catalog can be repaired automatically. Subsequent refreshes use the existing hourly policy.
- Merge completed checks into the latest record so reading progress recorded during a network request is preserved. Catalog failures retain the available catalog and position.
- Parse upper/middle/lower publications, sort them in chapter order, and join parts before advancing to another chapter in either direction. Numeric chapter jumps enter the first available part; backward continuous reading enters the last available part.
- Original website post metadata and post details remain unchanged. No user data or downloaded website HTML is committed.

## Verification

- Six regression tests cover cross-uploader matching and rejection, split chapters and bundles, bidirectional part transitions, old-library migration, fallback metadata, and progress preservation during identity promotion.
- Local Swift grammar, localization, repository policy, and diff checks passed. Grammar checking is not compilation or type checking.
- CI run 67 caught immutable-title assignments in the new test fixtures. The fixtures now construct their titles at initialization; no model mutability change was needed.
- CI run [68](https://github.com/SyIar/clear-forum-flutter/actions/runs/36955249952), source `87a0523dea1ef4957b0018e6ceb368480b3d8f2c`, passed 361 ForumCore tests and 20 Tieba tests, including all six new literary-author tests.
- The same run passed repository, localization, fonts, design-system, media, and bridge checks, then compiled the generic iPhoneOS Release app with Xcode 26.3 and generated unsigned build 1068. No simulator or physical-device UI check was performed.

## Delivery

- Local package: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1068-unsigned.ipa` (56,234,583 bytes).
- SHA-256: `24b0ab7431231aa397eeee83663f2b6cdd29e668a71f83b43a7996c3d9a8c1ef`.
- Verified artifact ZIP integrity, package checksum, source commit and build metadata, arm64 iPhoneOS executable, unsigned state, application identity, fonts, localized resources, ForumUI/Pika resources, and ChunUI bundle assets before copying to the delivery directory.
- Upgrade using the existing app identity, then open the bookhouse module. Existing declared-author follows migrate without re-adding; their first catalog check bypasses the previous successful-check timestamp once. Live search availability still depends on the source website.
