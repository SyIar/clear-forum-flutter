import Foundation
import ImageIO
import ImageCodecSupport
import XCTest
@testable import ForumCore

final class LocalImageConversionTests: XCTestCase {
  private func be(_ value: Int) -> Data { Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
  private func chunk(_ name: String, _ payload: Data) -> Data {
    let body = Data(name.utf8) + payload
    let crc = body.withUnsafeBytes { FLImageCRC($0.bindMemory(to: UInt8.self).baseAddress, body.count) }
    return be(payload.count) + body + be(Int(crc))
  }
  // Stored DEFLATE blocks intentionally leave room for compression, with exact
  // source bytes including hidden RGB values underneath fully transparent pixels.
  private func png(width: Int = 64, height: Int = 32, depth: UInt8 = 8, extra: Data = Data()) -> Data {
    var raw = Data()
    for y in 0..<height {
      raw.append(0)
      for x in 0..<width { raw.append(contentsOf: [UInt8(x % 16), UInt8(y % 16), 80, UInt8(x % 2 == 0 ? 0 : 128)]) }
    }
    var compressed = Data([0x78, 0x01])
    var position = 0
    while position < raw.count {
      let size = min(65535, raw.count - position)
      compressed.append(contentsOf: [position + size == raw.count ? 1 : 0, UInt8(size & 255), UInt8(size >> 8), UInt8((size ^ 65535) & 255), UInt8((size ^ 65535) >> 8)])
      compressed.append(raw[position..<(position + size)])
      position += size
    }
    var a = 1, b = 0
    for byte in raw { a = (a + Int(byte)) % 65521; b = (b + a) % 65521 }
    compressed.append(be((b << 16) | a))
    return Data([137, 80, 78, 71, 13, 10, 26, 10]) + chunk("IHDR", be(width) + be(height) + Data([depth, 6, 0, 0, 0]))
      + extra + chunk("IDAT", compressed) + chunk("IEND", Data())
  }
  private func fixture(_ run: (URL, LocalFileCatalog) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try run(root, LocalFileCatalog(root: root))
  }

  func testExactTransparentPixelsRoundTripAndNativeDecoderSupport() throws {
    let source = png()
    let encoded = try LosslessPNG.encode(source)
    XCTAssertLessThan(encoded.count, source.count)
    let decoded = try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
    XCTAssertEqual(CGImageSourceGetCount(decoded), 1)
    XCTAssertEqual(CGImageSourceCreateImageAtIndex(decoded, 0, nil)?.width, 64)
  }

  func testEXIFOrientationSurvivesConversion() throws {
    // Little-endian TIFF with one orientation entry (rotate 90 degrees).
    let exif = Data([73, 73, 42, 0, 8, 0, 0, 0, 1, 0, 18, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0])
    let encoded = try LosslessPNG.encode(png(extra: chunk("eXIf", exif)))
    let decoded = try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
    let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
    XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6)
  }

  func testNativeEncoderCancellationProducesNoOutput() throws {
    let pixels = Data(repeating: 127, count: 256 * 256 * 4)
    var count = 0
    let result = pixels.withUnsafeBytes {
      FLWebPEncode($0.bindMemory(to: UInt8.self).baseAddress, 256, 256, nil, 0, nil, 0, { 0 }, &count)
    }
    if let result { FLImageFree(result) }
    XCTAssertNil(result)
    XCTAssertEqual(count, 0)
  }

  func testReplacementPreservesArrivalAndOldQueuePath() throws {
    try fixture { root, catalog in
      let file = root.appendingPathComponent("image.png")
      try png().write(to: file)
      let arrived = Date(timeIntervalSince1970: 1000)
      try LocalFileMetadata.arrived(file, at: arrived)
      let result = try XCTUnwrap(LocalImageConversion.convert(["image.png"], in: catalog))
      XCTAssertEqual(result.file.pathExtension, "webp")
      XCTAssertGreaterThan(result.savedBytes, 0)
      XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
      XCTAssertEqual(LocalImageConversion.resolved(file), result.file)
      XCTAssertEqual(try catalog.url(for: ["image.png"]), result.file)
      XCTAssertEqual(try catalog.entries().first?.added, arrived)
      XCTAssertNil(try LocalImageConversion.convert(["image.png"], in: catalog))
    }
  }

  func testExistingWebPIsNeverOverwrittenOrUsedAsUnverifiedAlias() throws {
    try fixture { root, catalog in
      let file = root.appendingPathComponent("image.png"), output = root.appendingPathComponent("image.webp")
      let source = png(), other = Data([1, 2, 3])
      try source.write(to: file); try other.write(to: output)
      XCTAssertNil(try LocalImageConversion.convert(["image.png"], in: catalog))
      XCTAssertEqual(try Data(contentsOf: file), source)
      XCTAssertEqual(try Data(contentsOf: output), other)
      try FileManager.default.removeItem(at: file)
      XCTAssertEqual(LocalImageConversion.resolved(file), file)
    }
  }

