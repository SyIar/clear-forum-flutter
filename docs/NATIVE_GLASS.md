# Native Liquid Glass trial

## Current revision: complete native pager

The next revision replaces the iOS passive material plus Flutter controls with
one application-owned platform view in `ios/Runner/NativeGlass.swift`.
A standard `UIToolbar` contains previous/refresh/next `UIBarButtonItem` actions
and a native page label. UIKit supplies the glass and pressed feedback;
enabled state, appearance, accent and page updates cross the method channel.
The existing non-iOS preview remains a Flutter fallback.

Native events are checked again against current Flutter callbacks, so a queued
tap cannot activate a now-disabled action. The view hides under another route or
popup and restores with the reader. It does not install an eager drag recognizer.
The existing floating layout and safe-area clearance remain intact.

The player toolbar and both media pipelines are unchanged. Build 12 remains the
device comparison baseline. The historical trial and research below describe the
previous implementation; their `interactive: false` limitation no longer applies
to this revision's iOS pager. Compilation and device visual acceptance are
separate. No claim of measured frame rate or completed device A/B is made.

Local verification: Dart analysis and all 65 Flutter tests passed, including the
updated native bridge lifecycle/state test and the existing floating-reader
large-text/scrolling test. Cloud device compilation is pending at this entry.

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
- The downloaded artifact is unsigned. On 2026-09-28, after the user's explicit
  USB install request, its checksum and selected build 12 filename were checked.
  Sideloadly used the existing signing account with the device selected as @USB.
  Start reset progress to 0%; the subsequent state showed Done / 100%, confirming
  signing and installation completed. Native glass appearance, launch behavior
  and the updated controls still await the user's on-device acceptance.

## Follow-up comparison on 2026-09-28

The current implementation cannot be called the universally best-looking or
fastest Flutter glass solution. Its material is Apple's native implementation,
but the pager does not yet use native controls and touch feedback end to end.
The player toolbar already uses standard UIKit controls directly. No device A/B
comparison or frame-time measurement has been performed for the alternatives.

### What is native in this app

`GlassPager` sets `interactive: false` and puts Flutter `IconButton` and `Text`
widgets over one native material surface. This deliberately keeps the native
background out of touch handling. It does not provide native glass touch feedback,
native symbol rendering or a complete native toolbar. The package itself supports
interactive surfaces, grouped materials and a native `UITabBar`; these are not
features the current pager uses. A page navigator should not be recast as a tab bar
merely to use that component.

Changing `interactive` alone would not turn the overlaid Flutter buttons into
native controls. It also changes the package's platform-view hit testing from
transparent to opaque. Interaction ownership needs to be designed and verified
alongside the visual change.

### Alternatives and evidence

| Option reviewed | Evidence | Fit for this app |
| --- | --- | --- |
| `real_liquid_glass` 0.3.0, current | Published Dart and Swift sources confirm `UIGlassEffect`, optional interaction, group support and a native tab bar. | A small dependency for the present surface. Its material is not intrinsically inferior to another wrapper around Apple's APIs. |
| `liquid_glass_native` 0.3.1 | Published source confirms SwiftUI glass buttons and toolbar. Its icon button enables `.interactive()` conditionally. `GlassToolbarView.swift` uses regular glass without that modifier; the toolbar bridge passes icons/colors, but no disabled flag or page label. | A larger control catalog, not a drop-in pager upgrade. Supporting the current page number and unavailable previous/next actions would still require adaptation. Version 0.3.1 changes documentation only, per its changelog. |
| `native_liquid_glass` 0.3.1 | Author documentation describes complete UIKit controls, route/overlay workarounds, composition costs, and empty non-Apple fallbacks. Its source was not fully audited in this comparison. | Worth evaluating if adopting a broader native control suite, but not evidence that switching improves this single pager. |
| `cupertino_native` 0.1.1 | Serverpod's published README explicitly describes the package as a proof of concept and lists integration work still needed. Its source was not fully audited here. | Native controls are relevant, but the publisher's own scope does not support calling it a universally more mature replacement. |
| `liquid_glass_renderer` 0.2.0-dev.4 | Author documentation describes custom Flutter rendering, interaction effects, Impeller requirements and experimental performance limitations. | Useful for custom visual design; not the first choice when the objective is the actual iOS material and standard control behavior. |

The source inspection for `liquid_glass_native` used the pub.dev 0.3.1 release
archive, rather than assuming its README applies equally to every widget. A wider
catalog does not mean every control implements the same interaction, accessibility
or fallback behavior.

### Recommendation and limits

1. Retain the player's standard `UINavigationController` / `UIBarButtonItem`
   implementation. Apple supplies its glass presentation and control behavior.
2. If richer pager interaction is the next priority, prototype the entire pager
   as one native control surface, including its buttons, page label, enabled state
   and callbacks. A narrowly scoped UIKit/SwiftUI bridge is a reasonable candidate
   given the existing native integration; it also creates code we must maintain.
   Compare it on the same device before replacing the current pager.
3. Keep regular glass for text/navigation readability. Apple recommends glass for
   floating navigation and controls, rather than repeated content rows or stacked
   glass layers. Keep forum floors as readable content surfaces.
4. Check scrolling over detailed images, light/dark appearance, disabled buttons,
   large text, reduced-transparency/motion settings, route transitions and touch
   behavior. Use device profile/release measurements for performance claims.

These recommendations are an inference from the current code and the cited
platform/package sources. Flutter's official documentation confirms platform-view
composition and performance tradeoffs; it does not establish that a particular
package is fastest. A web fallback preview and compilation success cannot settle
native visual quality. This follow-up changes documentation only.

## Sources

- [Apple UIGlassEffect](https://developer.apple.com/documentation/uikit/uiglasseffect)
- [Apple: UIKit and the new design](https://developer.apple.com/videos/play/wwdc2025/284/)
- [Apple navigation bar](https://developer.apple.com/documentation/uikit/uinavigationbar)
- [Apple navigation controller](https://developer.apple.com/documentation/uikit/uinavigationcontroller)
- [Flutter iOS platform views](https://docs.flutter.dev/platform-integration/ios/platform-views)
- [real_liquid_glass package](https://pub.dev/packages/real_liquid_glass)
- [real_liquid_glass source](https://github.com/kiddo4/real_liquid_glass)
- [liquid_glass_native comparison](https://pub.dev/packages/liquid_glass_native)
- [liquid_glass_native changelog](https://pub.dev/packages/liquid_glass_native/changelog)
- [liquid_glass_native published source archive](https://pub.dev/api/archives/liquid_glass_native-0.3.1.tar.gz)
- [native_liquid_glass and composition caveats](https://pub.dev/packages/native_liquid_glass)
- [cupertino_native and proof-of-concept scope](https://pub.dev/packages/cupertino_native)
- [liquid_glass_renderer and limitations](https://pub.dev/packages/liquid_glass_renderer)
- [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Apple UIGlassEffect interaction](https://developer.apple.com/documentation/uikit/uiglasseffect/isinteractive)
