# Untagged book author presentation

## Cause and change

The catalog title parser previously required a category opener after the author name. Search results that ended with the author clause had no such delimiter, so their full title remained visible and the byline fell back to the posting account.

The title presentation now accepts either a category opener or the end of the title. Both ASCII and full-width colons remain supported. An empty author still falls back to the posting account. Category extraction remains independent.

This affects the shared catalog/search presentation only. Original titles, posting-account metadata, post details, and followed-book account matching retain their existing behavior.

The supplied search page returned HTTP 200 and contains keyword-highlight spans within the author name. A regression fixture covers this structure, preserving the uploader in the source model while showing the literary author in the result card. The downloaded page stays in ignored local artifacts and is not committed.

## Validation

- Local Swift grammar, repository-policy, and diff checks passed. Grammar checking is not compilation or type checking.
- Added regression coverage for terminal authors, both colon styles, trailing whitespace, missing names, and highlighted search-result markup.
- CI run [36863624038](https://github.com/SyIar/clear-forum-flutter/actions/runs/36863624038) passed for source commit `1e6864f1d4afdf960a76aeb1d632e5f113e512a5`: 355 ForumCore tests, 20 TiebaCore tests, and Release iPhoneOS compilation (build 1066).
- No simulator was used; visual acceptance remains on a physical device.

## Delivery

- Package: `D:\workspace\sideloadly-setup\ForumLite-0.3.0-1066-unsigned.ipa` (56,219,172 bytes).
- SHA-256: `d69bf0e5819cb1b93d58ca6ebf967144c9c3dd7759b8d63c36ab72f99615eef3`.
- Verified artifact integrity, build/source metadata, ARM64 iPhoneOS executable, fonts, localization, and ForumUI resources. The package is unsigned for the existing sideload workflow.
