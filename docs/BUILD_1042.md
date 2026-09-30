# Forum Lite 0.3.0 (1042)

## Typography correction

The system font is now the primary face. Source Han Serif Regular and Bold
are CJK fallbacks, rather than the primary fonts for all text. Latin letters,
digits and emoji keep Apple's system faces; Han characters, Japanese kana
and Korean Hangul use the bundled serif. Existing system fallbacks remain
available for characters the bundled fonts cannot cover.

SwiftUI text styles, rich post text and UIKit navigation/search labels share
this policy. Dynamic Type, actual bold faces, link colors, Chinese interface
translations and original post content remain intact. No new font upload is
needed.

## Build and verification

- Source: `4613b5f1dce223c7072de47d9e81612030919ce9` on `main`.
- [Actions run 36680449177](https://github.com/SyIar/clear-forum-flutter/actions/runs/36680449177)
  passed on 2026-09-30, including the generic iPhoneOS arm64 Release build.
- All 268 Swift Core tests and existing media, localization and repository
  checks passed.
- CoreText checks on the macOS builder inspect actual shaped glyph runs in
  both weights: Latin/digits/emoji retain system faces; Han/kana/Hangul select
  the corresponding Source Han Serif face. Mixed paragraphs use both.
- Packaging verifies both registered OTF resources and their license.

## Local delivery

- IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1042-unsigned.ipa`.
- Size: `46,618,394` bytes.
- SHA-256: `a7df3a17fd3035d72d21fe5de5b97e7b2c59ae635068ccec011e3079e81bca0b`.
- The downloaded IPA passed ZIP CRC, CI/source/run metadata, SHA-256,
  version/build, bundle identity, arm64 executable and unsigned-status checks.
- Registered OTFs match the source bytes exactly, and compiled Chinese string
  tables match the translations. Icon, media, license and Photos/Files settings
  are present. The installation-directory copy is byte-identical to the artifact.

No simulator or installation was used. Physical-device acceptance of the
mixed-script appearance remains pending.
