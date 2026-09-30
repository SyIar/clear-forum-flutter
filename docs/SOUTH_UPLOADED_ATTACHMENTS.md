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

## Verified delivery

- Version: 0.3.0, build 1052.
- Source: `3f7c00a89623de090d17aa3cf5571e68380b9abd`.
- CI: https://github.com/SyIar/clear-forum-flutter/actions/runs/36702493785
- 304 Forum Core tests and 20 Tieba Core tests passed, followed by native iPhone
  compilation and package verification. No simulator was used.
- Downloaded archive integrity, source/build metadata, unsigned arm64 executable,
  font/localization resources, and embedded Tieba framework/resources verified.
- IPA: `D:/workspace/sideloadly-setup/ForumLite-0.3.0-1052-unsigned.ipa`.
- Size: 51,649,756 bytes.
- SHA-256: `ea87010d511cd4268b802619b3529abb17e07ddbe66bb5d3e80ef4e257da8bf0`.

The three uploaded images in the supplied HTML were independently checked on the
local machine to be outside `read_*` and inside attachment/content wrappers.
Device acceptance: refresh the affected thread and confirm all three attachment
images display; use the image-count diagnostics if any request still fails.
