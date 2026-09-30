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
  guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) else { fatalError("Font registration failed: \(name)") }
  print("Validated \(name): CoreText loading, PostScript name, Latin and Chinese glyphs")
}

func faces(_ text: String, font: CTFont) -> [String] {
  let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
  let line = CTLineCreateWithAttributedString(string)
  return (CTLineGetGlyphRuns(line) as! [CTRun]).map { run in
    let attributes = CTRunGetAttributes(run) as NSDictionary
    return CTFontCopyPostScriptName(attributes[kCTFontAttributeName] as! CTFont) as String
  }
}

for bold in [false, true] {
  let font = MixedScriptFont.font(size: 17, bold: bold)
  let expected = bold ? MixedScriptFont.bold : MixedScriptFont.regular
  for sample in ["iPhone 18 / Download 99%", "Cafe\u{00E9}", "\u{03B1}\u{03B2}", "\u{1F600}"] {
    let result = faces(sample, font: font)
    guard !result.isEmpty, result.allSatisfy({ !$0.hasPrefix("SourceHanSerif") }) else {
      fatalError("System-script text incorrectly used the CJK serif: \(result)")
    }
  }
  for sample in ["\u{4E2D}\u{6587}", "\u{65E5}\u{672C}\u{8A9E}", "\u{3042}\u{3044}", "\u{30AB}\u{30CA}", "\u{D55C}\u{AD6D}\u{C5B4}"] {
    let result = faces(sample, font: font)
    guard !result.isEmpty, result.allSatisfy({ $0 == expected }) else {
      fatalError("CJK fallback did not select the requested serif face: \(result)")
    }
  }
  let mixed = faces("iPhone 18 \u{4E2D}\u{6587} \u{3042} \u{D55C} \u{1F600}", font: font)
  guard mixed.contains(expected), mixed.contains(where: { !$0.hasPrefix("SourceHanSerif") }) else {
    fatalError("Mixed paragraph did not preserve separate system and CJK faces")
  }
  print("Validated mixed-script shaping: system Latin/digits/emoji and \(expected) for Han, kana and Hangul")
}
