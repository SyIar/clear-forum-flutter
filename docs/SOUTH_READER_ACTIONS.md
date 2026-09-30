# South desktop identity and reader controls

## Request identity

South now uses a fixed desktop Safari User-Agent for HTTP page loads, search,
purchase requests and its session browser. Existing mobile identities migrate
when the session is created; cookies, bookmarks, history and the separate Simp
profile are kept. The South WKWebView also requests desktop content mode.

The `.html` route suffix is not treated as a mobile-site signal. Both accepted
PHPWind route formats remain supported, preserving paging, author filters and
post fragments. An anonymous comparison of the supplied `tid=2973920` and
`tid-2973920.html` URLs, with mobile and desktop identities, returned HTTP 200
and fourteen `tpc_content` occurrences for all four requests. This does not
prove the logged-in iPhone page has identical markup or layout. Device
acceptance is still needed; desktop identity alone cannot override all website
responsive CSS or repair native parser/layout defects.

Apple documents the independent [custom User-Agent](https://developer.apple.com/documentation/webkit/wkwebview/customuseragent)
and [preferred content mode](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/preferredcontentmode)
settings used here. No URL rewriting or new authentication flow is introduced.

## Native controls

- Reader pagination stays in its native bottom-left toolbar group. The
  bottom-right glass control is a single menu toggle. It expands Top, Bottom
  and Refresh vertically above it; actions, scrolling, navigation and purchase
  activity close the controls. Motion respects Reduce Motion.
- Expanded buttons use a native Liquid Glass container. Apple documents its
  [combined glass rendering](https://developer.apple.com/documentation/swiftui/glasseffectcontainer).
- South post headers place an ellipsis menu beside the floor number. Select
  text, author filtering, full-size avatar, author topics, follow/unfollow and
  block actions live there. The separate scope button and avatar action sheet
  are removed. Invalid/missing author IDs cannot trigger account actions.
- Select text presents a medium/large bottom sheet with a selectable,
  non-editable UITextView and Copy all. Body paragraphs, quotes, code and visible
  links keep their content. The exporter omits purchase-action tokens and image
  transport metadata. The selection survives ordinary sheet updates.
- App-owned labels are localized in the approved Chinese resource file;
  original post text remains unchanged. Mixed system/CJK typography is retained.

## Validation

Local Swift syntax parsing and repository/localization checks are used before
CI. Core tests cover persisted desktop-identity migration, separate site
identities, a real macOS WebKit/HTTP identity comparison, and text export with
whitespace, nested blocks, full link targets and excluded purchase metadata.
No simulator is used. Device checks should cover logged-in South browsing,
expanded button placement, post menu actions and arbitrary text selection.

## Verified build 1043

- Source: `2e72569187a071263190e2461ba4c76289901797` on `main`.
- [Actions run 36684731902](https://github.com/SyIar/clear-forum-flutter/actions/runs/36684731902)
  succeeded on 2026-09-30.
- All 271 Swift Core tests passed, including the persisted identity migration,
  real macOS WebKit/HTTP User-Agent consistency, and text-export cases.
- Repository, localization, mixed-script font and existing media checks passed.
- The Xcode 26.3 iPhoneOS arm64 Release build and IPA packaging passed.
- Installation and physical-device UI acceptance remain pending.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1043-unsigned.ipa`.
- Size: `46,641,631` bytes.
- SHA-256: `cd955c69ee57c3a72b2fdd8bb612f9a2e010281bbc6d80654605ffef2fa29f3e`.
- Downloaded artifact verification passed ZIP CRC, source/run metadata, checksum,
  version/build, bundle identity, arm64 executable, unsigned status and media/icon
  resources. Embedded fonts match their sources and Chinese string tables match
  all source translations. The installation-directory copy is byte-identical.
