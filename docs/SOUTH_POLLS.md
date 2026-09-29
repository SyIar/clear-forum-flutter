# South poll display

## Scope

The native reader displays the thread poll above its posts. Voting opens the existing authenticated South Site browser inside the app. The reader does not submit votes or choose options for the user.

## Evidence and display

The user-supplied PHPWind HTML contains a `form[name=vote]` outside the post bodies, targeting `job.php?action=vote`. Its six checkbox rows allow up to six choices, show 251 participants, and include start/end times. Each result is `*` votes; a bar image with width zero is not a zero-vote result.

- Keep every option in source order, with website-selected state if present.
- Show participant count, choice limit, source timestamps, and any poll status notice.
- Keep hidden or unrecognized counts unknown. Only show vote-share bars when every count is numeric; the denominator is the sum of votes, not the number of participants, because multiple selections are possible.
- Preserve zero counts, results-only rows, and disabled polls without inventing a closed/voted state.
- Open the current thread in Site browser for voting. Read page reloads South poll pages from the authenticated session; closing Site browser also reloads the reader. No form token is retained in `SouthPoll` or persisted to the library.
- Retain the poll and its scroll anchor in the bounded in-memory page cache.

## Verification

Synthetic English fixtures reproduce the supplied malformed table closing tag and the poll's location outside the post body. Tests cover hidden results, numeric/zero results, multiselect proportions, radio/selected state, results-only/disabled polls, unknown metadata, unrelated forms, and cache restoration. No live vote is submitted during development. Device presentation and post-vote refresh require user testing.
