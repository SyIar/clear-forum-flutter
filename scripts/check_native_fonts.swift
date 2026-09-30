import Foundation
import CoreText

// Run on the macOS builder, without launching a simulator or installing fonts.
let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "native/Resources/Fonts", isDirectory: true)
for name in ["SourceHanSerifSC-Regular", "SourceHanSerifSC-Bold"] {
  let url = directory.appendingPathComponent(name + ".otf")
  guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
        let descriptor = descriptors.first, descriptors.count == 1 else {
    fatalError("Unreadable font: \(url.lastPathComponent)")
  }
  let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
  guard CTFontCopyPostScriptName(font) as String == name else { fatalError("Unexpected PostScript name: \(name)") }
  let characters = Array("Forum Lite 0123 \u{4E2D}\u{6587}\u{8BBA}\u{575B}".utf16)
  var glyphs = [CGGlyph](repeating: 0, count: characters.count)
  let covered = characters.withUnsafeBufferPointer { buffer in
    CTFontGetGlyphsForCharacters(font, buffer.baseAddress!, &glyphs, characters.count)
  }
  guard covered else { fatalError("Missing sample Latin or Chinese glyphs: \(name)") }
  print("Validated \(name): CoreText loading, PostScript name, Latin and Chinese glyphs")
}
