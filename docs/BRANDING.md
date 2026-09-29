# Branding

## Forum selector, 2026-09-29

The merged app remains `forum lite`. Its selector uses the existing `ForumLogo` asset and a new `SouthLogo` asset, approved by the user in the entry-screen prototype. `SouthLogo.imageset/southplus-wordmark.png` is the unmodified generated 2172 x 724 transparent PNG. It is displayed on white for contrast. The two illustrations and the seasonal word are omitted.

Generation prompt: Use the supplied low-resolution Southplus website logo. Produce a high-definition, clean redraw of only its central black wordmark. Exact text: Southplus, with uppercase S and all remaining letters lowercase. Preserve the original calligraphic shapes, stroke contrast, modest irregularity, letter spacing, tall ascenders and descending p. Remove both illustrated characters and the small red autumn text. No other words, symbols, decorations, borders or shadows. Black ink, smooth sharp contours, transparent background. Center the horizontal wordmark on a wide landscape canvas with a modest safe margin.

## Previous Simp app icon

Display name: `simp lite`. Bundle identifier: `dev.sylar.clearforum`, unchanged for update compatibility.

Master: `assets/branding/app-icon.png`. The 2026-09-28 edit uses the built-in image_gen tool, not the CLI. The existing SIMP/CITY bitmap is the edit target. The output was visually checked for the exact SIMP/LITE text and copied into this repository. `scripts/generate_icons.py` resizes the opaque master into app assets without redrawing it.

## Final edit prompt

Use case: text-localization. Asset type: replacement iPhone app icon for simp lite. Edit target: the existing square app-icon.png. Make exactly one change: replace the lower turquoise word CITY with the uppercase word LITE, spelled L-I-T-E. Preserve the upper white SIMP lettering, turquoise upper background, near-black lower background, horizontal split, square full-bleed shape, typography style, softened corners, letter heights, centered alignment, and comfortable safe margins. Lower LITE uses the same turquoise condensed heavy tall type as the old CITY and approximately the same total visual width. Keep the design simple, crisp, opaque, no rounded outer mask, no additional symbols, no mockup. Exact final two text rows: SIMP above, LITE below. Return the edited icon only.
