# Native Liquid Glass trial

## Scope and decision

The forum/thread bottom pager uses `real_liquid_glass` **0.3.0**, pinned in
`pubspec.yaml` and `pubspec.lock`. Its MIT-licensed published source was inspected
before integration. It has only the Flutter SDK as a runtime Dart dependency.

Compared with `liquid_glass_native` 0.3.1, which supplies a larger SwiftUI control
catalog and shader implementation, the small surface primitive fits the existing
pager without replacing its navigation state or media code. No local Metal shader
or custom native bridge is needed for this trial.

On iOS 26+, the package creates `UIVisualEffectView` with
`UIGlassEffect(style: .regular)` and native capsule corner configuration through
`UiKitView`. Older iOS uses `UIBlurEffect(.systemMaterial)`; Windows/web uses a
Flutter blur fallback. The deployment target stays iOS 15. This is a native
**material surface**; icons, text, individual actions and accessibility labels
remain Flutter widgets.

## Composition and interaction

- One passive native surface per visible reader page; no native view per floor.
- No native `onTap`, eager gesture recognizer, or full-page platform-view overlay.
  The glass background uses transparent hit testing; each Flutter IconButton
  keeps its own enabled state, callback, tooltip and minimum touch target.
- The pager floats above the ListView, so content can scroll behind the material.
  Bottom padding accounts for the pager height and system safe area. Large text
  increases the height; the final floor can scroll completely above the bar.
- No Flutter blur, opacity layer, shader mask or clipping wrapper is applied over
  the iOS glass surface. There is no opaque custom background beneath it.
- App brightness is passed consistently through CupertinoTheme and MediaQuery.
  The package updates the native view when brightness changes. UIKit renders the
  material and applies its system appearance behavior; no private API is used.
- The trial intentionally does not add touch-shimmer animation or merging shapes:
  the surface is passive and there is only one capsule. These are separate native
  interaction features, not guaranteed by merely choosing the material.

The publisher advertises iOS 27 transparency controls. This work confirms the
public iOS 26 `UIGlassEffect` code path, not every claimed iOS 27 setting. Actual
refraction, Reduce Transparency, Increase Contrast, frame rate and touch behavior
need validation on the user's iPhone. A Windows/web screenshot cannot prove them.

## Native player toolbar

The player remains a native `UINavigationController` and `MediaPlayerController`.
Its leading item is now the SF Symbol `chevron.backward`, with the accessibility
label `Back to thread`. Its only trailing item is `arrow.clockwise`, labeled
`Refresh video`. Both are standard `.plain` UIBarButtonItems: UIKit supplies their
Liquid Glass background and interaction on iOS 26+. Only the symbol tint is set
to the adaptive `.label` color. No custom navigation background, manual blur,
extra platform view or competing glass layer is introduced.

The former `Done` item dismissed the modal player. The new back item calls the
same `close()` action, including cancellation, player cleanup and completion.
Refresh still calls `reload()`. The `Details` item and diagnostic sheet are
removed, including their copy action; error hints now point to refresh instead.
The bounded internal diagnostic collector and playback pipelines are unchanged.

## Validation

Automated coverage checks button callbacks and disabled states, a narrow dark
reader at 2x text with safe-area clearance, scrolling back up, native platform-view
creation parameters, passive hit testing, theme updates and disposal. Mocked
platform-view tests validate the bridge contract, not UIKit rendering.

The macOS Actions workflow compiles the CocoaPods plugin using Xcode 26.3 and
packages an unsigned device IPA. Runtime visual acceptance remains separate from
successful compilation. Existing playback, poster, image-layout and compact-link
regressions remain in the suite.

Local checks on 2026-09-28 passed: Dart analysis, all 65 Flutter tests, media
observer checks, repository policy scan (104 files), and diff whitespace checks.
The web release build and light/dark fallback preview also passed. The preview
does not show native UIKit optical rendering.
Build 11 was cancelled when the user added the player toolbar changes, before
delivery. The next build contains both the reader pager and player toolbar.

The user reports manually installing the previous IPA and accepting non-Turbo
playback and the other page changes. The installed build number was not read.
That acceptance does not yet cover the new Liquid Glass surfaces.

## Build 12 delivery

[Actions 36416967331](https://github.com/SyIar/clear-forum-flutter/actions/runs/36416967331)
completed successfully, including all 65 Flutter tests, Dart analysis, repository
checks, web release, native policy/resolver checks, Xcode 26.3 compilation and IPA
verification. Source: `40953f9d44b4dd8954695fd7f6c6b45ee6af3ac7`.

- App: `simpcity ultimate` 0.1.0 (12), `dev.sylar.clearforum`.
- IPA: `D:\workspace\sideloadly-setup\SimpcityUltimate-0.1.0-12-unsigned.ipa`.
- Size: 9,773,475 bytes.
- SHA-256: `3a15fb2fa35cdc07a40d192761f5f507448355b22ad3f7406b70617a17a940d7`.
- Downloaded ZIP, required components, identity, device platform, build number,
  source/run metadata and checksum were verified. The install-directory copy was
  checked against the same checksum.
- Unsigned artifact, for the existing Sideloadly signing workflow. Build 12 has
  not been installed or visually accepted on the iPhone in this turn.

## Sources

- [Apple UIGlassEffect](https://developer.apple.com/documentation/uikit/uiglasseffect)
- [Apple: UIKit and the new design](https://developer.apple.com/videos/play/wwdc2025/284/)
- [Apple navigation bar](https://developer.apple.com/documentation/uikit/uinavigationbar)
- [Apple navigation controller](https://developer.apple.com/documentation/uikit/uinavigationcontroller)
- [Flutter iOS platform views](https://docs.flutter.dev/platform-integration/ios/platform-views)
- [real_liquid_glass package](https://pub.dev/packages/real_liquid_glass)
- [real_liquid_glass source](https://github.com/kiddo4/real_liquid_glass)
- [liquid_glass_native comparison](https://pub.dev/packages/liquid_glass_native)
