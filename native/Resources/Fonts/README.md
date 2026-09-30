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
the app bundle root. `AppTypography` uses their verified PostScript names for
SwiftUI text styles, rich post text, and app navigation text. Dynamic Type is
retained. Bold and semibold text select the real Bold face; regular and medium
text use Regular. Code blocks and tiny progress counters keep their system
monospaced fonts; SF Symbols and original website content keep their own styling.

CI validates both fonts with CoreText, including their names and representative
Latin/Chinese glyphs. Packaging verifies both embedded files byte-for-byte
against these sources and requires their `UIAppFonts` entries and license.

Large binary assets are uploaded by the repository owner. Prepare the target
folder and exact source links first, then pull and validate the uploaded files;
do not repeatedly retry transferring large assets on the owner's behalf.
