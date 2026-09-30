# Tieba native module and Bookhouse catalog update

## Implementation

Tieba Lite is the fourth module on the Forum Lite selection screen. The three
existing web readers retain their libraries and session stores. Each Tieba tab
has a native navigation stack; the leading back button at its root returns to
the forum selection screen. Deeper screens retain ordinary navigation back.

The SwiftUI/UIKit implementation is imported from SyIar/tieba-lite-flutter,
commit ab3926ea07e39ca6f44f2d4d79c53919ba5cefbd. It includes browsing, forum
feeds, thread replies, account switching, search, profiles, posting, settings,
drafts, history, and existing seamless pagination/reading-position fixes.
The standalone project is not modified.

TiebaFeature.framework provides the view/session boundary. Its resources use
the framework bundle, and the host owns the two shared mixed-script fonts.
Tieba's account Keychain service, preference/library keys, ephemeral browser
cookies, image cache, and draft directory remain separate from other modules.
No old app-container or account data is copied. Users sign in again inside the
integrated module. The old app's alternate-icon picker is removed because
Forum Lite owns the application icon.

Protocol definitions and the pinned SwiftProtobuf generator are included under
native/Tieba. CI generates the codecs, tests both Core packages, and compiles
the native iPhone application. No simulator is launched. Packaging checks the
framework binary, Chinese strings, emoticon artwork, and notices.

The integrated distribution includes the GPL v3 license and corresponding
source; upstream notices are retained in the repository and in Tieba settings.
Dependency license text is copied from the exact resolved SwiftProtobuf source.

## Bookhouse catalog

BookhouseTitlePresentation transforms only row presentation. It extracts the
author from the observed 作者：…『 pattern (also accepting an ASCII colon), and
displays 『…』 categories as separate chips. It keeps the posting account as
fallback. Author and timestamp share one line. The original model, novel detail
title, posting author, and body are preserved.

## Validation

Local source/resource checks and device CI results are recorded after building.
Physical-device acceptance should cover module selection/back navigation,
Tieba login and account switching, forum-to-thread return position, posting
drafts, Chinese/Latin typography, and Bookhouse title/author/category rows.

## Verified delivery

- Source: 6666d1a8e9323d0b1d6b2a65609b482cf268fc12.
- GitHub Actions: https://github.com/SyIar/clear-forum-flutter/actions/runs/36699144554.
- Forum Core: 293 tests passed. Tieba Core: 20 tests passed.
- Apple Swift syntax checks, native iPhone Release build, and packaging passed.
- Build: Forum Lite 0.3.0 (1049), unsigned arm64 IPA, 51,644,511 bytes.
- SHA-256: 919d65f89113f70fbebac26cc57d9fd2cf35c32c60415867e81f80e1de1f2d7f.
- Delivery: D:/workspace/sideloadly-setup/ForumLite-0.3.0-1049-unsigned.ipa.
- Downloaded archive CRC, version/source metadata, fonts, framework, localization,
  all 60 emoticon files, and notices verified locally. Text comparisons normalize
  Git's Windows CRLF versus CI LF line endings.
- No simulator testing performed; physical-device acceptance remains with the user.
