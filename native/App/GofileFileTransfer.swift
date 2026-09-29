import Foundation

// A separate transfer policy: arbitrary files go to Files, never through the video/Photos pipeline.
final class GofileFileTransfer: NSObject, URLSessionDownloadDelegate {
  // Main-queue scheduler shared by all native Gofile viewers, including thumbnails.
  private static var waiting: [(GofileFileTransfer, URL)] = []
  private static var active: GofileFileTransfer?
  private static var cooldown = Date.distantPast
  private static var wake: DispatchWorkItem?
  static func slowDown(until date: Date) {
    cooldown = max(cooldown, date)
  }
  private let cookies: [HTTPCookie]
  private let userAgent: String
  private let name: String
  private let expectedBytes: Int64?
  private let mime: String
  private let limit: Int64
  private let progress: (Double?) -> Void
  private var completion: ((Result<URL, Error>) -> Void)?
  private var session: URLSession?
  private var task: URLSessionDownloadTask?
  private var redirects = 0
  init(name: String, expectedBytes: Int64?, mime: String, cookies: [HTTPCookie], userAgent: String,
       limit: Int64 = GofilePolicy.fileLimit, progress: @escaping (Double?) -> Void,
       completion: @escaping (Result<URL, Error>) -> Void) {
    self.name = name; self.expectedBytes = expectedBytes; self.mime = mime
    self.cookies = cookies; self.userAgent = userAgent; self.limit = limit
    self.progress = progress; self.completion = completion
  }
  func start(_ url: URL) {
    Self.waiting.append((self, url))
    Self.startNext()
  }
  private static func startNext() {
    guard active == nil, !waiting.isEmpty else { return }
    guard cooldown <= Date() else {
      wake?.cancel()
      let item = DispatchWorkItem { startNext() }; wake = item
      DispatchQueue.main.asyncAfter(deadline: .now() + min(3600, cooldown.timeIntervalSinceNow), execute: item)
      return
    }
    wake?.cancel(); wake = nil
    let (transfer, url) = waiting.removeFirst()
    active = transfer; transfer.begin(url)
  }
  private func begin(_ url: URL) {
    guard GofilePolicy.fileURL(url), expectedBytes.map({ $0 <= limit }) ?? true else {
      fail("This file address is unavailable or the file exceeds the download limit."); return
    }
    if let expectedBytes,
       let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
       let available = values.volumeAvailableCapacityForImportantUsage, expectedBytes > max(0, available - 64 * 1024 * 1024) {
      fail("There is not enough free space for this file."); return
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil; configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 7200
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    task = session?.downloadTask(with: request(url)); task?.resume()
  }
  private func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.httpShouldHandleCookies = false
    for (key, value) in HTTPCookie.requestHeaderFields(with: cookies.filter { MediaPolicy.cookieMatches($0, url) }) {
      request.setValue(value, forHTTPHeaderField: key)
    }
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("https://gofile.io/", forHTTPHeaderField: "Referer")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return request
  }
  func cancel() { finish(.failure(CancellationError())) }
  private func fail(_ message: String) { finish(.failure(MediaFileError(message: message))) }
  private func finish(_ result: Result<URL, Error>) {
    guard let completion else { return }
    self.completion = nil
    if case .failure(let error) = result, let date = (error as? GofileFailure)?.retryDate { Self.slowDown(until: date) }
    session?.invalidateAndCancel(); session = nil; task = nil
    Self.waiting.removeAll { $0.0 === self }
    if Self.active === self { Self.active = nil }
    completion(result)
    Self.startNext()
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    redirects += 1
    guard redirects <= 5, let url = newRequest.url, GofilePolicy.fileURL(url),
          url.path.split(separator: "/").dropFirst(2).first == task.originalRequest?.url?.path.split(separator: "/").dropFirst(2).first else {
      completionHandler(nil)
      fail("Gofile redirected to a web page instead of the file. Refresh the folder, or open the website to restore access.")
      return
    }
    completionHandler(request(url))
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard completion != nil else { return }
    guard totalBytesWritten <= limit, totalBytesExpectedToWrite <= limit else { fail("This file exceeds the download size limit."); return }
    let expected = expectedBytes ?? totalBytesExpectedToWrite
    progress(expected > 0 ? min(1, Double(totalBytesWritten) / Double(expected)) : nil)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard completion != nil else { return }
    var directory: URL?
    do {
      guard let response = downloadTask.response as? HTTPURLResponse, let url = response.url else { throw MediaFileError(message: "Invalid download response.") }
      if response.statusCode == 429 || response.statusCode == 503 {
        let retry = response.value(forHTTPHeaderField: "Retry-After")
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let date = retry.flatMap { format.date(from: $0) }
          ?? Date().addingTimeInterval(max(60, retry.flatMap(Double.init) ?? 60))
        throw GofileFailure.rateLimited(date)
      }
      if response.statusCode == 404 || response.statusCode == 410 { throw GofileFailure.notFound }
      if response.statusCode == 401 || response.statusCode == 403 { throw GofileFailure.access }
      let bytes = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
      let handle = try FileHandle(forReadingFrom: location)
      let prefix = try handle.read(upToCount: 512) ?? Data()
      try handle.close()
      if let error = GofilePolicy.responseError(status: response.statusCode, url: url, mime: response.mimeType, expectedMIME: mime,
                                                bytes: bytes, expectedBytes: expectedBytes, prefix: prefix, limit: limit) {
        throw MediaFileError(message: error)
      }
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gofile-\(UUID().uuidString)", isDirectory: true)
      directory = folder
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let file = folder.appendingPathComponent(GofilePolicy.filename(name))
      try FileManager.default.moveItem(at: location, to: file)
      try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
      finish(.success(file))
    } catch {
      if let directory { try? FileManager.default.removeItem(at: directory) }
      finish(.failure(error))
    }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, completion != nil else { return }
    if (error as NSError).code == NSURLErrorCancelled { finish(.failure(CancellationError())) }
    else { fail("The file could not finish downloading. Check the connection and try again.") }
  }
  static func remove(_ file: URL) {
    let parent = file.deletingLastPathComponent()
    guard parent.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL,
          parent.lastPathComponent.hasPrefix("gofile-") else { return }
    try? FileManager.default.removeItem(at: parent)
  }
}
