import Foundation
import CoreGraphics
import ImageIO
import ImageCodecSupport

/// Converts only representations whose pixels and color metadata can be preserved.
enum LosslessPNG {
  enum Failure: Error { case unsupported, invalid }
  static let maximumBytes = 80 * 1024 * 1024

  static func encode(_ png: Data) throws -> Data {
    guard png.count <= maximumBytes, png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw Failure.invalid }
    var offset = 8, width = 0, height = 0, color = 0
    var compressed = Data(), palette = Data(), transparency = Data(), exif = Data()
    var seen: Set<String> = [], ended = false, idatEnded = false
    let allowed: Set<String> = ["IHDR", "PLTE", "tRNS", "IDAT", "IEND", "iCCP", "sRGB", "gAMA", "cHRM", "eXIf"]
    func integer(_ start: Int) -> Int { png[start..<(start + 4)].reduce(0) { ($0 << 8) | Int($1) } }
    while offset <= png.count - 12 {
      let size = integer(offset)
      guard size <= png.count - offset - 12 else { throw Failure.invalid }
      let type = String(decoding: png[(offset + 4)..<(offset + 8)], as: UTF8.self)
      guard allowed.contains(type) else { throw Failure.unsupported }
      let crc = png.withUnsafeBytes { raw in
        FLImageCRC(raw.baseAddress!.advanced(by: offset + 4).assumingMemoryBound(to: UInt8.self), size + 4)
      }
      guard crc == UInt32(integer(offset + 8 + size)), !ended,
            (seen.isEmpty ? type == "IHDR" : type != "IHDR"),
            type == "IDAT" || !seen.contains(type) else { throw Failure.invalid }
      let payload = Data(png[(offset + 8)..<(offset + 8 + size)])
      if seen.contains("IDAT") && type != "IDAT" { idatEnded = true }
      switch type {
      case "IHDR":
        guard size == 13 else { throw Failure.invalid }
        width = integer(offset + 8); height = integer(offset + 12)
        color = Int(payload[9])
        guard payload[8] == 8, payload[10] == 0, payload[11] == 0, payload[12] == 0,
              [0, 2, 3, 4, 6].contains(color), width > 0, height > 0,
              width <= 16383, height <= 16383, width * height <= 16_000_000 else { throw Failure.unsupported }
      case "IDAT":
        guard !idatEnded else { throw Failure.invalid }
        compressed.append(payload)
      case "PLTE", "tRNS", "iCCP", "sRGB", "gAMA", "cHRM":
        guard !seen.contains("IDAT") else { throw Failure.invalid }
        if type == "PLTE" { palette = payload }
        if type == "tRNS" { transparency = payload }
      case "eXIf": exif = payload
      case "IEND":
        guard size == 0, seen.contains("IDAT") else { throw Failure.invalid }
        ended = true
      default: break
      }
      seen.insert(type)
      offset += size + 12
    }
    guard ended, offset == png.count, !compressed.isEmpty,
          let source = CGImageSourceCreateWithData(png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) == 1,
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
          image.width == width, image.height == height else { throw Failure.invalid }
    let profile: Data
    if let space = image.colorSpace, space.model == .rgb, let icc = space.copyICCData() {
      profile = icc as Data
    } else {
      // WebP stores RGB, so do not attach a gray/indexed profile to expanded RGB.
      guard seen.isDisjoint(with: ["iCCP", "gAMA", "cHRM"]),
            let icc = CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() else { throw Failure.unsupported }
      profile = icc as Data
    }
    try Task.checkCancellation()
    let rgba = compressed.withUnsafeBytes { data in
      palette.withUnsafeBytes { colors in
        transparency.withUnsafeBytes { alpha in
          FLPNGDecode(data.bindMemory(to: UInt8.self).baseAddress, compressed.count, Int32(width), Int32(height), Int32(color),
            colors.bindMemory(to: UInt8.self).baseAddress, palette.count, alpha.bindMemory(to: UInt8.self).baseAddress, transparency.count)
        }
      }
    }
    guard let rgba else { throw Failure.invalid }
    defer { FLImageFree(rgba) }
    var size = 0
    let result = profile.withUnsafeBytes { icc in
      exif.withUnsafeBytes { metadata in
        FLWebPEncode(rgba, Int32(width), Int32(height), icc.bindMemory(to: UInt8.self).baseAddress, profile.count,
          metadata.bindMemory(to: UInt8.self).baseAddress, exif.count, &size)
      }
    }
    guard let result else { throw Failure.invalid }
    defer { FLImageFree(result) }
    try Task.checkCancellation()
    let output = Data(bytes: result, count: size)
    // Confirm that the app's actual image decoder can open the installed format.
    guard let check = CGImageSourceCreateWithData(output as CFData, nil),
          let decoded = CGImageSourceCreateImageAtIndex(check, 0, nil),
          decoded.width == width, decoded.height == height else { throw Failure.unsupported }
    return output
  }
}
