# Forum Lite 0.3.0 (1034)

## Delivery

- [GitHub Actions run 36669825063](https://github.com/SyIar/clear-forum-flutter/actions/runs/36669825063) succeeded on 2026-09-30.
- Source commit: `62cc928cf746c34365d9f18a7a004b5dde1483bb` on `main`.
- Native SwiftUI/UIKit, arm64 iPhoneOS Release, Xcode 26.3. No simulator build or simulator run.
- Display name: `Forum Lite`; bundle ID: `dev.sylar.clearforum`.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1034-unsigned.ipa`.
- Size: `5,354,960` bytes.
- SHA-256: `cc9b9132b5abce03069070f6b8982c3e25e931b7815ce519d837c98500b16a6d`.
- The adjacent `.ipa.sha256` file records the delivery copy's checksum.

## Included changes

- Native file lists for Bunkr, Pixeldrain, Fileditch and Filester, with individual and serial batch downloads integrated into the global download manager.
- Bunkr single-file pages expand their associated complete album. Known domain aliases share one identity. Album script metadata is parsed as data, never executed.
- Filester collects paged folders sequentially; batches discover nested folders in order. File names are sanitized and collisions receive unique suffixes.
- Provider metadata reads run off the main actor. Download URLs are resolved when a file reaches the shared serial transfer slot. Error pages, incomplete bodies and rate limits are surfaced instead of being saved as successful files.
- Torrent entries show **Copy magnet**, including in Gofile. The action temporarily reads bounded torrent metadata and hashes its original bencoded `info` bytes locally. It never saves the torrent in Downloads, starts a BitTorrent payload transfer, launches PikPak or creates a cloud task. Batch downloads skip torrents.

## Verification and limits

- All 255 Swift Core tests passed, including complete album parsing, alias matching, folder pagination, serial planning, filename collisions, false metadata inside filenames, download-response validation and v1/v2 torrent hashes.
- All 9 Gofile JavaScript tests, media observer checks, Swift media-policy checks and repository policy checks passed.
- Xcode device Release compilation, IPA packaging and artifact upload passed.
- Local package checks passed: CI checksum, exact source/run metadata, ZIP CRC, version/build, bundle identity, arm64 executable, unsigned status, icon registration, media resources, dependency notice and Photos/Files settings. The delivery copy is byte-identical to the CI artifact.
- Tests use synthetic ordinary fixtures. Provider documentation, public scripts and selected page metadata informed the implementation; real media transfers and iPhone clipboard behavior were not accepted on a physical device during this task.
- Leaving a viewer inside the app keeps queued downloads alive. Backgrounding pauses file-host batches; Continue restarts the current file. Unfinished batches do not survive app termination, while completed files remain under **Files > On My iPhone > Forum Lite > File Downloads**. This change does not claim persistent background transfers or byte-range resume.
- Website access restrictions, passwords, challenges and rate limits are not bypassed. Unsupported pages retain an explicit website fallback.
- Build 1033 also passed, but was superseded by final metadata responsiveness and parser fixes in this delivery.

The IPA requires local signing before installation. No installation was started during this task. Device acceptance should cover opening each host, Bunkr file-to-album expansion, leaving and reopening an active batch, saved file previews, and copying a magnet into the user's chosen client.
