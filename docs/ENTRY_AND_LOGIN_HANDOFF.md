# Forum entry and login handoff

## Approved interface

- App launch opens the forum selector instead of the last selected forum.
- Two vertical cards show the SimpCity website banner and the approved redrawn Southplus wordmark. Only `simpcity.cr` and `south-plus.net` appear as labels.
- Each card pushes its forum home into the same native `NavigationStack`. The system back button and interactive back gesture return to the selector.
- Bookmarks, recent reading, thread updates and the refresh button remain on the corresponding forum home. Reader Home returns to that forum home.
- The selector has no app name, forum-name heading or segmented picker. The app display name remains `forum lite`.

## Report and implementation evidence

The user reported that South was signed in inside the app's browser, but returned to a signed-out reader. The browser and reader already shared South's persistent `WKWebsiteDataStore`; their HTTP identities did not match. The browser used WebKit's default User-Agent, while reader requests sent `ForumLite/0.3`.

The public [PHPWind 8.7 source mirror](https://github.com/old-blueday/phpwind/blob/master/upload/require/common.php) includes `HTTP_USER_AGENT` in `PwdCode`. This is a concrete upstream mechanism consistent with the reported failure. South's deployed version and account response have not been inspected, so this is not a claim of real-site verification.

The reader now uses the same WebKit-derived User-Agent as the site browser. Each forum stores that non-secret string locally and reuses it across launches and OS updates. No Cookie values are copied to UserDefaults or committed to the repository.

Opening the site browser invalidates old page requests and pauses new native page loads. A response from the previous generation cannot apply cookies after the browser handoff. Closing the browser completes a cookie-store round trip before refreshing the reader. Saved scroll positions cannot reinsert pages from an older login generation.

Read page preserves login/logout HTML structure for status detection, while removing entered input values and active scripts. A captured page supersedes any pending reader load.

The WebKit stores remain separate: Simp retains its existing default store, and South retains its fixed-identifier persistent store. Cookie domain and path filtering is unchanged. Clear session only clears the current forum. See Apple's [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) and [customUserAgent](https://developer.apple.com/documentation/webkit/wkwebview/customuseragent) documentation.

## Validation

Local checks cover repository policy, Swift syntax and diffs. CI runs the Swift package tests and builds the arm64 device app; no simulator is used. New request tests cover exact browser identity through pagination, expired/path/foreign cookies, guest requests and rejection of unsupported routes.

Device acceptance remains required:

1. Open both entry cards and return using the upper-left back button and edge gesture.
2. Sign into South inside Site browser, wait for the forum to finish loading, then use Done. Verify reader access and pagination.
3. Repeat with Read page and relaunch the app. If the previous version's failed requests already invalidated the login cookie, sign in once again.
4. Switch to Simp and verify its existing login and reading library remain unchanged.

No claim is made that an expired or server-revoked session can be recovered without signing in again.
