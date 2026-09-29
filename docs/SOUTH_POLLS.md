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

## Build 1023 delivery

- Source: `41ac2ac3c1bc9a915e380fd24866d8a1c42b2795`.
- [GitHub Actions run 36551043078](https://github.com/SyIar/clear-forum-flutter/actions/runs/36551043078) succeeded: 93 Swift Core tests with zero failures, media checks, native arm64 iPhoneOS Release compilation, and packaging. No simulator.
- Includes this poll display and the [South purchase flow](SOUTH_PURCHASES.md).
- Version `0.3.0 (1023)`, bundle ID `dev.sylar.clearforum`, display name `forum lite`.
- Local IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1023-unsigned.ipa`.
- Size: `4,261,191` bytes. SHA-256: `a106280d0538b176835204f15797d1bce2f2d01091343d3d9eefda4855b698a2`.
- Verified source/run metadata, checksum, ZIP CRC, bundle/version, arm64 executable, icon assets, native resources, and matching delivery copy.
- Not installed during this task. Native poll presentation, post-vote refresh, and real site purchases await user device testing.
