# Branding

## Current Forum Lite app icon, 2026-10-08

The opaque 1024 x 1024 RGB master is `assets/branding/app-icon.png`. Its SHA-256 is `1a4f92328e502d390f809b22c8f23f5861efaf55c6eab7585a89de043f0d7930`. The built-in `image_gen` tool edited the previous blue star into a black, white, and silver-gray version. The twelve-point silhouette, central facets, square composition, and safe margins remain recognizable. No text, outer corner mask, or border was added.

The generated bitmap was inspected visually, normalized to the 1024-pixel master using the existing asset resizer, and resized into all iOS AppIcon slots, existing web icons, and the favicon. The iOS marketing icon has identical RGB pixels to the master. This is a grayscale visual palette with continuous shading, rather than three flat quantized colors. No app code, display name, bundle identifier, or forum selector logos changed.

Final edit prompt (built-in image tool; no CLI or external image API):

> Edit target: the attached current Forum Lite iOS app icon. Change ONLY its color palette to strictly achromatic black, white, and neutral gray tones (no hue, no blue tint, all RGB channels equal ideally). Preserve exactly the existing centered twelve-point faceted star silhouette, placement, proportions, radiating triangular facets, margins, and lighting direction. Render white highlights and silver-gray shaded facets on a deep black/charcoal subtle gradient square background. Keep the visual design elegant and crisp at small app-icon sizes. No text, no border, no rounded outer corners, no extra objects. Opaque square 1024x1024 production app icon. This is a faithful monochrome recolor of the supplied icon, not a new symbol.

## Previous Forum Lite app icon, 2026-09-30

The previous opaque 1024 x 1024 RGB master at `assets/branding/app-icon.png` was copied byte-for-byte from the user-supplied `forumlite-twelve-point-icon-1024.png`. Its SHA-256 was `48e32605159a6f4e4840e350d9feb5369c9209ee2fe42523ae857cb1c4fce0f7`. The cyan/blue faceted twelve-point star on navy replaced the previous FORUM / LITE wordmark. No generation, redrawing, corner mask, or composition change was applied at that time.

`scripts/generate_icons.py` mechanically resizes the master into every iOS AppIcon slot, the existing web icons, and the favicon. The iOS marketing icon retains identical RGB pixels at 1024 x 1024. The display name is `Forum Lite`; the bundle identifier remains `dev.sylar.clearforum`. Forum selector logos are unchanged.

## Previous Forum Lite app icon, 2026-09-29

The previous opaque master at `assets/branding/app-icon.png` replaced the geometric F icon with exactly two uppercase rows: FORUM and LITE. The built-in `image_gen` tool generated the bitmap from scratch (no CLI or external image API). The output was visually inspected: correct spelling, white upper row, cyan lower row, midnight navy full-bleed square background, safe margins, no outer corner mask. `scripts/generate_icons.py` mechanically resizes the master into all iOS AppIcon slots and existing web icons. `scripts/render_forum_icon.py` delegates to that resizer so it cannot restore the obsolete F design. Forum selector logos are unchanged.

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
