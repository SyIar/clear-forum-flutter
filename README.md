# simpcity ultimate

A personal iOS forum reader built with Flutter. Reading pages use native Flutter widgets; a visible WKWebView handles sign-in and pages requiring browser interaction.

## Scope

- Forum and thread lists, compact pinned notices, paged posts, quotes and spoilers.
- A local bookmark library, an add-URL action, and the ten most recently read forums or threads.
- Thread history keeps the latest visited page. Bookmarks preserve the exact page URL and post fragment.
- System light/dark appearance, system font, compact layout and a translucent page bar.
- On-device WebKit session. No credentials in Dart, source control, analytics or a remote proxy.
- GET-only HTML requests restricted to known read routes on the configured origin.
- A visible browser fallback with a user-triggered **Read page** action.
- Ads and active page scripts are excluded from the native reading tree. Inline promotions may still need site-specific rules.
- Images and available video thumbnails load automatically, with loading and error states and without forum cookies. Adjacent images adapt to the available width; tall previews are capped and can be opened for zooming.
- Video cards place the thumbnail on the left and a separate framed **Tap to play** action on the right. Media playback starts only after that action. Replies, messages, search forms and push notifications are not native features in this version.

Media cards open an iOS player. Direct HTTPS media uses AVKit. Embedded pages initialize in an isolated, visible WKWebView; a media observer can hand an available HTTPS stream to AVKit. A Web player action remains available when handoff fails. Signed links are kept in memory, never in bookmarks or history. Provider compatibility requires device verification; this is not a guarantee that every embed plays or that every ad is removed. See [media behavior and limits](docs/EMBEDDED_MEDIA.md).

The iOS display name and generated icon are updated; the bundle identifier remains `dev.sylar.clearforum` so a correctly re-signed update can replace the existing installation. See [branding](docs/BRANDING.md) for the icon source and generation prompt.

The sample mode is clearly marked and contains only invented, non-account content. A successful build is not evidence that a real account session works on a phone.

## Run and build

Use Flutter 3.47.5. Run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build web` for shared UI checks. The web build is a sample preview; live sessions run on iOS only.

The manually triggered GitHub Actions workflow builds an unsigned device IPA on a standard macOS runner. Apple credentials are never used in CI. Sign the IPA locally before installing it.

See [implementation and validation](docs/IMPLEMENTATION.md) for the current limits and acceptance checklist.
