# Android migration audit

The initial Android build 7 is an incomplete migration, not feature parity with
the production Forum Lite app. Successful installation, parser smoke tests and
tablet layout tests did not establish that the original workflows were ported.
The production reference is `native/Core`, `native/App` and `native/Tieba`, not
the retired root Flutter prototype.

## Required workflow inventory

| Workflow | Production reference | Build 7 finding |
| --- | --- | --- |
| Login and browser handoff | `ForumSession`, `BrowserIdentity`, `ForumBrowser` | Dedicated login added; South form verified; Simp device connection reset also reproduced in Brave; authenticated handoff unverified |
| Bookmarks and import | `ReadingLibrary`, `ReaderView` | Only exact-URL toggles; import and metadata missing |
| Visible reading progress | `ReadingLibrary`, `ReaderView` | Missing floor high-water mark and resume anchor |
| Latest thread checks | `LibraryRefreshPolicy`, `ForumSession.latestThreadPage` | Incorrect current-page signature comparison; latest-page discovery absent |
| Followed authors | `SouthFollowing`, `SouthFollowingSection` | Missing |
| Author actions and blocking | `SouthAuthorBlocking`, `SouthPostMenu` | Missing; ellipsis only opens text selection |
| Seamless forum paging | `ReaderPageWindow`, `ReaderView` | Forward append only; no backward prepend or bounded window |
| Native forum search | `SimpSearch`, `SouthSearch`, `ForumSearchView` | Browser fallback instead of native search execution/results |
| South purchase and poll | `SouthPurchase`, `SouthPoll` | Missing |
| Complete offline threads | `SouthOfflineRepository`, `SouthOfflineStore` | Only raw HTML page cache; assets and durable task checkpoints missing |
| Diagnostics and verification | `ReaderDiagnostics`, `SimpBrowserVerification` | Incomplete diagnostics and recovery |
| Novel chapter model | `BookhouseFollowing`, `BookhouseReadingWindow` | Publication-level implementation; bundled/split chapter anchors incomplete |
| Novel offline cache | `BookhouseOfflineRepository`, `BookhouseOfflineSearch` | Basic cache/search exists; quota, eviction and paragraph jumps incomplete |
| Reading appearance | `ReadingAppearance`, `MixedScriptFont` | Font-size only; typography and appearance controls missing |
| Embedded video resolution | `MediaViewer`, `MediaProbe.js` | Provider web fallback; native resolution incomplete |
| Hosted file resolution | `HostedFileClient`, `GofileSession`, `TorrentMetadata` | Partial providers; Fileditch, full pagination and magnet copying missing |
| Persistent file transfers | `FileDownloadStore`, `GofileBatchPlan` | Android foreground service exists; provider-level refreshed resume parity incomplete |
| Local archive/image tools | `LocalArchiveExtractor`, `LocalImageConversion` | Archive extraction and image conversion missing |
| Tieba | `native/Tieba`, existing Dart client | Existing Dart client vendored; native-client differences require separate audit |

## Acceptance rules

- Port behavior and persistence semantics from production code, retaining the
  four installed application IDs and existing user data.
- Cover meaningful state transitions and representative source fixtures. A
  visible menu entry is not evidence that its workflow works.
- Local Dart analysis/tests are allowed. Android compilation and APK packaging
  run only in GitHub Actions; never invoke local Gradle.
- Report local checks, remote builds, device checks and unverified account
  workflows separately. Do not label this migration complete while rows above
  remain missing or partial.

## Core restoration in the current branch

This is a corrective migration milestone, not a declaration of full parity.

- Bookmarks retain their imported URLs and labels. Paste/import HTML or URLs,
  rename, remove, and browse history are available. Simp opens the latest known
  bookmark page without a preliminary redirect/check when tapped.
- Actual visible posts update a persisted floor high-water mark and resume
  anchor. Fetching, checking or preloading a page does not mark it read.
- Update checks validate the actual last page and its maximum floor. Successful
  checks are skipped for one hour; manual checks retry eligible failures. South
  followed authors retain their three latest validated topics and unread state.
- South author actions include profile, topics, follow/unfollow, only-author,
  blocking, unblocking and selectable text. Only-author rewritten URLs retain
  their filter. The original-poster marker uses a solid person symbol.
- Reader paging appends/prepends and retains at most five offscreen-trimmable
  pages. Page boundaries remain measurable for scroll anchoring. Tests cover
  eight successive pages, reverse loading after eviction, and unchanged read
  high-water marks. Text selection is in the copy drawer so prose does not
  consume vertical scrolling gestures. Large image-heavy threads still need
  tablet memory and scroll-performance measurements.
- Simp and South submit their validated native website search forms through
  the shared WebView session and render native paginated results. Search POSTs
  are submitted once; no credential or verification token is guessed.
- South purchases refresh the offer, validate the post and price, submit once,
  and reconcile uncertain results without replay. Free offers can unlock in
  the reader; paid offers require an explicit price confirmation. Poll results
  are display-only, with voting in the authenticated website as in the native
  client. No live purchase or vote was performed during verification.
