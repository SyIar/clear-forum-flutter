# South uploaded attachment parsing

## Diagnosis

The supplied desktop HTML places three uploaded image attachments in sibling
`div#att_<id>` nodes before `div#read_tpc`. All four nodes share a `.tpc_content`
wrapper. The reader previously selected only the identified `read_tpc` body,
which preserved text and inline emoticons but discarded sibling attachments.
The same structure can occur in replies with `read_<post-id>` bodies.

The supplied build 1048 log already requested a `read.php?tid=...` URL. Its pasted
HTML ends in the account header before any post content, so it cannot establish
whether the received response lacked the attachments. Diagnostic HTML is also
deliberately sanitized and formatted; scripts, styles, and form values are not
part of the exported HTML. The parser uses the original
decoded response, not the sanitized export.

The supplied source separately redirects mobile browsers to `/simple/` through
JavaScript when the `mobilever` cookie is absent. The `.html` URL suffix alone
does not determine that layout. Existing desktop browser identity and ordinary
thread query normalization remain in place, as does legacy author-filter syntax.

## Change

Keep the identified body for post identity and author/floor metadata, but render
its nearest `.tpc_content` wrapper when the wrapper contains exactly that one
identified post. This includes sibling attachments in document order without
expanding into the surrounding table, footer, signature, or avatar column.
Ambiguous wrappers containing multiple posts retain per-body extraction.

Diagnostics now report the response image count, South attachment image count,
parsed post image count, and inline emoticon count. HTML exports identify their
sanitized UTF-8 byte size and include a closing marker to expose incomplete
copies. Supplied account data and page contents are not checked into the repo.

## Validation

Regression tests cover sibling attachment order and post identity, an empty body
with an image attachment, exclusion of signature/avatar images, ambiguous shared
wrappers, response-versus-parser image counts, and complete export markers.
Existing parser, URL normalization, session isolation, and pagination tests also
run in CI. No simulator is used; physical-device image display remains to be
confirmed by the user.
