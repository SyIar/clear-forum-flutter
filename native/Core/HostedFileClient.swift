import Foundation

// Metadata requests carry no forum cookies, credentials, or browser account state.
@MainActor
final class HostedFileClient {
  typealias MetadataLoader = (URL, FileHost, [String: String]?, URL?) async throws -> Data
  private let loadMetadata: MetadataLoader?
  init(loadMetadata: MetadataLoader? = nil) { self.loadMetadata = loadMetadata }
  private static var cooldowns: [FileHost: Date] = [:]
  nonisolated static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1"

  func listing(_ url: URL, expandAlbum: Bool = true) async throws -> HostedFileListing {
    guard let provider = HostedFilePolicy.provider(url) else { throw HostedFileFailure.unsupported }
    switch provider {
    case .fileditch:
      let entry = HostedFileEntry(pageURL: url, name: url.lastPathComponent, mime: HostedFilePolicy.mime(url.lastPathComponent))
      return HostedFileListing(url: url, title: entry.name, entries: [entry])
    case .pixeldrain:
      let id = url.lastPathComponent
      let path = HostedFilePolicy.isFolder(url) ? "list/\(id)" : "file/\(id)/info"
      let data = try await metadata(URL(string: "https://pixeldrain.com/api/" + path)!, provider: provider)
      return try HostedFileParser.pixeldrain(data, url: url)
    case .bunkr:
      if HostedFilePolicy.isFolder(url) {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "advanced", value: "1")]; parts.fragment = nil
        let data = try await metadata(parts.url!, provider: provider)
        return try HostedFileParser.bunkrAlbum(String(decoding: data, as: UTF8.self), url: url)
      }
      let data = try await metadata(url, provider: provider)
      let (entry, album) = try HostedFileParser.bunkrFile(String(decoding: data, as: UTF8.self), url: url)
      if expandAlbum, let album {
        var result = try await listing(album, expandAlbum: false)
        result.expandedAlbum = true
        return result
      }
      return HostedFileListing(url: url, title: entry.name, entries: [entry])
    case .filester:
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
      parts.query = nil; parts.fragment = nil
      let data = try await metadata(parts.url!, provider: provider)
      let first = try HostedFileParser.filester(String(decoding: data, as: UTF8.self), url: url)
      guard first.pages > 1 else { return first }
      var entries = first.entries, seen = Set(first.entries.map(\.id))
      for page in 2...first.pages {
        try await Task.sleep(for: .milliseconds(700))
        parts.queryItems = [URLQueryItem(name: "page", value: String(page))]
        let data = try await metadata(parts.url!, provider: provider)
        let listing = try HostedFileParser.filester(String(decoding: data, as: UTF8.self), url: url)
        let additions = listing.entries.filter { seen.insert($0.id).inserted }
        guard !additions.isEmpty else { throw HostedFileFailure.format }
        entries += additions
        guard entries.count <= 10000 else { throw HostedFileFailure.limit }
      }
      return HostedFileListing(url: url, title: first.title, entries: entries)
    }
  }

  // Called only after this item owns the shared serial transfer slot.
  func resolve(_ entry: HostedFileEntry, download: Bool = true) async throws -> HostedFileRequest {
    guard !entry.folder, let provider = HostedFilePolicy.provider(entry.pageURL) else { throw HostedFileFailure.unsupported }
    switch provider {
    case .fileditch:
      return HostedFileRequest(url: entry.pageURL, referer: entry.pageURL, name: entry.name, size: entry.size, mime: entry.mime)
    case .pixeldrain:
      return HostedFileRequest(url: URL(string: "https://pixeldrain.com/api/file/\(entry.pageURL.lastPathComponent)" + (download ? "?download" : ""))!,
                               referer: entry.pageURL, name: entry.name, size: entry.size, mime: entry.mime)
    case .filester:
      let data = try await metadata(URL(string: "https://filester.me/v2/api/public/" + (download ? "download" : "view"))!, provider: provider,
                                    body: ["file_slug": entry.pageURL.lastPathComponent], referer: entry.pageURL)
      return try HostedFileParser.filesterDownload(data, entry: entry, download: download)
    case .bunkr:
      var item = entry
      if item.remoteID == nil {
        guard let found = try await listing(entry.pageURL, expandAlbum: false).entries.first else { throw HostedFileFailure.missing }
        item = found
      }
      guard let id = item.remoteID else { throw HostedFileFailure.format }
      let data = try await metadata(URL(string: "https://apidl.bunkr.ru/api/_001_v2")!, provider: provider,
                                    body: ["id": id], referer: URL(string: "https://get.bunkrr.su/file/" + id)!)
      return try HostedFileParser.bunkrDownload(data, entry: item)
    }
  }

  private func metadata(_ url: URL, provider: FileHost, body: [String: String]? = nil, referer: URL? = nil) async throws -> Data {
    try Task.checkCancellation()
    if let date = Self.cooldowns[provider], date > Date() { throw HostedFileFailure.rateLimited(date) }
    if let loadMetadata { return try await loadMetadata(url, provider, body, referer) }
    do { return try await Self.fetchMetadata(url, provider: provider, body: body, referer: referer) }
    catch {
      if let date = (error as? HostedFileFailure)?.retryDate { Self.cooldowns[provider] = date }
      throw error
    }
  }

  // Reading an album's byte stream must not run byte-by-byte on the UI actor.
  nonisolated private static func fetchMetadata(_ url: URL, provider: FileHost, body: [String: String]?, referer: URL?) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil; configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 60
    let delegate = HostedMetadataRedirect(provider: provider, original: url)
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("text/html, application/json", forHTTPHeaderField: "Accept")
    if let referer {
      request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
      request.setValue("https://" + (referer.host ?? ""), forHTTPHeaderField: "Origin")
    }
    if let body {
      request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw HostedFileFailure.format }
    switch http.statusCode {
    case 200: break
    case 401, 403, 424, 451: throw HostedFileFailure.access
    case 404, 410: throw HostedFileFailure.missing
    case 429, 503:
      let date = HostedFilePolicy.retryDate(http.value(forHTTPHeaderField: "Retry-After"))
      throw HostedFileFailure.rateLimited(date)
    default: throw HostedFileFailure.format
    }
    let limit = 8 * 1024 * 1024
    guard response.expectedContentLength <= Int64(limit) else { throw HostedFileFailure.limit }
    var data = Data()
    for try await byte in bytes {
      guard data.count < limit else { throw HostedFileFailure.limit }
      data.append(byte)
    }
    try Task.checkCancellation()
    return data
  }
}

private final class HostedMetadataRedirect: NSObject, URLSessionTaskDelegate {
  let provider: FileHost
  let original: URL
  private var count = 0
  init(provider: FileHost, original: URL) { self.provider = provider; self.original = original }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    count += 1
    guard count <= 4, let url = request.url, HostedFilePolicy.publicHTTPS(url),
          url.host == original.host || (provider == .bunkr && HostedFilePolicy.provider(url) == .bunkr) else {
      completionHandler(nil); return
    }
    var clean = request
    clean.setValue(nil, forHTTPHeaderField: "Cookie"); clean.setValue(nil, forHTTPHeaderField: "Authorization")
    completionHandler(clean)
  }
}
