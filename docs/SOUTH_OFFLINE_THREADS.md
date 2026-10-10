# South offline threads

The South thread menu includes **Download entire thread**. It starts a persistent,
serial queue and opens a download sheet. South's home shows the five most recently
saved threads; the section header opens the full list. Pending and incomplete
downloads stay visible with page counts, size, progress and a retry action. Swipe
or long-press an entry to remove its local copy after confirmation.

The downloader always starts at the unfiltered thread root, even when invoked
from a later page or an author-only view. Each response must have the expected
thread identity, page number and unfiltered post content. It caches all pages in
the pagination range reported by the first saved page. It does not automatically
buy locked content. Downloads use the current South session and save the content
returned by the server for that account.
New replies after this snapshot require removing the snapshot and downloading
the thread again.

Parsed pages, body images, source images, avatars, emoticons and supplied video
posters are stored under Application Support/OfflineSouth and excluded from
iCloud backup. External attachments and video streams are not automatically
downloaded. Image transfers are serial, disk-backed, validated with ImageIO and
bounded by the existing per-image transfer limit. Failed images result in an
incomplete status; retry reuses saved pages and successfully saved image files.

A single repository actor owns disk mutations. Atomic index writes and
per-download tokens protect checkpoints and prevent stale callbacks from
recreating removed downloads. Interrupted pending tasks resume on entering South
or returning to the foreground within South. Closing the downloads sheet does
not stop a task. iOS backgrounding pauses this queue; continuous background
execution is not promised.

The offline reader uses a separate session, page memory cache and image store.
Page loads, seamless pagination, thumbnails and full-resolution gallery images
resolve only from disk; missing assets never silently fall back to networking.
Gallery sharing uses temporary copies so closing the gallery cannot delete the
saved original. Explicit taps on external links, videos or the original website
can still open online destinations. Offline visits do not mark update checks
fresh or alter the live thread's latest-page metadata.

## Validation

Core regression tests cover restart checkpoints, all-page navigation, filtered
URL normalization, wrong-thread/page rejection, incomplete status, image
deduplication, gallery-copy ownership, stale writes after deletion and excluding
video/attachment URLs from automatic image downloads. Local syntax checks are
not compilation; the macOS CI workflow runs the Swift tests and device build.

Device acceptance: cache a multi-page image thread, close the sheet while it
runs, reopen the app, retry a failed transfer, enable airplane mode, read through
every page, swipe/zoom the image gallery, and delete a download while it runs.
