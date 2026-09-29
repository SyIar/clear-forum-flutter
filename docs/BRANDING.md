# Branding

## Forum Lite app icon, 2026-09-29

The current opaque master is `assets/branding/app-icon.png`. It replaces the geometric F icon with exactly two uppercase rows: FORUM and LITE. The built-in `image_gen` tool generated the bitmap from scratch (no CLI or external image API). The output was visually inspected: correct spelling, white upper row, cyan lower row, midnight navy full-bleed square background, safe margins, no outer corner mask. `scripts/generate_icons.py` mechanically resizes it into all iOS AppIcon slots and existing web icons. `scripts/render_forum_icon.py` now delegates to that resizer so it cannot restore the obsolete F design. Forum selector logos are unchanged.

Final generation prompt:

> Use case: logo-brand. Create a polished, distinctive iOS app icon for a minimal forum reader. Deliver ONLY one opaque square icon, preferably 1024 by 1024, edge-to-edge artwork, not a mockup. Exact text on precisely TWO lines: first line FORUM, second line LITE. Spell every letter correctly, uppercase Latin letters. Make typography the entire identity: very bold, slightly condensed, softly rounded geometric sans-serif with beautiful confident proportions, crisp contours and careful optical spacing. FORUM and LITE each fill approximately the same visual width, with LITE larger to balance its four letters against the five above. Stack closely with clear line separation. Center the combined wordmark with generous safe margins of about 13 percent for the iOS icon crop. Background: a deep midnight navy, almost black, with an extremely subtle luminous blue gradient. FORUM: luminous warm white. LITE: vivid cool cyan with a restrained soft blue tonal gradient. Very subtle dimensional edge highlights in the lettering, sophisticated and restrained, no inflated bubble lettering, no busy shadows. Bold, clean, contemporary, premium editorial typography that stays readable at 60 pixels. Full-bleed SQUARE background, DO NOT draw a rounded-corner app tile or border; the operating system supplies the outer corner mask. No additional words, no tagline, no pictures, no speech bubble, no symbols, no frame, no watermark, no external background. The complete icon is the artwork.

## Forum selector, 2026-09-29

The merged app remains `forum lite`. Its selector uses the existing `ForumLogo` asset and a new `SouthLogo` asset, approved by the user in the entry-screen prototype. `SouthLogo.imageset/southplus-wordmark.png` is the unmodified generated 2172 x 724 transparent PNG. It is displayed on white for contrast. The two illustrations and the seasonal word are omitted.

Generation prompt: Use the supplied low-resolution Southplus website logo. Produce a high-definition, clean redraw of only its central black wordmark. Exact text: Southplus, with uppercase S and all remaining letters lowercase. Preserve the original calligraphic shapes, stroke contrast, modest irregularity, letter spacing, tall ascenders and descending p. Remove both illustrated characters and the small red autumn text. No other words, symbols, decorations, borders or shadows. Black ink, smooth sharp contours, transparent background. Center the horizontal wordmark on a wide landscape canvas with a modest safe margin.

## Previous Simp app icon

Display name: `simp lite`. Bundle identifier: `dev.sylar.clearforum`, unchanged for update compatibility.

Master: `assets/branding/app-icon.png`. The 2026-09-28 edit uses the built-in image_gen tool, not the CLI. The existing SIMP/CITY bitmap is the edit target. The output was visually checked for the exact SIMP/LITE text and copied into this repository. `scripts/generate_icons.py` resizes the opaque master into app assets without redrawing it.

## Final edit prompt

Use case: text-localization. Asset type: replacement iPhone app icon for simp lite. Edit target: the existing square app-icon.png. Make exactly one change: replace the lower turquoise word CITY with the uppercase word LITE, spelled L-I-T-E. Preserve the upper white SIMP lettering, turquoise upper background, near-black lower background, horizontal split, square full-bleed shape, typography style, softened corners, letter heights, centered alignment, and comfortable safe margins. Lower LITE uses the same turquoise condensed heavy tall type as the old CITY and approximately the same total visual width. Keep the design simple, crisp, opaque, no rounded outer mask, no additional symbols, no mockup. Exact final two text rows: SIMP above, LITE below. Return the edited icon only.
