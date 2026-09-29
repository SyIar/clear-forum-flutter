# Forum search

Status: source changes only. Not packaged or verified on an iPhone.

## Home entries

Both forum homes have a magnifying-glass toolbar button.

- Simp opens native search: keywords, Titles only, Date/Relevance, result snippets, and previous/next pages. Selecting a result opens the reader. Returning keeps the search results.
- South opens native title search with any/all words, newest/latest-reply/reply-count/view-count ordering, and a time range. Defaults match the supplied form: any word, newest first, all forums, past year. Blocked authors remain hidden. Site browser remains available for other search options.

## Verified Simp structure

The user's open search form and result page were inspected on 2026-09-29:

- Form: `https://simpcity.cr/search/search`, POST to `/search/search`.
- Fields used: `keywords`, optional `c[title_only]=1`, `order=date|relevance`, live `_xfToken`, and the form's `search_type` value (empty in the observed form).
- Results: `/search/<id>/?q=<keywords>&o=date`; pages add `page=N`.
- Template: `search_results`. Entries use `.block-row .contentRow`, `.contentRow-title`, `.contentRow-snippet`, and `.contentRow-minor`.
- A title may point to `/threads/<slug>.<id>/post-<id>`. It is resolved through `/posts/<id>/`; the reader now retains the redirected reply fragment. Different matching replies in the same thread remain distinct results.

Tokens and cookies are fetched from the current app session, never copied from the desktop browser, persisted in search data, or logged. POST is submitted once; only ordinary GET redirects follow it. There is no automatic retry or search-as-you-type traffic. Same-origin endpoint validation and per-path cookie filtering apply. Login, challenge, rate-limit, expired-search, and site error responses are not treated as successful empty results.

Native results support forum threads and posts. Unsupported result types require Site browser. Search requests and in-flight pagination are cancelled when leaving the screen. Requests from a previous session generation cannot update the screen.

## Verified South structure

The user supplied both HTML pages after browser inspection was blocked. No browser-policy workaround was used. The attached source uses UTF-8.

- Form `sF` POSTs to `search.php?`, with `step=2`, `keyword`, `method=OR|AND`, `sch_area=0`, `pwuser`, `f_fid`, `sch_time`, `orderway`, and `asc=DESC`. Content/reply searches are disabled in the supplied form, so native search does not enable them. Current hidden fields are retained from the live form.
- The POST returns the first result page directly. Native search parses this body instead of making a fresh GET of `search.php?`, which would lose the search.
- Pagination carries `step`, `keyword`, `sid`, `seekfid`, and `page` in PHPWind's hyphenated URL. These are converted to an encoded query form, retaining the search ID and full keyword, including punctuation. The first result URL is recovered from the pager; a result with no pager stays in the search screen's memory.
- Thread links include a keyword-highlighting parameter that the ordinary reader does not accept. Search parsing removes only this presentation parameter and opens the canonical thread ID.
- Result titles, author IDs/names, forum labels, and dates come from the supplied seven-column result table. Search results do not become pinned threads. Missing markup and site error messages are not treated as empty successes.

## Verification

- Synthetic Swift regression cases cover form encoding, live token extraction, same-origin validation, cookies, multiple matching replies, empty results, error responses, pagination, and redirect fragments. They contain no browser session data.
- Local Swift syntax parsing and repository checks are available on Windows; they do not compile or run the Swift tests.
- macOS CI and device checks remain required for native networking, POST redirects, keyboard/navigation behavior, and website verification flows.
