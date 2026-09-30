# Glass home, wallpaper, content typography, and Filester compatibility

## Module selection

The four existing module destinations use native interactive Liquid Glass cards
in one `GlassEffectContainer`. Logos and domain labels remain the entry points.
The backdrop belongs only to module selection; readers retain their readable
system surfaces. There is no replacement app heading.

The app requests Bing's current mainland-China daily image and first tries the
1080x1920 rendition. A 1920x1080 fallback fills the portrait viewport if the
portrait rendition fails. The endpoint and portrait image were checked live:
HTTP 200, JPEG, 1080x1920, 332256 bytes on 2026-09-30.

Only entries marked `wp: true` are accepted. Copyright and source links remain
visible at the bottom. The archive is an undocumented Bing homepage endpoint,
not a promised stable developer API. An unavailable response preserves the
previous cached image, or the bundled gradient on first use. Downloaded photos
are not committed or bundled into the application.

Requests use a separate ephemeral session without forum cookies or credentials,
bounded metadata/image sizes, HTTPS Bing hosts and redirect validation. A single
atomic cache file stores the latest image and its attribution. Old files do not
accumulate. Image dimensions and decoding are checked before replacing it.

Refresh uses local Gregorian midnight, including time-zone/daylight-saving
changes. A visible foreground homepage checks again at midnight; an inactive or
suspended application checks on its next active display. There is no claim of
an exact background wakeup. Failures or an archive that has not rolled over retry
at five-minute intervals while active. Repeated same-day appearances reuse the
cache. Navigation is never blocked on a wallpaper request.

Sources:

- [Apple: Liquid Glass in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Microsoft: daily homepage images and wallpaper availability](https://support.microsoft.com/en-us/topic/explore-the-homepage-bab2022c-cdb4-4d1f-80e2-c8f5c55712c7)
- [Bing homepage archive](https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN)

## Content and interface fonts

`appFont` uses Apple's system font. It is used for the root environment, buttons,
download lists, status/error text, controls, menus, badges, and page numbers.
UIKit navigation/search appearance is no longer globally overridden.

`forumFont` and the embedded framework's `tiebaFont` are explicit content styles:
forum titles, usernames, excerpts, tags, source breadcrumbs, poll choices, post
text and the selectable-text sheet. They retain the existing CJK-only Source Han
Serif cascade; Latin letters and digits remain system sans-serif. Existing rich
text font runs keep that same cascade. Typography never applies to whole reader
screens or containers holding app controls. Tieba retains its font-size setting.

## Bookhouse

Catalog cards put extracted tags before the title. Source titles remain intact
in detail views. Home no longer starts thread-update checks, exposes a refresh
control, or installs pull-to-refresh. The store also rejects such refresh calls,
and saved book rows never display obsolete floor/update badges. Local bookmarks,
reading history, reading-position restoration, catalog pagination and explicit
reader reload/retry continue to work.

## Filester

The public token response can contain a storage UUID with an extension, such as
`example-id.zip`, and the dedicated `https://fsc2.cdn.cr` server. Previously the
parser rejected both, conflating download-address resolution with list parsing.
Accept safe filename suffixes and this observed CDN, retaining traversal,
lookalike-domain, credential, query and server-path rejection. Successful tokens
keep the original filename and escaped token query. Failed resolution now has a
separate localized error.

The site's own `/js/file_dl.js?ver=24` confirms the public token request and URL
construction. A live token response and HEAD request confirmed HTTP 200,
`application/zip`, 236553525 bytes, and byte-range support. No archive contents
were downloaded or added to fixtures. Regression fixtures contain synthetic
identifiers, tokens and filenames only.

## Validation

Core coverage includes archive permission/schema checks, URL validation,
portrait preference, same-day reuse, midnight expiry, delayed upstream rollover,
daylight-saving boundaries, Bookhouse update exclusion and Filester resolution.
Windows checks cover syntax and repository resources, not native type checking.
The macOS device build and tests are the native validation path; no simulator is
used. Glass appearance, scroll tracking and network behavior still require
physical-device acceptance.

## Build 1053 delivery

- Source: `2f4720037d1ee34e280a26338c277a2355069cf9`
- [macOS CI run 36705730055](https://github.com/SyIar/clear-forum-flutter/actions/runs/36705730055): successful.
- Forum Core: 321 tests passed; embedded Tieba Core: 20 tests passed.
- Native iPhone Release build, compiled localization, CJK/Latin cascade,
  repository policy and package verification passed. No simulator was used.
- Delivered IPA: `D:\workspace\sideloadly-setup\ForumLite-0.3.0-1053-unsigned.ipa`
- Size: 51732579 bytes.
- SHA-256: `f7533888623aeaa55036768ee741fa5be912300769455d9d9e8457ea9cf74ce3`
- Downloaded archive CRC, source/run metadata, arm64 executable, bundle identity,
  font/localization resources, and embedded Tieba resources were verified locally.
- Physical appearance, live scroll tracking and complete device downloads remain
  for user acceptance.
