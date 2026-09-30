# Forum Lite 0.3.0 (1032)

## Delivery

- [GitHub Actions run 36666136869](https://github.com/SyIar/clear-forum-flutter/actions/runs/36666136869) succeeded on 2026-09-30.
- Source commit: `f32d6eb6986ba0f4c1d1ce6da76acdf2b8cb68bf` on `main`.
- The `fix/forumlite-eighteen-issues` branch, including `0324df7` and review fixes `60763bc`, was fast-forward merged into `main` and pushed. The final source commit adds CI-discovered trailing-slash compatibility fixes.
- Native SwiftUI/UIKit, arm64 iPhoneOS Release, Xcode 26.3. No simulator build or simulator run.
- Display name: `Forum Lite`; bundle ID: `dev.sylar.clearforum`.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1032-unsigned.ipa`.
- Size: `5,139,341` bytes.
- SHA-256: `fb9621b9143b4639a49ec84eee1475644d86bf23eb36ce6cd51c60abb0025279`.
- The adjacent `.ipa.sha256` file records the delivery copy's checksum.

## Included changes

- The eighteen-issue reader update from `0324df7`; see [scope and device acceptance](FIXES_2026_09.md).
- Site browser only unwraps recognized redirect wrappers. Ordinary unread/post links retain their original requests and website navigation semantics.
- Explicit bookmark titles survive metadata refresh and persistence. Automatic titles continue to update. Legacy non-placeholder labels are preserved because old data did not record title provenance; path placeholders with or without a trailing slash remain eligible for resolution.
- The user-supplied twelve-point star master replaces the old icon in all AppIcon slots and existing web assets.
- The non-packaging validation workflow also uses the device SDK.

## Verification

- All 234 Swift Core tests passed, including both-forum bookmark persistence, legacy migration, unread navigation and redirect regressions.
- All 9 Gofile JavaScript cases, media observer checks, Swift media-policy checks and repository policy checks passed.
- Xcode device Release compilation, IPA packaging and artifact upload passed.
- Local checks passed: CI checksum, exact source/run metadata, ZIP CRC, version/build, bundle identity, arm64 executable, icon registration, media resources, dependency notice and Photos/Files settings.
- The bundled 120 px iPhone and 152 px iPad PNGs were decoded from Apple's CgBI format for verification; their RGB pixels exactly match the new source icon assets. The master and all 19 catalog slots were also verified.
- The delivered IPA is byte-identical to the downloaded CI artifact.
- Build 1031 produced no IPA: its tests detected a legacy placeholder comparison affected by Foundation's trailing-slash normalization and a pre-existing search assertion using `URL.path`. Both were corrected before this successful build.
- Existing warnings remain for an old bar-button style, absent AppIntents metadata and iPad orientation declarations.

This is an unsigned IPA for Sideloadly signing. It was not installed during this task. Physical-device acceptance remains pending for the reader's gesture, gallery, continuous paging and live-provider interactions; CI success does not replace those checks.
