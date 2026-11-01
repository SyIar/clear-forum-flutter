# Forum Tablet

Android tablet adaptation of Forum Lite, maintained separately from the production iOS application.

## Applications

| Flavor | Application ID | Entry point |
| --- | --- | --- |
| `tieba` | `dev.sylar.tablet.tieba` | Tieba home, account and forum APIs |
| `simp` | `dev.sylar.tablet.simp` | Simp forums |
| `south` | `dev.sylar.tablet.south` | South forums |
| `bookhouse` | `dev.sylar.tablet.bookhouse` | Bookhouse catalog and followed books |

There is deliberately no downloader flavor. Each package has its own download queue, browser cookie store, preferences, chapter cache and private file directory. Clearing or uninstalling one application does not clear another application. Uninstalling an application removes its private downloads; export files first when needed.

## Tablet layout

- At 600 logical pixels and above, directory/search results and the selected reader share a two-pane layout.
- The OPPO OPD2515 at 1680 × 2520 and density 420 provides 640 × 960 logical pixels in portrait, and 960 × 640 in landscape. Both layouts split.
- A navigation rail appears at 840 logical pixels. Narrow and split-screen windows use bottom navigation and one reading pane.
- Reader and directory retain separate scroll controllers. Dialogs and drawers have bounded widths. The Android appearance uses Material 3 rather than the iOS glass layers.

## Downloads

An Android foreground data-sync service owns serial transfers independently of Flutter navigation. Records and partial files survive process loss; interrupted transfers become resumable paused records when the service restarts. Resume validates Content-Range and ETag/Last-Modified before appending. Credentials are forwarded only to the original transfer host and scheme. HTML/JSON error pages cannot be saved as successful downloads.

The service obeys Android foreground-service limits; a system timeout pauses the queue. This is not an unlimited background execution exemption. Notification permission is requested when adding a download. Export uses a scoped FileProvider.

Supported link resolvers: direct HTTP(S) files, South attachments, Filester files/folders, Pixeldrain files/lists, Bunkr files/albums, and Gofile content observed from its website. Gofile folders spanning multiple API result pages currently require the website. Host formats can change independently of the app.

The local library sorts by file arrival/completion time, collapses chains of single directories, previews images/videos with swipe navigation, provides storage analysis and explicit file/folder deletion, and exports to other Android apps.

## Bookhouse

List titles extract literary authors and tags from localized parsing rules. Followed books use the first seven title characters for search and match literary authors, without requiring the same uploader. Main chapters and extras share one record. Successful refreshes have a one-hour cooldown; failures remain retryable. Reading preloads the next linked chapter near the end. Read pages cache automatically, and chapter caching continues after closing its drawer. A pending cache plan resumes when reopening the followed book.

## Verification and builds

Android builds run only in `.github/workflows/android-tablet.yml`. Do not invoke Gradle or `flutter build apk` locally under the user's environment constraints.

Allowed local checks (no Gradle):

```text
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

CI emits four unsigned ARM64 release APKs. Personal signing keys remain on the user's workstation and must never be committed or uploaded. Install signed artifacts with `adb install -r` to preserve application data.

Android tooling is pinned to AGP 8.13.2, Gradle 8.14.6 and Kotlin 2.3.20. The stable InAppWebView plugin still uses a ProGuard default removed in AGP 9. Flutter 3.47 requires Gradle 8.14 or newer. This combination preserves the plugin without modifying the shared dependency cache. See the [AGP compatibility table](https://developer.android.com/build/releases/agp-8-13-0-release-notes).

## Sources and localization

- Shared reader basis: `SyIar/clear-forum-flutter`, local deployed revision `6ffc1738757f5f536691fafd5f32cd613f365d12`.
- `packages/tieba`: vendored Dart sources from `SyIar/tieba-lite-flutter`, revision `ab3926ea07e39ca6f44f2d4d79c53919ba5cefbd`, under its retained GPL license. Android theme, adaptive navigation, and download hooks are local modifications. Protobuf generated sources retain their notices.
- Native iOS sources are references for protocol and parser behavior, not a binary dependency. This Android application is not an execution wrapper around Swift.
- The user explicitly authorized dedicated Chinese resource files for these four personal apps on 2026-11-01. Resources live in `assets/l10n`, Android `res/values-zh`, Tieba `lib/l10n`, and localized test fixtures. General source code remains English. No LEO credentials or encoded-Chinese workaround is introduced.

Reference implementation guidance: [Flutter adaptive layouts](https://docs.flutter.dev/ui/adaptive-responsive/best-practices), [Flutter Android flavors](https://docs.flutter.dev/deployment/flavors), [Android foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types).
