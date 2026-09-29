# South inline emoticons and the shared external browser

## South emoticons

The South parser recognizes images on the exact `south-plus.net` origin under `/images/post/smile/`, including `smallface/face077.gif`. The existing URL resolver normalizes relative URLs, protocol-relative URLs, and legacy HTTP URLs on that origin. Other South images and lookalike domains remain ordinary photos.

An emoticon stays in the paragraph as a `TextRun.emoticon`; it no longer flushes the paragraph or enters the large-image grid. The SwiftUI text renderer loads it through the site's existing bounded image cache, preserves its aspect ratio, and caps its longest side at 24 points at the default text size. Dynamic Type adjusts that cap. HTML width/height cannot enlarge it. Emoji-only paragraphs, quotes, and lazy sources are supported. A small symbol occupies the inline position if loading fails. As with the existing image decoder, GIFs currently use their first frame; this change does not add GIF animation.

## External links

Both readers present `SFSafariViewController` when an ordinary link is not handled by their forum reader. The system browser stays inside the app and supplies its standard close, browsing, sharing, and page controls. It is presented modally through UIKit using Safari's default transition, not embedded as a child controller. Explicit external link taps in Site browser, including new-window links, use the same browser. Automatic cross-origin main-frame redirects in the forum login browser remain blocked.

The external browser does not call `beginBrowsing` or `endBrowsing`, invalidate parsed pages, or transfer forum cookies. The two forum sessions remain separate. Ordinary dismissal preserves the source reader; memory-pressure eviction can still require a later reload. Media cards continue to use their existing player. Safari's explicit open-in-browser action remains available to the user.

This uses the [Apple SFSafariViewController API](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller), which Apple documents as an in-app web interface with native modal transitions and dismissal gestures. It does not imply a custom ad blocker for arbitrary external websites.

## Verification

Parser regression cases use synthetic HTML only: inline ordering/formatting, emoji-only paragraphs, lazy/relative/HTTP source normalization, exact directory/host matching, ordinary photos, and quoted content. The existing media checks and native device build cover integration. No simulator or captured account data is used.

Device checks after installation:

1. Open a South post mixing text, built-in emoticons, and normal photos. Confirm the emoticons stay small and inline in light/dark mode and with larger system text.
2. In both forums, tap an ordinary external link, browse another page, then close or swipe back. Confirm the original thread and reading position remain available.
3. Repeat from Site browser and from a link opening a new window. Confirm forum login still works after returning.
4. Open existing Turbo and non-Turbo media cards; their player flow should remain unchanged.

Native build and device acceptance results are recorded below when available.
