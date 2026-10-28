# Per-thread update failure recovery

Reading and updating have different freshness rules. ReaderView may display a parsed PageCache snapshot without networking. Library refresh always uses ForumSession.load, which reads the shared WKWebsiteDataStore cookies but performs a fresh URLSession request. A visible cached page is not evidence that a new request passed the site's browser check. The supplied screenshot alone does not identify the failing HTTP document.

Three state bugs were confirmed in source:

- The automatic refresh attempt cooldown also blocked recording a subsequently successful live read for an hour.
- A successful visit changed the thread phase without clearing the previous refresh failure count and message.
- Background success had a visit-token guard; the failure path did not, allowing a delayed error to overwrite a newer foreground result.

Live pages with a trustworthy maximum now update the saved maximum and successful-check time immediately. For pages requiring a last-page lookup, only the last successful check can suppress that lookup; a failed attempt cannot. Cached pages still use `checkMaximum: false` and cannot clear errors or extend freshness. Filtered/reverse pages retain the unfiltered lookup rule, and a successful manual update still has the one-hour cooldown.

LibraryCheckProgress tracks each thread attempt and failure separately. A newer live read invalidates older attempts; a verified, persisted maximum removes only that thread's failure. Other failed threads and followed-author failures remain visible. Update details name the failed thread instead of displaying its verification error as a site-wide banner. Session invalidation/cancellation pauses refresh rather than counting a network failure.

Regression cases cover live-success recovery, late errors, a newer read without proven maximum, independent failures, retries, cooldown behavior, and batch replacement. The verification detector and site security requirements are unchanged. Device acceptance should include cached reading during a genuine challenge, a successful live last-page read after a failed update, and opening a thread while a background update is still pending.

No new runtime text or Chinese localization values are introduced; existing app localization keys are reused. No LEO configuration changes are required.
