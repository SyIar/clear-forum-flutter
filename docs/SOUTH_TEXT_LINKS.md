# South plain-text links

The South body parser previously attached a `TextRun.url` only when the source HTML already contained a supported anchor. Bare URLs were left as ordinary text even when they were complete HTTPS addresses.

After collecting a paragraph, `SouthTextLinks` identifies explicit `http://` and `https://` addresses with a case-insensitive regular expression and validates each destination. It maps the detected ranges back into the original text runs, retaining bold/italic formatting and all surrounding text. Adjacent formatting nodes can form one URL; line breaks, emoticons, existing valid links, and literal inline code break detection groups.

- Preserve query strings, fragments, percent-encoded characters, and balanced URL parentheses. Trim common sentence punctuation and surplus closing brackets from the clickable range; leave those characters visible as text.
- Chinese punctuation and invisible separators terminate a candidate. Source/test strings use Unicode escapes to keep repository code in English.
- Preserve existing valid anchor targets, even when the displayed text is itself a different URL. If an anchor lacks a usable target, recover a visible HTTP(S) address without executing its scripts.
- Apply the same behavior to quote and spoiler children and paragraphs containing forum emoticons. Keep preformatted and inline code literal.
- Keep South HTTP links normalized to HTTPS for the existing native reader routes. External HTTP links stay HTTP and open through the existing in-app browser. This navigation-only helper does not relax authenticated reader or image/media request policies.
- Reject unsupported schemes, missing hosts, credentials, invalid percent escapes, invalid ports, backslashes, and oversized candidates. Do not fetch or open destinations during detection.
- Existing `RichBodyView` behavior supplies compact small-font link cards for standalone links and clickable inline text inside sentences. No new browser or layout component is required.

Synthetic regression cases cover bare HTTP/HTTPS links, query/hash preservation, Unicode punctuation and emoji offsets, balanced parentheses, HTML entities and formatting boundaries, explicit/invalid anchors, quotes/spoilers/emoticons, literal code, malformed inputs, and repeated detection. Local Swift syntax and repository/diff checks pass. Swift compilation, test execution, and device acceptance are pending; no packaging or simulator run was requested for this batch.

Punctuation at a raw URL boundary can be inherently ambiguous; normal prose delimiters are treated as punctuation. An existing valid HTML anchor keeps its full target, including significant trailing punctuation.
