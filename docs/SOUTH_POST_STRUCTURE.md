# South post boundaries and author metadata

## Confirmed structure

The user supplied a saved thread HTML document on 2026-09-29. It contains 31 actual `read_tpc` / `read_<numeric post ID>` bodies, 31 corresponding `td_*` cells, and 31 `w_*` footer placeholders. Each real body and each footer wrapper carries `.tpc_content`, giving 62 class matches. The actual content element has class `f14`, not `tpc_content`.

Each `.js-post` table contains a `th.r_two` author column spanning two rows. The first profile anchor wraps the avatar and has no text; a later anchor contains the author's name in `strong`. Profiles use `u.php?action-show-uid-<UID>.html`. Avatars include relative built-in images, relative uploads, and external HTTPS images. The `.tiptop` area contains a copy-link anchor followed by a `span.fl.gray` whose text is the absolute post timestamp. Its title is a relative date. Reply floor labels use `B1F`, `B2F`, etc.

## Causes and fix

The old body selector counted both wrappers as posts. Its first author anchor was the empty avatar anchor, producing `Member`. Its first `.tiptop [title]` was the copy-link tooltip, displayed as a date. Its floor regex did not recognize `B<number>F`. The shared post model also had no avatar or UID fields.

- Identify real `read_*` body elements, use stable post IDs, and bind metadata to the enclosing `.js-post` table.
- Keep fallback support for older explicit body markers, while skipping parsed blocks that contain no content. Emoji-only and media-only posts remain visible.
- Prefer the visible name profile link, parse its numeric UID, and take the avatar from the matching profile anchor. Ignore author-menu text and quoted profile links.
- Read the actual timestamp from date elements; never use an arbitrary link tooltip as a date. Recognize `B<number>F` and the original post.
- Render cached round avatars, author name, UID, timestamp, and floor. Hide the date row when no metadata exists. Failed avatar downloads retain the initial-letter fallback.

## Evidence and validation boundaries

The source attachment remains outside the public repository. The regression fixture reproduces its table layout with synthetic English names, IDs, timestamps, content, and resource URLs. No supplied account information, raw page capture, or real post content is published.

Regression cases cover 31 posts staying 31 cards, metadata association, relative and external avatars, modern and legacy UID links, quoted profiles, emoji/media-only replies, and empty compatibility placeholders. Native device compilation runs in the existing GitHub macOS workflow. No simulator is used. The device should be checked with the supplied South thread after installing the updated package.
