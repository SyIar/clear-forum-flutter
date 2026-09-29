# South content purchases

## Requested behavior

In the visible South thread, automatically purchase content whose price is explicitly zero SP. For a positive SP price, show the price and a Buy button and submit only after the user taps it. Refresh the current thread after each submission. Background library/update checks must never purchase content.

## Source evidence and parsing

The supplied local HTML contains `h6.quote.jumbotron > span.s3` with a zero-SP price and an `input[type=button]`. Its handler assigns `location.href` to `job.php?action=buytopic&tid=...&pid=tpc&verify=...`. This is a state-changing GET, matching the site's button, not a POST form. The attachment and its real verification value are never committed or used for a live request during development.

The parser only recognizes that purchase-card shape inside a real `read_*` body. It validates the explicit SP price, exact South origin and `/job.php` path, `action=buytopic`, current thread ID, containing post ID, a nonempty verification parameter, and unique query parameters. Quoted purchase markup and arbitrary JavaScript are excluded. Unknown, malformed, negative, or non-SP prices never become free by default. Normal reader routing still rejects purchase/action URLs.

Offers and verification URLs are held in memory only. Browser capture continues stripping input values and handlers; it passes only a `hasPurchases` flag so the South reader can fetch a fresh authenticated copy when returning from Site browser.

## Purchase flow

- Re-read the current thread before every submission. If the offer is gone, display the fresh page without submitting. Use the current verification URL, not the cached one.
- Compare the newly fetched price with the accepted price. Automatic requests accept only zero; a paid click accepts exactly the price shown on its button. Any change refreshes the displayed price without submitting and requires a new click.
- Send only matching South cookies from its own persistent WebKit store, plus the same browser identity and a thread Referer. The request layer does not follow or replay mutation redirects. Refresh through the normal read-only loader afterward; a still-present offer is reported as unconfirmed.
- Serialize purchases, disable competing controls, respect cancellation/session changes, and attempt a given free offer only once per automatic batch. A defensive cap bounds a batch to 100 distinct offers. Paid offers are never included in a free batch.
- Invalidate cached pages of the affected thread before submission. Preserve unrelated cached threads and the reader's visible floor when a manual purchase completes.
- Network or site failures retain the readable page and the purchase controls. The app does not infer success from a 200 response alone or automatically replay a paid submission.

The observed endpoint contains no atomic maximum-price parameter. Fresh-page revalidation reduces stale-price errors but cannot enforce a server-side price lock between the final read and the site's own transaction. No undocumented price parameter is invented.

## Validation

Synthetic fixtures cover the supplied button structure, zero/positive/unknown prices, quoted markup, mismatched IDs, foreign origins, duplicate parameters, script rejection, cookie scoping, free-only batches, both zero-to-paid and paid price changes, fresh verification values, already-unlocked content, failed unlocks, concurrent submission rejection, and thread-scoped cache invalidation. No real purchase or simulator is used during development. Site-specific transaction success remains a device acceptance check.
