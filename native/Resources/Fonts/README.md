# Source Han Serif upload directory

Upload these original static Simplified Chinese OTF files directly into this
directory. Keep their filenames unchanged; do not upload a ZIP archive or a
Git LFS pointer.

| File | Intended use | Official download |
| --- | --- | --- |
| `SourceHanSerifSC-Regular.otf` | Body text | [Download Regular](https://raw.githubusercontent.com/adobe-fonts/source-han-serif/release/OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf) |
| `SourceHanSerifSC-Bold.otf` | Headings and emphasis | [Download Bold](https://raw.githubusercontent.com/adobe-fonts/source-han-serif/release/OTF/SimplifiedChinese/SourceHanSerifSC-Bold.otf) |

Official source: [Adobe Source Han Serif](https://github.com/adobe-fonts/source-han-serif/tree/release/OTF/SimplifiedChinese).
The accompanying `SourceHanSerif-LICENSE.txt` is the upstream SIL Open Font
License and copyright notice; keep it with the fonts.

Repository path: `native/Resources/Fonts/` on `main`.
Local checkout: `D:\workspace\clean-forum-flutter\native\Resources\Fonts\`.
On GitHub, open this directory and choose **Add file > Upload files**.

The two fonts are registered in `native/Info.plist`. XcodeGen copies them into
the app bundle root. The system font remains primary for Latin text, numbers
and emoji. `MixedScriptFont` adds the bundled serif as the preferred CJK
fallback for Han, Japanese kana and Korean Hangul, preserving the system's
remaining fallback list. This applies to SwiftUI text, rich post text and
navigation labels. Bold and semibold CJK text select the real Bold face.
SwiftUI styles use `ScaledMetric`, and UIKit uses `UIFontMetrics` for Dynamic
Type. Code blocks, tiny counters, SF Symbols and original website styling keep
their existing presentation.

CI validates both fonts with CoreText, including their names, glyphs and actual
shaped runs for Latin, digits, emoji, Han, kana, Hangul and mixed paragraphs.
Packaging verifies both embedded files byte-for-byte
against these sources and requires their `UIAppFonts` entries and license.

Large binary assets are uploaded by the repository owner. Prepare the target
folder and exact source links first, then pull and validate the uploaded files;
do not repeatedly retry transferring large assets on the owner's behalf.
