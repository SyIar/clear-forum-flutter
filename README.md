# Clear Forum

A personal iOS forum reader built with Flutter. Reading pages use native Flutter widgets; a visible WKWebView handles sign-in and pages requiring browser interaction.

## Scope

- Forum and thread lists, compact pinned notices, paged posts, quotes and spoilers.
- System light/dark appearance, system font, compact layout and a translucent page bar.
- On-device WebKit session. No credentials in Dart, source control, analytics or a remote proxy.
- GET-only HTML requests restricted to known read routes on the configured origin.
- A visible browser fallback with a user-triggered **Read page** action.
- Ads and active page scripts are excluded from the native reading tree. Inline promotions may still need site-specific rules.
- Images load only after a tap, without forum cookies. Video embeds, replies, messages, search forms and push notifications are not native features in this first version.

The sample mode is clearly marked and contains only invented, non-account content. A successful build is not evidence that a real account session works on a phone.

## Run and build

Use Flutter 3.47.5. Run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build web` for shared UI checks. The web build is a sample preview; live sessions run on iOS only.

The manually triggered GitHub Actions workflow builds an unsigned device IPA on a standard macOS runner. Apple credentials are never used in CI. Sign the IPA locally before installing it.

See [implementation and validation](docs/IMPLEMENTATION.md) for the current limits and acceptance checklist.