  func testUnsupportedPNGAndMetadataRemainUntouched() throws {
    let samples = [png(depth: 16), png(extra: chunk("acTL", be(2) + be(0))),
                   png(extra: chunk("tEXt", Data("Author\0Original author".utf8)))]
    for source in samples {
      try fixture { root, catalog in
        let file = root.appendingPathComponent("original.PNG")
        try source.write(to: file)
        XCTAssertNil(try LocalImageConversion.convert(["original.PNG"], in: catalog))
        XCTAssertEqual(try Data(contentsOf: file), source)
      }
    }
  }

  func testNoSavingsKeepsOriginal() throws {
    try fixture { root, catalog in
      let source = png(width: 1, height: 1)
      let file = root.appendingPathComponent("tiny.png")
      try source.write(to: file)
      XCTAssertNil(try LocalImageConversion.convert(["tiny.png"], in: catalog))
      XCTAssertEqual(try Data(contentsOf: file), source)
    }
  }

  func testCorruptPNGAndOversizedDimensionsAreRejected() throws {
    var badCRC = png(); badCRC[29] ^= 255
    XCTAssertThrowsError(try LosslessPNG.encode(badCRC))
    let huge = Data([137, 80, 78, 71, 13, 10, 26, 10]) + chunk("IHDR", be(16384) + be(16384) + Data([8, 6, 0, 0, 0]))
    XCTAssertThrowsError(try LosslessPNG.encode(huge))
    XCTAssertThrowsError(try LosslessPNG.encode(Data(png().dropLast())))
  }

  func testRetryCompletesInterruptedPublicationWithoutReencoding() throws {
    try fixture { root, catalog in
      let file = root.appendingPathComponent("image.png"), source = png()
      try source.write(to: file)
      let result = try XCTUnwrap(LocalImageConversion.convert(["image.png"], in: catalog))
      try source.write(to: file)
      let retry = try XCTUnwrap(LocalImageConversion.convert(["image.png"], in: catalog))
      XCTAssertEqual(result.file, retry.file)
      XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
  }

  func testRecursiveCandidatesStayInsideFolderAndDoNotFollowLinks() throws {
    try fixture { root, catalog in
      let folder = root.appendingPathComponent("nested/deeper")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try png().write(to: folder.appendingPathComponent("image.png"))
      try Data([1]).write(to: root.appendingPathComponent("video.mp4"))
      try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: root.deletingLastPathComponent())
      let files = try catalog.storage(in: ["nested"]).files
      XCTAssertEqual(files.map(\.path), [["nested", "deeper", "image.png"]])
      XCTAssertNotNil(try LocalImageConversion.convert(files[0].path, in: catalog))
      XCTAssertThrowsError(try LocalImageConversion.convert(["outside", "image.png"], in: catalog))
    }
  }

  func testEveryPNGRowFilterReconstructsOriginalBytes() throws {
    let width = 3, height = 2, stride = width * 4
    let raw = (0..<(width * height * 4)).map { UInt8(($0 * 19 + 17) % 256) }
    for filter in 0...4 {
      var scanlines = Data()
      for y in 0..<height {
        scanlines.append(UInt8(filter))
        for x in 0..<stride {
          let a = x >= 4 ? Int(raw[y * stride + x - 4]) : 0
          let b = y > 0 ? Int(raw[(y - 1) * stride + x]) : 0
          let c = y > 0 && x >= 4 ? Int(raw[(y - 1) * stride + x - 4]) : 0
          let p = a + b - c
          let predictor = abs(p - a) <= abs(p - b) && abs(p - a) <= abs(p - c) ? a : abs(p - b) <= abs(p - c) ? b : c
          let delta = filter == 1 ? a : filter == 2 ? b : filter == 3 ? (a + b) / 2 : filter == 4 ? predictor : 0
          scanlines.append(UInt8(truncatingIfNeeded: Int(raw[y * stride + x]) - delta))
        }
      }
      let n = scanlines.count
      var z = Data([0x78, 0x01, 1, UInt8(n), 0, UInt8(255 - n), 255]) + scanlines
      var a = 1, b = 0
      for byte in scanlines { a = (a + Int(byte)) % 65521; b = (b + a) % 65521 }
      z.append(be((b << 16) | a))
      let decoded = z.withUnsafeBytes { FLPNGDecode($0.bindMemory(to: UInt8.self).baseAddress, z.count, Int32(width), Int32(height), 6, nil, 0, nil, 0) }
      let pixels = try XCTUnwrap(decoded)
      XCTAssertEqual(Data(bytes: pixels, count: raw.count), Data(raw))
      FLImageFree(pixels)
    }
  }
}
