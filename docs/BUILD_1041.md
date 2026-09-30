# Forum Lite 0.3.0 (1041)

## Delivery

- [GitHub Actions run 36677611668](https://github.com/SyIar/clear-forum-flutter/actions/runs/36677611668) succeeded on 2026-09-30.
- Source commit: `6c8780128428d5b12d4634e08769e67f30559efe` on `main`.
- Native SwiftUI/UIKit, arm64 iPhoneOS Release, Xcode 26.3.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1041-unsigned.ipa`.
- Size: `46,584,174` bytes.
- SHA-256: `afc8576d161dcad968c086edd20936270b11a7a0d3dd76770e825aa0838c1885`.
- Display name and bundle identity remain `Forum Lite` and `dev.sylar.clearforum`.

## Changes since build 1038

- Copy, play and download actions use matching 44-point targets and symbol weight, so file-list action centers align. Copying remains icon-only with a spinner and completion checkmark.
- The owner-uploaded Source Han Serif Regular and Bold OTF files are bundled, registered and applied to native text, rich post text and navigation labels. Bold/semibold styles use the actual Bold face. Dynamic Type is retained; code, tiny numeric progress indicators, SF Symbols and original website styling keep their appropriate system/original presentation.
- App-owned interface text uses Simplified Chinese: 369 entries cover controls, navigation, counts, download states, error messages, accessibility labels and help. Photos permission text is localized separately.
- Original forum posts, website notices, names, filenames, provider brands and browser pages retain their original content. Localization is applied at the source of app-owned text, not to arbitrary downloaded strings.
- Chinese resources are confined to the two `zh-Hans.lproj` strings files. Source code, identifiers, diagnostics and configuration remain English. Large binary uploads remain the repository owner's responsibility; integration and validation happen afterward.
- XcodeGen development language and generated Info.plist settings both use `zh-Hans`. This follows XcodeGen's [developmentLanguage option](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#options), whose default is English.

## Verification

- All 268 existing Swift Core tests passed. All 9 Gofile JavaScript tests, media observer checks, Swift media-policy checks and repository policy checks passed.
- Localization checks verified resource syntax, key coverage and interpolation placeholders. Foundation loaded Chinese strings and preserved literal percent signs in filenames.
- CoreText loaded both font files and verified PostScript names plus representative Latin/Chinese glyph coverage.
- Device Release compilation, packaging checks and artifact upload passed. Build 1040 compiled successfully but its packaging check caught the generated default-language mismatch; build 1041 fixes that configuration and is the delivery.
- The downloaded IPA passed ZIP CRC, CI checksum, source/run metadata, version/build, bundle identity, arm64 binary, unsigned status, icon/media resources and Photos/Files settings checks.
- Both embedded OTF files match the uploaded sources byte-for-byte. Both compiled Chinese string tables match the source translations. The development language and advertised localization are `zh-Hans`.
- The installation-directory copy is byte-identical to the CI artifact; its adjacent `.ipa.sha256` contains the checksum.

No simulator or installation was performed. The unsigned IPA needs local signing; physical-device acceptance remains pending for Chinese layout, font appearance and action alignment.
