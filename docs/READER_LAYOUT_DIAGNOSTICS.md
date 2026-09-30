# Reader layout, South paging, and diagnostic export

## Confirmed paging failure

An anonymous desktop-Safari GET of the user-provided
`https://south-plus.net/thread.php?fid-9-page-2.html` returned HTTP 200 with the
normal `ajaxtable` directory. Its title links carry `read.php?tid-N-fpage-2.html`.
The old route policy accepted only `fpage-0`; it discarded every title link
on page 2 and the parser then reported an unsupported page. This also prevented
the next page from joining the seamless scrolling window.

`fpage` is now accepted as a bounded directory-source hint (0 through 99999)
and omitted from canonical thread identity. Actual thread page, author filter,
and fragments remain intact. Ordinary threads use `tid=...`; author-filtered
threads retain their requested legacy URL syntax. Invalid hints, duplicate
parameters, and action links remain rejected. Synthetic regression fixtures
cover the observed directory structure and joining consecutive pages.

Error presentation now keeps the requested page identity, and diagnostics
retain adjacent-page failures plus the most recent drag peak/edge event.
The drag-trigger threshold and touch-only triggering behavior are unchanged.

## Layout

- South directory metadata shares one row: author at left, date and post count
  aligned at right.
- South post metadata occupies its own full-width row with UID at left and
  the complete date aligned at right. The menu's visible circle is 24 points;
  its hit area remains 44 points.
- Reader controls use a slider icon. Expanded top/bottom/reload actions share
  one vertical glass capsule with subtle separators.
- Video cards retain their 84-point height, fill/crop the thumbnail frame,
  and show only a centered circle-enclosed play icon on the right.

The glass grouping follows Apple's
[custom Liquid Glass guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).
Scroll diagnostics use the existing
[ScrollGeometry](https://developer.apple.com/documentation/swiftui/scrollgeometry)
and phase observations without installing competing gesture recognizers.

## Image investigation and export

Inline image requests now carry the referring reader page (falling back to
the forum origin) instead of inventing an image-directory referrer. South
uses its existing desktop identity. Image HTTP status, MIME type, byte count,
network error code and decode failures are available in diagnostics. This is
not proof that every reported image problem is resolved; the affected device
page still needs to be exported if its images fail again.

The reader's top-right menu and page error screen offer Page diagnostics.
Copy loading diagnostics includes the request chain, parser outcome, page
window, edge state, and the latest 40 image-request events. Copy page HTML adds
the sanitized HTTP response, including responses that failed parsing. If the
page was cached before capture was available, it can be fetched explicitly.
The site browser also has a bug icon to copy its current sanitized DOM.

Exports are user initiated and clipboard-local. Cookie headers are never
collected. Scripts, form values, event handlers and secret query values are
removed. Page text and image addresses remain for debugging. Source snapshots
are memory-only, capped at six pages and one megabyte per page; raw source is
neither committed nor uploaded. Device gesture, appearance and image behavior
remain subject to physical-device acceptance. No simulator is used.

## Verification

- Source commit: `e20b1d3b4a7625e39ac852d3b768441a37087601`.
- [Native build 1048 / workflow run 48](https://github.com/SyIar/clear-forum-flutter/actions/runs/36697128496):
  291 Swift Core tests passed with zero failures; generic iPhoneOS Release
  compilation succeeded on 2026-09-30.
- Local validation parsed 121 Swift files (syntax only), checked 394 localized
  strings and 381 app text keys, and checked repository language policy.
- Physical-device acceptance is pending for layout, edge gestures, and the
  user's failing image page.
- Downloaded delivery: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1048-unsigned.ipa`
  (47,702,709 bytes).
- SHA-256: `dc6594f78025b84bd38288fc3603ad9e323ab878cc029881a951706a22093f88`.
- Verified ZIP CRC, build/source/run metadata, unsigned ARM64 iPhoneOS app,
  unchanged application identity, font resources and bundled Chinese strings.
