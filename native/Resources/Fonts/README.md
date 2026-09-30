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

This directory currently prepares the asset handoff only. The native app still
uses the system font. After upload, verify the OTF files and their PostScript
names, register the bundled fonts, and apply the text styles before building an
IPA. Uploading the files alone does not switch the app font.
