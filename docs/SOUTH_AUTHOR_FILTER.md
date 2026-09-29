# South author-only reading

Implemented locally on 2026-09-29. Packaging is paused at the user's request.

## Behavior

- Each South post with a valid header action shows a native glass `scope` icon immediately left of its floor number.
- The action opens the website's author-filtered thread in the native reader, starting at page 1. It covers both the original poster and other authors.
- Previous, next, and page selection retain `uid`. The navigation back action returns to the original reader and its saved position.
- The active author's button is disabled while viewing that author, preventing duplicate pushes of the same filter.
- The icon is absent when the source has no valid author-filter action. Simp posts are unchanged.

## Source and integration

The supplied local HTML contains 31 post tables. Each has exactly one matching author link inside `.tiptop`, with the same UID as its author metadata. Raw HTML, account data, and tokens are not copied into the repository; test fixtures use synthetic identities.

`ForumPost.authorFilterURL` comes from the post header. It must be a readable South `read.php` URL for the same thread and match the parsed author ID when available. Quoted/body links cannot supply this action. Only positive numeric `uid` values are accepted, and duplicate parameters remain invalid.

Page cache identity includes `uid`, so the whole thread and different authors retain separate content and scroll positions. Thread identity continues to exclude `uid`: purchase invalidation covers all views, and library update checks load the unfiltered thread before recording its maximum floor. A filtered page never reports its last reply as the whole thread's maximum.

## Validation status

- Local source inspection: all 31 provided post headers have one matching author-filter link.
- Tree-sitter syntax parsing passed for 51 Swift files. This is not Swift compilation or type checking.
- Repository language/credential policy and whitespace checks passed.
- Added Swift Core regression cases for per-post association, route aliases, pagination, cache separation, invalidation, and unfiltered library identity. These tests have not been executed yet.
- No simulator, cloud build, IPA packaging, or installation performed for this change. Compilation, Core test execution, and device acceptance remain pending the user's batch-build instruction.

Device acceptance should cover the original poster and a reply author, filtered pagination/page selection, back navigation with restored position, and unchanged whole-thread update tracking.
