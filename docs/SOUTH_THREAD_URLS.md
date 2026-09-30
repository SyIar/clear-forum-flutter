# South thread query URLs

South full-thread navigation now prefers `read.php?tid=2973920` instead of
`read.php?tid-2973920.html`. Author-filtered threads keep the legacy form, such
as `read.php?tid-2973760-uid-1191634.html`, including their pagination. Existing
query-style author links are converted to that form too.
This is a device compatibility experiment requested
after build 1043; the desktop Safari identity and desktop WebKit content mode
from that build remain enabled.

Validated thread routes are converted before HTTP requests, reader loading,
HTML parsing and main-frame GET navigation in the embedded South browser.
Relative links, thread pagination, author filters and existing library entries
use the same conversion. Thread ID, forum ID, author filter, page and fragment
remain intact. The previously accepted neutral `fpage=0` and empty `toread`
hints are removed. Login, purchase/action URLs, POST submissions, directory and
author-topic routes are not rewritten.

Bookmarks recognize both route spellings without rewriting saved data or
losing custom labels. Existing cache identity remains the same, so a route
spelling change does not discard the stored reading position. Browser rewrite
attempts are bounded if the server repeatedly redirects to the legacy spelling.

Regression coverage includes preserved filters, page and floor anchors,
request headers/cookies, parsed thread destinations, cache aliases and old
bookmark selection/removal. Cloud Core tests and an iPhoneOS Release build
validate the package; logged-in behavior and layout require physical-device
acceptance. No simulator is used.
