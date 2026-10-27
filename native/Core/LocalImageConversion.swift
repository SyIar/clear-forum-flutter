import Foundation
import CryptoKit

enum LocalImageConversion {
  struct Origin: Codable {
    let name: String
    let bytes: Int
    let hash: String
    let outputHash: String
  }
  struct Result: Sendable {
    let original: URL
    let file: URL
    let savedBytes: Int64
  }
  enum Failure: Error { case changed }
  static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

  /// Resolve old queue/gallery paths only to a file carrying our exact origin tag.
  static func resolved(_ file: URL) -> URL {
    guard file.isFileURL, file.pathExtension.lowercased() == "png", !FileManager.default.fileExists(atPath: file.path) else { return file }
    let output = file.deletingPathExtension().appendingPathExtension("webp")
    guard let values = try? output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          values.isRegularFile == true, values.isSymbolicLink != true,
          let metadata = LocalFileMetadata.read(LocalFileMetadata.conversionKey, at: output),
          let origin = try? JSONDecoder().decode(Origin.self, from: metadata), origin.name == file.lastPathComponent else { return file }
    return output
  }

  /// Work stays in a sibling staging file until verified and durably written.
  /// A crash before original removal leaves both copies; retry verifies and completes it.
  static func convert(_ path: [String], in catalog: LocalFileCatalog) throws -> Result? {
    let file = try catalog.url(for: path)
    guard file.pathExtension.lowercased() == "png" else { return nil }
    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey])
    guard values.isRegularFile == true, let bytes = values.fileSize, bytes > 0, bytes <= LosslessPNG.maximumBytes else { return nil }
    let data = try Data(contentsOf: file)
    guard data.count == bytes else { throw Failure.changed }
    let digest = hash(data)
    let destination = file.deletingPathExtension().appendingPathExtension("webp")
    let originalDate = LocalFileMetadata.arrival(at: file)
    func unchanged() throws {
      try Task.checkCancellation()
      guard try catalog.url(for: path) == file,
            try hash(Data(contentsOf: file)) == digest else { throw Failure.changed }
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      guard let metadata = LocalFileMetadata.read(LocalFileMetadata.conversionKey, at: destination),
            let origin = try? JSONDecoder().decode(Origin.self, from: metadata),
            origin.name == file.lastPathComponent, origin.hash == digest, origin.bytes == bytes,
            (try? catalog.url(for: Array(path.dropLast()) + [destination.lastPathComponent])) == destination else { return nil }
      let existing = try Data(contentsOf: destination)
      guard existing.count < bytes, hash(existing) == origin.outputHash else { return nil }
      try unchanged()
      try FileManager.default.removeItem(at: file)
      return Result(original: file, file: destination, savedBytes: Int64(bytes - existing.count))
    }
    let output: Data
    do { output = try LosslessPNG.encode(data) }
    catch LosslessPNG.Failure.unsupported { return nil }
    guard output.count < bytes else { return nil }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("image-conversion-\(UUID().uuidString).webp")
    defer { try? FileManager.default.removeItem(at: staging) }
    try output.write(to: staging, options: .withoutOverwriting)
    let handle = try FileHandle(forWritingTo: staging)
    try handle.synchronize(); try handle.close()
    guard hash(try Data(contentsOf: staging)) == hash(output) else { throw Failure.changed }
    var attributes: [FileAttributeKey: Any] = [:]
    if let date = values.creationDate { attributes[.creationDate] = date }
    if let date = values.contentModificationDate { attributes[.modificationDate] = date }
    try FileManager.default.setAttributes(attributes, ofItemAtPath: staging.path)
    if let originalDate { try LocalFileMetadata.arrived(staging, at: originalDate) }
    try LocalFileMetadata.write(JSONEncoder().encode(Origin(name: file.lastPathComponent, bytes: bytes, hash: digest, outputHash: hash(output))),
      key: LocalFileMetadata.conversionKey, at: staging)
    try unchanged()
    // moveItem does not overwrite a colliding file created by Files or another job.
    try FileManager.default.moveItem(at: staging, to: destination)
    try unchanged()
    try FileManager.default.removeItem(at: file)
    return Result(original: file, file: destination, savedBytes: Int64(bytes - output.count))
  }
}
