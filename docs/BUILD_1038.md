# Forum Lite 0.3.0 (1038)

## Delivery

- [GitHub Actions run 36671488679](https://github.com/SyIar/clear-forum-flutter/actions/runs/36671488679) succeeded on 2026-09-30.
- Source commit: `94951f6dce58fa6440998017978ab13d20a9d0c5` on `main`.
- Native SwiftUI/UIKit, arm64 iPhoneOS Release, Xcode 26.3. No simulator build or simulator run.
- Local unsigned IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1038-unsigned.ipa`.
- Size: `5,377,627` bytes.
- SHA-256: `2b8cf425980378ec7f971866ccb81a38c5ba82d6ff31046bb178205d1985e3ec`.
- Display name and bundle identity remain `Forum Lite` and `dev.sylar.clearforum`.

## Changes since build 1034

- File-host recognition supports final domain-suffix variants for Filester, Bunkr/Bunkrr, Pixeldrain and Fileditchfiles, plus `pixeldra.in`. Supported route checks and exact brand-label matching remain required. Filester/Pixeldrain API calls and generated child links preserve the selected origin. Matching aliases share one download identity.
- Mirror metadata redirects remain within the selected provider. Pixeldrain/Fileditch file redirects may change mirror hosts only while preserving the resource path. Forum cookies and credentials are not sent to file hosts. Recognizing a brand-shaped hostname does not verify ownership of that hostname.
- File sizes appear below file names. Fileditch reads its public status API without fetching the file body. Filester reads its detail-page size label. Rounded labels are for display only and do not become exact expected download sizes. Unknown sizes show **Size unknown**.
- The summary contains one horizontal row: centered **Download all** button on the left and item count on the right. Torrent-only lists retain their copy action and do not offer a misleading batch download button.
- External text links use the same compact chip even when mixed with styled paragraph text. Provider prefixes include `bunkr##`, `gofile##`, `filester##` and `fileditch##`; other sites use their hostname. Raw addresses show a short path component rather than the entire URL. Destinations, internal links, image previews and inline emoticons are preserved.
- Magnet copying is icon-only: copy icon, loading spinner, then checkmark in a fixed 44-point target. Accessibility names remain available without visible Copy magnet/Copied text.
- Filester file titles now come from `#fileTitle`; folder titles come from `.folder-title`/`#folderTitle`. The first document `h1` was the site branding heading and incorrectly became the filename, MIME inference input and download name. This is fixed for both file and folder pages, including Unicode filenames.

## Verification

- All 268 Swift Core tests passed, including mirror routing, redirects, exact versus rounded size metadata, inline external-link presentation, original destination preservation, and Filester branding/content title separation.
- All 9 Gofile JavaScript tests, media observer checks, Swift media-policy checks and repository policy checks passed.
- Device Release compilation, IPA packaging and artifact upload passed.
- Local verification passed for the CI checksum, exact source/run metadata, ZIP CRC, version/build, bundle identity, arm64 executable, unsigned status, icon/media resources, dependency notice and Photos/Files settings.
- The delivery copy is byte-identical to the CI artifact; the adjacent `.ipa.sha256` contains its checksum.
- Build 1035 passed but predates the follow-up changes. Builds 1036 and 1037 were deliberately cancelled after newer requirements arrived; they are not the delivery.

Domain and metadata behavior was checked against the [Filester mirror list](https://filester.me/proxy), Filester's own page markup and public script, [Pixeldrain mirror documentation](https://docs.pixeldrain.com/questions_and_answers/), and [Fileditch status API documentation](https://new.fileditch.com/api.html). Tests use synthetic ordinary content; supplied forum media was not downloaded for verification.

The IPA needs local signing before installation. No installation or simulator validation was performed. Physical-device acceptance remains pending for the final layout, actual mirror downloads and copy-icon interaction. Download lifecycle limits remain as documented in [build 1034](BUILD_1034.md).
