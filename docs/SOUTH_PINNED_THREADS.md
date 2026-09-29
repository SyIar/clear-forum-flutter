# Collapsed South pinned threads

South thread lists show the first two visible pinned threads in website order. When more than two remain, a compact native glass ellipsis button appears below them. Selecting it presents a sheet containing all visible pinned threads, including the first two. Selecting a row dismisses the sheet before pushing its thread onto the reader's navigation stack.

The local author blocklist applies before choosing the first two and also applies to the sheet. Ordinary threads retain their order below the pinned preview. Zero, one, or two pinned threads do not show an overflow button. Simp lists and South forum-category lists retain their existing presentation.

Full parsed pages remain cached. Collapsing the display does not truncate cache contents or alter pagination. Restoring a saved anchor for an overflowed pinned thread targets the ellipsis row.

Implemented on 2026-09-29. Local Swift syntax parsing, repository policy checks, and whitespace checks passed. No Swift compilation, simulator, cloud build, or IPA packaging was performed; the user is collecting changes for a later batch build.
