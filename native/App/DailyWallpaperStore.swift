import SwiftUI
import ImageIO

private final class WallpaperRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(request.url.map(BingWallpaper.accepts) == true ? request : nil)
  }
}

private actor DailyWallpaperService {
  private let session: URLSession
  private let cache: URL?
  private let maximumImageBytes = 8 * 1024 * 1024

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 45
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration, delegate: WallpaperRedirectPolicy(), delegateQueue: nil)
    cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("DailyWallpaper", isDirectory: true).appendingPathComponent("current.plist")
  }

  func cached() -> BingWallpaperSnapshot? {
    guard let cache,
          let size = try? cache.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          size <= maximumImageBytes + 64 * 1024,
          let data = try? Data(contentsOf: cache),
          let snapshot = try? PropertyListDecoder().decode(BingWallpaperSnapshot.self, from: data),
          BingWallpaper.accepts(snapshot.wallpaper.source), validImage(snapshot.image) else { return nil }
    return snapshot
  }

  func fetch(previous: BingWallpaperSnapshot?) async throws -> BingWallpaperSnapshot {
    let data = try await receive(BingWallpaper.archive, limit: 128 * 1024, image: false)
    let wallpaper = try BingWallpaper.parse(data)
    let image: Data
    if let previous, previous.wallpaper.id == wallpaper.id, validImage(previous.image) {
      image = previous.image
    } else {
      var downloaded: Data?
      for url in wallpaper.images {
        do {
          let candidate = try await receive(url, limit: maximumImageBytes, image: true)
          guard validImage(candidate) else { continue }
          downloaded = candidate
          break
        } catch {
          try Task.checkCancellation()
        }
      }
      guard let downloaded else { throw BingWallpaper.Failure.invalidResponse }
      image = downloaded
    }
    try Task.checkCancellation()
    let snapshot = BingWallpaperSnapshot(wallpaper: wallpaper, image: image, checkedDay: BingWallpaper.dayKey(Date()))
    if let cache {
      try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = PropertyListEncoder()
      encoder.outputFormat = .binary
      if let encoded = try? encoder.encode(snapshot) { try? encoded.write(to: cache, options: .atomic) }
    }
    return snapshot
  }

  private func receive(_ url: URL, limit: Int, image: Bool) async throws -> Data {
    guard BingWallpaper.accepts(url) else { throw BingWallpaper.Failure.invalidResponse }
    var request = URLRequest(url: url)
    request.httpShouldHandleCookies = false
    request.setValue(image ? "image/jpeg,image/png" : "application/json", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          response.url.map(BingWallpaper.accepts) == true,
          !image || ["image/jpeg", "image/png"].contains(response.mimeType ?? "") else {
      bytes.task.cancel()
      throw BingWallpaper.Failure.invalidResponse
    }
    guard response.expectedContentLength <= Int64(limit) else {
      bytes.task.cancel()
      throw BingWallpaper.Failure.oversizedImage
    }
    var data = Data()
    do {
      for try await byte in bytes {
        guard data.count < limit else { throw BingWallpaper.Failure.oversizedImage }
        data.append(byte)
      }
      return data
    } catch {
      bytes.task.cancel()
      throw error
    }
  }

  private func validImage(_ data: Data) -> Bool {
    guard data.count <= maximumImageBytes,
          let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width >= 720, height >= 720, width <= 4096, height <= 4096 else { return false }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) != nil
  }
}

@MainActor final class DailyWallpaperStore: ObservableObject {
  @Published private(set) var image: UIImage?
  @Published private(set) var wallpaper: BingWallpaper?
  private let service = DailyWallpaperService()
  private var snapshot: BingWallpaperSnapshot?
  private var lastAttempt: Date?

  func run() async {
    if snapshot == nil, let cached = await service.cached() { await display(cached) }
    while !Task.isCancelled {
      let now = Date()
      if snapshot?.isCurrent(at: now) != true,
         lastAttempt.map({ now.timeIntervalSince($0) >= 300 || BingWallpaper.dayKey($0) != BingWallpaper.dayKey(now) }) ?? true {
        lastAttempt = now
        do {
          let fresh = try await service.fetch(previous: snapshot)
          try Task.checkCancellation()
          await display(fresh)
        } catch {
          if Task.isCancelled { lastAttempt = nil; return }
          // Keep the previous wallpaper while offline or if the archive is late.
        }
      }
      let current = Date()
      let delay = snapshot?.isCurrent(at: current) == true
        ? min(300, BingWallpaper.nextMidnight(after: current).timeIntervalSince(current)) : 300
      do { try await Task.sleep(for: .seconds(max(1, delay))) }
      catch { return }
    }
  }

  private func display(_ next: BingWallpaperSnapshot) async {
    if snapshot?.wallpaper.id != next.wallpaper.id || image == nil {
      guard let decoded = UIImage(data: next.image) else { return }
      let prepared = await decoded.byPreparingForDisplay() ?? decoded
      guard !Task.isCancelled else { return }
      image = prepared
    }
    snapshot = next
    wallpaper = next.wallpaper
  }
}
