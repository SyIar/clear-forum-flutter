# Filester and Gofile download fixes

## Filester numbered CDN nodes

The public download API returned a successful response with a stored ZIP filename, a token, and `https://fsc3.cdn.cr` as its server. The resolver only allowed `fsc2.cdn.cr`, so it rejected the response before beginning the transfer. A header-only request to the signed file returned HTTP 200, `application/zip`, and a content length of 325,672,882 bytes. The archive itself was not downloaded during this check.

The resolver now accepts the complete `fsc<number>.cdn.cr` hostname family as well as existing Filester subdomains. HTTPS, credentials, ports, root paths, queries, stored-file names, and lookalike-domain checks remain enforced. No signed tokens or user page contents are committed.

## Gofile single-file ownership

The file-list download button used a page-owned temporary transfer. The floating widget only observes global managers, so those downloads were invisible and could be cancelled when the page was released.

Explicit single-file downloads now use a manager-owned Gofile batch containing exactly that file. File and folder selection identities are separate, repeat taps reuse the existing task, and list progress observes the same task as the floating widget. Tapping an active or paused task opens its controls; completed files can be previewed or exported. Validated files are retained in the app's Gofile Downloads directory. Temporary preview transfers remain page-local; torrent entries retain their copy-magnet action.

## Validation

- Local Swift syntax, repository language, localization, icon coverage, Gofile bridge tests and media-script checks passed. Syntax checks do not establish Swift compilation.
- Added Swift regressions for numbered Filester CDN resolution, lookalike rejection, single-file selection, and separate file/folder identities.
- Device compilation and Swift test results will be recorded after CI completes. No simulator is used.

Physical-device acceptance: download the Filester sample; start one Gofile video download, leave the list, open the floating widget, and verify progress and the saved file. Reopen the file list and verify the same task is shown.
