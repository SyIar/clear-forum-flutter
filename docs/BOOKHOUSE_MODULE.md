# Guest novel-reading module

The third Forum Lite module is **禁忌书屋**, identified internally as
`bookhouse`. It shares the native app shell and existing mixed-script font
settings, with an independent bookmark/history document. The selection page
shows its new logo and domain. It has no app sign-in entry, no persistent
account profile, and no account cookies on reader requests. Its optional site
browser uses an ephemeral WebKit store.

## Source observations and implementation

The user supplied a redacted catalog HTML snapshot. The catalog contains an
embedded JSON `_PageData` array; root books are distinguished from replies by
`uptid == 0`. The site's `index.js` advances `mtid` to the smallest root thread
ID and requests `act=ajax`. This was checked against one anonymous response:
the supplied page contained 207 records and 85 roots; the next response
contained 153 records. No account or authentication is needed for these reads.

The observed detail template uses `h1.main-title`, `threadInfo`, a subtitle
byline and `#content-section`. The body commonly uses `pre` for prose, so it is
parsed as paragraphs instead of a horizontally scrolling code block. Newlines
are preserved; large unbroken text nodes are split into bounded text layouts.
Ads, controls, scripts and surrounding page chrome are excluded. JSON is parsed
as data; no website JavaScript executes inside the native reader.

Search uses the observed GET form. Search pages already contain
`.post-list .post-item` rows and `.pagination-bar` links. The site's
`thread_view_ready.js` declares `act=achildlist` for replies/continuations;
the app requests that list only when the user taps its button.

The source references inspected were the supplied HTML and the site's public
`resource/cool18/assets/public/index/js/index.js` and
`resource/cool18/assets/public/thread_view/js/thread_view_ready.js` scripts.
Live probes were anonymous GET requests; no posting, voting or account action
was performed. Raw responses stay in ignored local artifacts and are not
included in the repository or release bundle. Committed tests use invented,
non-explicit book titles, authors and prose.

The native list loads the next cursor batch with a Load more button. It does
not invent numeric pages for a cursor endpoint. Replies open as standalone
readable entries. Existing app-wide image preview and in-app external browsing
are reused. The reader retains its parsed content when returning from another
page; the bounded session cache keeps the visible paragraph/list position.
This first version does not persist paragraph positions across app termination
or implement novel downloads/offline packs.

## Logo

Asset: `ios/Runner/Assets.xcassets/BookhouseLogo.imageset/bookhouse-logo.png`.
Generated with the built-in imagegen tool, then copied into the app asset
catalog. No CLI/API fallback was used. The original generated image was kept.

Final prompt:

> Use case: logo-brand. Create one finished horizontal logo for an elegant
> Chinese novel-reading module named exactly "禁忌书屋". The four Chinese
> characters must be correct, clear, and the main focus, arranged in one line
> in graceful contemporary Song-style literary lettering. To the left, an
> original compact emblem combining a gently open book with a slender doorway
> and a small warm light, conveying entering a quiet library. Restrained deep
> ink teal and muted antique gold colors on a warm ivory solid background.
> Refined, calm, crisp, flat graphic shapes with only subtle depth. Wide
> horizontal composition with comfortable margins, suitable for a native iOS
> app's 102-point-tall home banner; legible when reduced. No people, no scenic
> illustration, no English words, no domain, no extra slogans, no mockup or
> device frame, no watermarks.

## Validation

Core tests cover the route allowlist, guest cookies, independent libraries,
root/reply separation, advancing cursors, JSON extraction, prose whitespace,
removed advertisements, continuation links, search paging and cached positions.
Local Swift tree-sitter parsing is syntax-only. Full type checking and device
Release compilation use the existing macOS CI workflow. No simulator is used;
physical-device typography and navigation acceptance remain with the user.
