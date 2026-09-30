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
