# South visible reading progress and compact controls

## Reading progress

The legacy `seenMaximum` field is the server's maximum floor observed at a visit,
used with `latestMaximum` to detect replies added since that visit. It cannot
establish which floor the reader actually viewed.

South now persists a separate `viewedMaximum`. Only the native scroll view's
visible post IDs can advance it, using each post's floor label, not its database
ID, the loaded page's last post, or a server maximum. The maximum is monotonic
across earlier pages, seamless page joins, and author-filtered thread routes.
Hidden authors, missing floor numbers, directory rows, and background fetches do
not count. Duplicate visibility callbacks do not write the library again.

Visibility comes from the existing scroll target observer with a 1% threshold,
which also supports posts taller than the viewport. Tracking is gated on the
active scene, visible reader, completed load and no covering destination/sheet.
Opening, caching, purchasing, and checking new replies do not directly advance
the viewed floor. The value saves through the existing library persistence path
as new visible maximums arrive; it is not deferred until leaving the reader.

South home rows use only `viewedMaximum` for their read label. Old visit snapshots
remain valid for the Updated badge, but are not migrated into fabricated read
positions. An old row has no read-floor label until actual viewing is observed.
Simp's existing display and new-reply behavior remain unchanged.

## Attachment labels

Remove only the generated image label and line break immediately before a
same-origin uploaded image in `div#att_<number>` outside an identified post body.
Preserve the image, subsequent captions, download links, and matching words in
ordinary author content or quotes. This also allows adjacent image attachments
to use the existing image-grid layout without intervening boilerplate text.

## Controls

South post menus now use the same native `.glass` button style as purchase/unlock
buttons. The ellipsis label is compact and horizontal, with a small control size
and a rounded-rectangle border. Paid purchase buttons say only Buy; the existing
price remains on their left. The free-unlock action keeps its existing label.

## Validation

Tests cover visible versus loaded floors, server-check independence, monotonic
progress across joined/author-filtered pages, blocked/missing/foreign posts,
legacy migration, persisted progress, zero floor and duplicate callbacks, and
scoped attachment-label filtering. UI appearance and physical scrolling require
device acceptance; no simulator is used.
