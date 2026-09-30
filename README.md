# Forum Lite

A personal iOS forum reader built with SwiftUI, UIKit, WebKit and AVKit. The production target is `native/ForumLite.xcodeproj`, generated from `native/project.yml`; it does not load Flutter. A visible WKWebView handles sign-in and pages requiring browser interaction.

## Two forums, one installation

The app opens on a forum selection screen with two vertical logo cards and small domain labels. Each card opens that forum's own home; the native back button returns to forum selection. Each forum has a separate local library, page/image cache, and persistent WebKit session. The bundle identifier stays `dev.sylar.clearforum`, allowing a correctly signed update to replace simp lite. Existing Simp bookmarks, reading history and its default WebKit profile are retained; an independently installed South app has a different sandbox and is not migrated.

The site browser and native reader use the same per-forum WebKit-compatible User-Agent, including after relaunch. The identity is prepared synchronously without a hidden web view, JavaScript or network access. Opening the site browser cancels older reader requests, and returning waits for the shared cookie store before refreshing the reader. See [entry screen and login handoff](docs/ENTRY_AND_LOGIN_HANDOFF.md).

South's parser is a compatibility preview tested against synthetic fixtures. Live South pages and account access have not been validated because browser site-safety policy blocked the target site. This build does not establish real-site compatibility. See [merge details and validation](docs/FORUM_LITE_MERGE.md).

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

The iOS display name and generated icon are updated; the bundle identifier remains `dev.sylar.clearforum` so a correctly re-signed update can replace the existing installation. The app uses a cool-color twelve-point star from `assets/branding/app-icon.png`, resized by `scripts/generate_icons.py`; the SimpCity header remains inside its forum home. Earlier branding is recorded in [branding history](docs/BRANDING.md).

See [September fixes and device acceptance](docs/FIXES_2026_09.md) for the current reader update and validation status.

## Native file hosts

Bunkr, Pixeldrain, Fileditch and Filester links open a native file list. Bunkr file pages expand their associated album, using the complete album metadata rather than the small related-file preview. Known Bunkr aliases share one identity. Filester folder pages are collected sequentially before displaying the complete list; nested folders expand as their batch reaches them.

File-host batches share Gofile's serial transfer slot. A fresh download URL is resolved when each file reaches the front, and responses are checked for HTTP errors, unexpected HTML and incomplete sizes. No forum cookies are sent to these hosts. Rate limits pause the batch, and inaccessible items can be retried or explicitly skipped. Saved files live under **Files → On My iPhone → Forum Lite → File Downloads**. Closing a reader keeps its batch alive; backgrounding pauses it, Continue restarts the current file, and quitting clears unfinished batches while preserving completed files. Each batch is limited to 10,000 entries, 20 folder levels and 8 GB per file.

Torrent entries offer **Copy magnet**, including in Gofile. Only the bounded torrent metadata is fetched temporarily and parsed locally; the file is not added to Downloads, and no BitTorrent payload or PikPak task is started. Batch downloads skip torrents. The original bencoded `info` bytes supply the v1/v2 hash. PikPak's [official iOS FAQ](https://mypikpak.com/en-US/faq) does not offer direct task creation inside its iOS app; paste the copied magnet into a supported client or its web drive yourself.

Provider details were checked against [Pixeldrain's API](https://pixeldrain.com/api), Filester's own public download script, and the [upstream Bunkr integration](https://github.com/mikf/gallery-dl/blob/master/gallery_dl/extractor/bunkr.py). Torrent hashing follows [BEP 3](https://www.bittorrent.org/beps/bep_0003.html) and [BEP 52](https://www.bittorrent.org/beps/bep_0052.html). Site markup and access rules can change; a successful compile or metadata parse does not replace physical-device download acceptance.

The sample mode is clearly marked and contains only invented, non-account content. A successful build is not evidence that a real account session works on a phone.

## Run and build

Use Xcode 26 or newer on macOS. Run `swift test --package-path native`, generate the project with `xcodegen generate --spec native/project.yml`, then build the `ForumLite` scheme. The `ios-native.yml` workflow builds and validates an unsigned device IPA. See [native migration](docs/SWIFT_MIGRATION.md) for the delivered build and device acceptance status.

The old Flutter source and its workflows remain for comparison and rollback. They are not dependencies of the native target. The old web sample preview is still available through the Flutter toolchain.

The manually triggered GitHub Actions workflow builds an unsigned device IPA on a standard macOS runner. Apple credentials are never used in CI. Sign the IPA locally before installing it.

See [implementation and validation](docs/IMPLEMENTATION.md) for the current limits and acceptance checklist.
