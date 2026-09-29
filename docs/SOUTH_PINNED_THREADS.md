# South pinned threads

South thread lists group the first two visible pinned threads into one rounded card in website order. A shared header contains one pin icon, Pinned, the total count and a View all chevron when more than two entries remain. Titles use compact rows with inset separators instead of separate cards, repeated pin icons, thumbnails, category chips and a detached ellipsis button.

The entire header opens the existing sheet of all visible pinned threads, including the first two. The sheet shares the same row styling and allows two title lines. Selecting a sheet row dismisses it before pushing its thread onto the reader's navigation stack.

The local author blocklist applies before choosing the first two and also applies to the sheet. Ordinary threads retain their order below the card. No card appears for zero pinned threads. One or two show a static header with no View all control. Simp lists and South forum-category lists retain their existing presentation.

Full parsed pages remain cached. The preview does not truncate cache contents or alter pagination. The card uses the first visible pinned thread's real ID as its scroll anchor, preserving page lookup during continuous paging. Restoring any pinned entry or the legacy south-pinned-more anchor targets that card.

The earlier layout was included in build 1028. This unified-card redesign is included in [build 1030](BUILD_1030.md). Local Swift syntax parsing, repository policy and whitespace checks passed; macOS CI passed 192 Swift Core tests and arm64 iPhoneOS Release compilation. The IPA passed local integrity verification. Pending device checks: zero/one/two/many pinned entries, long titles, dark mode and large text, header and row taps, blocked authors, returning to the card and continuous paging.
