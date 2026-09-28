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
- Images load only after a tap, without forum cookies. Video embeds, replies, messages, search forms and push notifications are not native features in this first version.

Embedded frames have inert host-labelled placeholders rather than disappearing from posts. They do not execute page scripts or resolve media URLs. Native embedded-video playback remains unsupported.

The iOS display name and generated icon are updated; the bundle identifier remains `dev.sylar.clearforum` so a correctly re-signed update can replace the existing installation. See [branding](docs/BRANDING.md) for the icon source and generation prompt.

The sample mode is clearly marked and contains only invented, non-account content. A successful build is not evidence that a real account session works on a phone.

## Run and build

Use Flutter 3.47.5. Run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build web` for shared UI checks. The web build is a sample preview; live sessions run on iOS only.

The manually triggered GitHub Actions workflow builds an unsigned device IPA on a standard macOS runner. Apple credentials are never used in CI. Sign the IPA locally before installing it.

See [implementation and validation](docs/IMPLEMENTATION.md) for the current limits and acceptance checklist.
