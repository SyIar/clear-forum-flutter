# South thread query URLs

South full-thread navigation now prefers `read.php?tid=2973920` instead of
`read.php?tid-2973920.html`. Author-filtered threads keep the legacy form, such
as `read.php?tid-2973760-uid-1191634.html`, including their pagination. Existing
query-style author links are converted to that form too.
This is a device compatibility experiment requested
after build 1043; the desktop Safari identity and desktop WebKit content mode
from that build remain enabled.

Validated thread routes are converted before HTTP requests, reader loading,
HTML parsing and main-frame GET navigation in the embedded South browser.
Relative links, thread pagination, author filters and existing library entries
use the same conversion. Thread ID, forum ID, author filter, page and fragment
remain intact. The previously accepted neutral `fpage=0` and empty `toread`
hints are removed. Login, purchase/action URLs, POST submissions, directory and
author-topic routes are not rewritten.

Bookmarks recognize both route spellings without rewriting saved data or
losing custom labels. Existing cache identity remains the same, so a route
spelling change does not discard the stored reading position. Browser rewrite
attempts are bounded if the server repeatedly redirects to the legacy spelling.

Regression coverage includes preserved filters, page and floor anchors,
request headers/cookies, parsed thread destinations, cache aliases and old
bookmark selection/removal. Cloud Core tests and an iPhoneOS Release build
validate the package; logged-in behavior and layout require physical-device
acceptance. No simulator is used.

## Build 1044

- Source: `b60719e90a2dcac831c3aa93deba01bedd9964fb` on `main`.
- [Actions run 36691308033](https://github.com/SyIar/clear-forum-flutter/actions/runs/36691308033)
  succeeded on 2026-09-30.
- All 276 Swift Core tests passed, including five new thread URL regression
  tests. Repository, localization, font and media checks passed.
- The Xcode 26.3 iPhoneOS arm64 Release build and unsigned IPA packaging passed.
- Physical-device verification remains pending, especially a full thread,
  author-filtered thread, pagination and an existing bookmark.
- Downloaded IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1044-unsigned.ipa`.
- Size: `46,644,791` bytes.
- SHA-256: `b53aad165a8a486ab4ff06c4b2ef7bc0cd2beb654c4c700cf80c8fbc5581a946`.
- Local verification passed archive CRC, source/run metadata, SHA-256, build
  number, bundle identity, unsigned arm64 executable and required media/icon
  resources. Embedded fonts and Chinese translations match the repository.
