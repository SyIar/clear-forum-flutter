import Foundation
import CoreText

enum MixedScriptFont {
  static let regular = "SourceHanSerifSC-Regular"
  static let bold = "SourceHanSerifSC-Bold"

  private static let cjk: CFCharacterSet = {
    let set = CFCharacterSetCreateMutable(nil)!
    for range in [0x1100...0x11FF, 0x2E80...0x2FFF, 0x3000...0x30FF,
                  0x3100...0x31FF, 0x3200...0xA4CF, 0xA960...0xA97F,
                  0xAC00...0xD7FF, 0xF900...0xFAFF, 0xFE30...0xFE4F,
                  0xFF00...0xFFEF, 0x1AFF0...0x1B16F, 0x20000...0x323AF] {
      CFCharacterSetAddCharactersInRange(set, CFRange(location: range.lowerBound, length: range.count))
    }
    return set
  }()

  static func addingCJKFallback(to base: CTFont, bold: Bool) -> CTFont {
    let cjkFont = CTFontDescriptorCreateWithAttributes([
      kCTFontNameAttribute: bold ? self.bold : regular,
      kCTFontCharacterSetAttribute: cjk
    ] as CFDictionary)
    let defaults = CTFontCopyDefaultCascadeListForLanguages(base, ["zh-Hans", "ja", "ko"] as CFArray) as? [CTFontDescriptor] ?? []
    let descriptor = CTFontDescriptorCreateWithAttributes([
      kCTFontCascadeListAttribute: [cjkFont] + defaults
    ] as CFDictionary)
    // Keep the system primary face for Latin, numbers and punctuation.
    return CTFontCreateCopyWithAttributes(base, 0, nil, descriptor)
  }

  static func font(size: CGFloat, bold: Bool) -> CTFont {
    let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
    return addingCJKFallback(to: base, bold: bold)
  }
}
