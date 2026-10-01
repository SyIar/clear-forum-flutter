# ChunUI integration

## Delivered build

- Version: `0.3.0 (1057)`.
- Source: `b02bb34ee81d80042aac55fb9a6f2ce86bf1779c`.
- [Successful device build](https://github.com/SyIar/clear-forum-flutter/actions/runs/36806015845): 323 Forum Core tests and 20 Tieba Core tests passed; media/bridge/resource checks passed; unsigned arm64 Release IPA packaged.
- Local IPA: `D:\workspace\sideloadly-setup\ForumLite-0.3.0-1057-unsigned.ipa` (55,957,705 bytes).
- SHA-256: `e15bd81671ec167206ad25c20e63492a7cac09625a26fe040fabde4c9652c957`.
- Downloaded archive CRC, build/source metadata, arm64 executable/framework, Pika mapping/assets, ChunUI Metal library/assets, fonts, Chinese tables and licenses verified. Windows/CI text resources were compared with newline normalization where appropriate.
- Physical-device visual and gesture acceptance remains with the user; no simulator was run.

## Scope

- ChunUI is pinned to `b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb`; Pow is pinned to `1.0.6`.
- `ForumUI.framework` owns the dependency, theme and presentation state once. The application and embedded Tieba feature share that framework.
- App-owned icons use 82 Pika SVG assets, mapped from 98 semantic identifiers. The matching upstream assets are preserved as template vectors for UIKit and SwiftUI. System-owned AVKit, Safari, keyboard and navigation chrome keep their system behavior.
- Cards, tags, compact links and primary file-download actions use ChunUI surfaces with a system-blue accent. Existing forum-content font rules remain in the owning modules; application UI uses system fonts.
- The module selector uses ChunUI glass and private variable blur at the top and bottom. Reduce Transparency switches the blur to a gradient; the private class/selector is checked before construction.
- Confirmation, error and information dialogs use ChunUI bottom cards. Normal actions use its outline role because the upstream default accent can produce white text on a white button in dark mode.
- Bookmarks, blocked users, page selection, pinned threads, copy-text, diagnostics, download management and simple Tieba input prompts use ChunUI's native sheet presenter. Forum data environments and dismissal callbacks remain owned by the source screen. Login browsers, media viewers, document/Photos interfaces and Tieba editing sheets retain their existing presentation lifecycles.
- Simp bookmark rows get one local blue sweep when a known maximum floor count increases and unread updates exist. This uses ChunUI's shader within that row, not the library's fullscreen window effect. Offscreen/initial rows and Recent Reading do not fire the effect. Reduce Motion disables it.

## Validation

`scripts/check_design_system.py` verifies Pika asset coverage, absence of app-owned SF Symbol calls and single dependency ownership. `scripts/package_native.py` verifies the shared framework, compiled icons, mapping, ChunUI resource bundle and bundled licenses in the device IPA. Syntax checks on Windows do not replace the macOS device build.

Physical-device checks: light/dark dialogs, dismiss by close/backdrop/swipe, reopen the same prompt, bookmark save, page selection, pinned-thread selection, selecting text, download manager dismissal, and automatic bookmark updates. No simulator run is part of this delivery.

## Sources and licenses

- [ChunUI source and component overview](https://github.com/liseami/ChunUI/tree/b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb)
- [Pika icon wrapper](https://github.com/liseami/ChunUI/blob/b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb/Sources/ChunUI/Icons/PikaIcon.swift)
- [Native sheet implementation](https://github.com/liseami/ChunUI/blob/b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb/Sources/ChunUI/Components/CCNativeSheet.swift)
- [Progressive blur implementation](https://github.com/liseami/ChunUI/blob/b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb/Sources/ChunUI/Core/Blur.swift)
- Unmodified MIT licenses are bundled as `ChunUI-LICENSE.md` and `Pow-LICENSE.md`.

The private blur is included for the user's explicitly requested personal-use build. Device behavior remains subject to iOS changes; this integration is not an App Store compatibility claim.
