# Module return and download status fixes

## Tieba return

The module selector previously replaced its entire view with Tieba, so no
navigation controller owned the return transition. A dedicated UIKit navigation
host now pushes the module, retaining the selector underneath. The standard edge
pop provides interactive progress and cancellation; the header button uses the
same pop transition. The outer navigation bar stays hidden and module navigation
bars retain their existing appearance.

Tieba reports the selected tab's root state. Its own routes, item-based
destinations, transitions and presented controllers prevent the outer edge pop.
The host also checks the selected UIKit child stack, since not all destinations
are represented by SwiftUI's bound route array. Each tab keeps its own path.
Switching accounts resets those paths consistently with the existing root reset.

The implementation uses Apple's public
[interactivePopGestureRecognizer](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivepopgesturerecognizer)
and disables only the outer controller's
[content-area pop gesture](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivecontentpopgesturerecognizer).
Inner module gestures remain owned by their original navigation controllers.

## File-host status

The batch plan retains an active file until it has been saved. Displaying the
raw plan count as pending, while hiding status during a running batch, made a
Filester transfer look queued despite its moving progress bar.

The shared file-transfer scheduler now reports waiting, address resolution,
downloading and saving. Batch status is visible while running, and the queued
count excludes the current item after the scheduler starts processing it.
Paused items remain in the outstanding count. Folder discovery has its own
status. The serial scheduler and file validation rules are unchanged.

## Floating badge

The count overlay used to be inside the glass button's label and extended beyond
its circular mask. It now overlays the styled button, with an outer layout margin
and no hit testing. A capsule accommodates multi-digit counts. The badge remains
in the upper-left corner without changing the button's action or progress ring.

## Verification

The compact South post menu also uses a capsule border, replacing the 6-point
corners while keeping its existing label size and minimum touch area.

The module selector cards show only their logos. Domain captions are removed;
vertical padding shrinks from 17 to 12 points while the logo height stays 82
points. Accessible entry names remain on the buttons and links.

- Local Swift syntax, resource, localization and repository checks pass. These
  are not a substitute for Apple compilation.
- Core regression coverage checks active, queued, paused, folder and completed
  plan counts.
- Physical-device acceptance: enter Tieba; complete and cancel an edge return;
  verify each tab and a nested forum/thread returns one level at a time; open and
  dismiss login/settings/media without leaving the module unexpectedly.
- Queue two file-host transfers and verify one is active while the other waits;
  pause/resume; verify saving and completion. Check badge counts 2, 10 and 100 in
  light/dark mode, including while progress animates.
- No simulator validation is performed.

## Build 1055 delivery

- Source: `f3cec5937c35c094d9de9d2c7a06634192934b7c`.
- [macOS CI run 36711675800](https://github.com/SyIar/clear-forum-flutter/actions/runs/36711675800): successful.
- Forum Core: 323 tests passed; embedded Tieba Core: 20 tests passed.
- Native iPhone Release compilation, localization and package checks passed.
- Build 1054 was cancelled before delivery to include the subsequent logo-only
  module-selector change in one package.
- IPA: `D:\workspace\sideloadly-setup\ForumLite-0.3.0-1055-unsigned.ipa`.
- Size: 51757650 bytes.
- SHA-256: `1f45fe936ef0ba5e8c1e0af7aa30cf2678965db43979a28097e090c2b0c9c257`.
- Local verification covered archive CRC, source/run metadata, bundle identity,
  arm64 device binaries, fonts, compiled translations and embedded Tieba assets.
- Gesture feel and glass rendering still require physical-device acceptance.
