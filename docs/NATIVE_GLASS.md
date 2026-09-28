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
Native compilation and device visual acceptance are still pending at this point.

## Sources

- [Apple UIGlassEffect](https://developer.apple.com/documentation/uikit/uiglasseffect)
- [Apple: adopting Liquid Glass in UIKit](https://developer.apple.com/documentation/uikit/adopting-liquid-glass)
- [Flutter iOS platform views](https://docs.flutter.dev/platform-integration/ios/platform-views)
- [real_liquid_glass package](https://pub.dev/packages/real_liquid_glass)
- [real_liquid_glass source](https://github.com/kiddo4/real_liquid_glass)
- [liquid_glass_native comparison](https://pub.dev/packages/liquid_glass_native)