- South offline threads use a durable serial queue, frozen page count,
  per-page/per-image checkpoints, local avatars/images/originals and retry of
  missing assets. Removing a job during a request cannot resurrect it. Offline
  viewing reads disk only. Older HTML-only cache records are labelled as such.
  Closing the reader does not cancel the queue; process termination is resumed
  from checkpoints at the next launch, not promised to run while terminated.
- Bookhouse retains a seven-character title search and author matching, regular
  and extra chapters, split parts, verified chapter headings inside bundles,
  paragraph-level resume/search anchors and a chapter-number slider. Overlap
  removal requires real headings instead of guessing away novel text. The last
  retained publication triggers preload when visible paragraphs reach 90%.
  Read pages are cached; cache-all continues outside its drawer and pending jobs
  resume when reopening the book. Refresh success throttling is one hour here too.
- Diagnostics expose recent page state and sanitized DOM for copying. Executable
  content, form controls and credential values are removed. Page addresses and
  DOM URLs redact non-routing parameters; inert form containers retain their
  post content, including lazy image source attributes.
- Existing app IDs, signing identity and preference keys remain unchanged.
  This change does not reset any installed account, history or download data.

## Explicit remaining gaps

- Torrent-to-magnet conversion, Fileditch metadata resolution, and native
  embedded-provider video resolution.
  Existing direct download/browser paths are not equivalent to these workflows.
- Live authenticated Gofile pagination and expired-link renewal still require
  account acceptance. Renewal needs the app's Dart/WebView session; an expired
  transfer waits while that session is unavailable instead of downloading HTML.
- Local image conversion deliberately retains transparent, animated, tagged
  metadata and non-sRGB PNGs. It is not full native PNG metadata parity.
- The complete native reading-appearance system (CJK-only bundled serif,
  paragraph/line spacing preferences), novel cache quotas/eviction and complete
  legacy author-provenance migration remain incomplete.
- Tieba already carries the existing Dart login, API, replies, search, history,
  settings and media implementation; it is not a newly implemented placeholder.
  However, its complete behavioral comparison against `native/Tieba` is still
  outstanding. Its two-pane rotation test does not establish native parity.
- Authenticated search, paid purchases, anti-bot recovery and large live offline
  downloads require account/device acceptance. Tests use source fixtures and
  fake network responses; they cannot establish that a website accepts a login.

## Validation boundary

Local verification uses Dart analysis and Flutter regression/widget tests only.
Android compilation and APK validation are performed by the remote workflow
`Four Android tablet apps`. The USB device list was empty during this milestone;
do not describe the new APKs as device-tested until that check actually happens.

## Download and local-file restoration

- A ZIP opens an extraction/password dialog or an external-app chooser. The
  shared Android worker supports plain, traditional encrypted and AES ZIPs
  through [Zip4j](https://github.com/srikanth-lingala/zip4j). It validates paths,
  duplicate entries, special file types, declared sizes and free storage before
  publishing a new sibling folder. Existing folders and the archive are retained;
  failures remove only the owned staging folder. Passwords are memory-only.
- The local-files toolbar recursively converts eligible PNGs to Android
  [lossless WebP](https://developer.android.com/reference/android/graphics/Bitmap.CompressFormat#WEBP_LOSSLESS).
  Newly downloaded PNGs use the same serial worker automatically. Conversion
  requires API 30+, an opaque 8-bit non-interlaced sRGB image, acceptable memory
  bounds, matching decoded pixels, a smaller output and an unchanged source hash.
  Unknown metadata and animated/transparent images remain untouched. An atomic
  provenance journal permits recovery without overwriting unrelated WebP files.
  Successful replacements retain arrival order and update completed task paths.
  New PNG downloads persist a pending-optimization marker. If Android stops the
  process after download completion, opening the app resumes that optimization;
  old downloads without this marker are changed only by the manual batch action.
- File jobs survive closing the file browser; progress remains available when
  reopening it. These jobs are process-owned, not persisted/resumable across an
  Android process kill. Interrupted extraction retains the original archive;
  re-run the operation after restarting. Download transfers remain owned by the
  existing Android foreground service.
- Gofile observes bounded responses from its own website, validates folder/file
  identity, collects all declared pages and subfolders, and publishes no partial
  plan on access/pagination errors. No provider tokens are fabricated. Direct
  CDN links normalize to their content IDs for resolution.
- New Filester, Bunkr, Pixeldrain and Gofile queue entries retain provider identity
  and source pages. Expired links can be resolved again without creating a second
  task. Automatic renewal is bounded; explicit resume can retry. Resume validates
  byte ranges and ETag/Last-Modified; changed validators restart instead of
  appending mismatched bytes. Old queues remain readable; pre-migration entries
  without source identity cannot gain provider refresh metadata retroactively.
- CI additionally runs Kotlin Android instrumentation workflows on an API 35
  emulator for real encrypted archives, unsafe paths, collision handling,
  lossless pixel comparison, arrival times and conversion provenance. These are
  device-platform integration checks, separate from local Dart tests and OPPO
  hardware acceptance. No local Gradle commands are used.
