# Playback loading feedback

## Behavior

- Resolving a provider URL shows the current phase, a spinner, and elapsed wait time. There is no measurable video-buffer denominator in this phase.
- While native AVPlayer prepares playback, show the union of `loadedTimeRanges` as a percentage of the finite video duration, plus contiguous playable seconds ahead of the current position. This is **buffered video time**, not bytes downloaded and not a percentage of progress toward playback starting. Unknown or live duration has no percentage.
- The player still chooses when to begin. This change does not alter its buffering policy, issue a second video request, or change provider parsing.
- Recent transfer speed uses the difference of known access-log byte and active-transfer-duration counters. The first valid sample uses their average so far. This is an approximate recent transfer measurement, not device-wide instantaneous network speed. Logs can arrive in batches or be absent; missing, invalid, reset, or more-than-five-second-old samples display `Transfer speed unavailable`.
- Feedback disappears when playback begins. Generic embedded web players retain their existing interaction path; measurements appear only when a candidate actually reaches native playback. Web-only fallback does not invent native measurements.
- Refresh starts a fresh timer and sample baseline. Return, failure, or native playback cancels the timer. Details includes the last numeric snapshot without URLs, credentials, or cookies.

## Sources

- [Apple loadedTimeRanges](https://developer.apple.com/documentation/avfoundation/avplayeritem/loadedtimeranges): readily available time ranges may be discontinuous.
- [Apple AVPlayerItemAccessLogEvent](https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent): transfer counters measure network activity; log fields are not KVO observable. `observedBitrate` is empirical transfer throughput, while `indicatedBitrate` is media bitrate.
- [Apple AVPlayer.WaitingReason](https://developer.apple.com/documentation/avfoundation/avplayer/waitingreason): the player can wait while evaluating its buffer fill rate or minimizing stalls. A fixed startup-completion percentage is not exposed by these APIs.

## Verification

Core regression cases cover discontinuous/overlapping ranges, invalid or live duration, clipping, actual transfer-counter deltas, stale samples, unavailable counters, and counter resets. Native compilation uses the existing macOS device-build workflow; no simulator is used. Actual provider counter availability and on-device presentation still need the user's iPhone test.
