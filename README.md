# simp lite

A personal iOS forum reader built with SwiftUI, UIKit, WebKit and AVKit. The production target is `native/SimpLite.xcodeproj`, generated from `native/project.yml`; it does not load Flutter. A visible WKWebView handles sign-in and pages requiring browser interaction.

## Scope

- Forum and thread lists, compact pinned notices, paged posts, quotes and spoilers.
- A local bookmark library, an add-URL action, and the ten most recently read forums or threads.
- Thread history keeps the latest visited page. Bookmarks preserve the exact page URL and post fragment.
- System light/dark appearance, system font, compact layout and a translucent page bar.
- On-device WebKit session. No credentials in source control, analytics or a remote proxy.
- GET-only HTML requests restricted to known read routes on the configured origin.
- A visible browser fallback with a user-triggered **Read page** action.
- Ads and active page scripts are excluded from the native reading tree. Inline promotions may still need site-specific rules.
- Images and available video thumbnails load automatically, with loading and error states and without forum cookies. Adjacent images adapt to the available width; tall previews are capped and can be opened for zooming.
- Video cards place the thumbnail on the left and a separate framed **Tap to play** action on the right. Media playback starts only after that action. Replies, messages, search forms and push notifications are not native features in this version.

Media cards open an iOS player. Direct HTTPS media uses AVKit. Turbo links use a bounded, isolated provider request followed by a fresh signed-stream request. Other embedded pages initialize behind a native loading screen, where a media observer can hand an available HTTPS stream to AVKit. Failure shows Retry and Details; only an explicit Web player action exposes the provider page. Details contains redacted stages, HTTP/MIME metadata, and native error codes. Signed links stay in memory, never in reports, bookmarks or history. Provider compatibility requires device verification; this is not a guarantee that every embed plays or that every ad is removed. See [media behavior and limits](docs/EMBEDDED_MEDIA.md).

The iOS display name and generated icon are updated; the bundle identifier remains `dev.sylar.clearforum` so a correctly re-signed update can replace the existing installation. See [branding](docs/BRANDING.md) for the icon source and generation prompt.

The sample mode is clearly marked and contains only invented, non-account content. A successful build is not evidence that a real account session works on a phone.

## Run and build

Use Xcode 26 or newer on macOS. Run `swift test --package-path native`, generate the project with `xcodegen generate --spec native/project.yml`, then build the `SimpLite` scheme. The `ios-native.yml` workflow builds and validates an unsigned device IPA. See [native migration](docs/SWIFT_MIGRATION.md) for the delivered build and device acceptance status.

The old Flutter source and its workflows remain for comparison and rollback. They are not dependencies of the native target. The old web sample preview is still available through the Flutter toolchain.

The manually triggered GitHub Actions workflow builds an unsigned device IPA on a standard macOS runner. Apple credentials are never used in CI. Sign the IPA locally before installing it.

See [implementation and validation](docs/IMPLEMENTATION.md) for the current limits and acceptance checklist.
