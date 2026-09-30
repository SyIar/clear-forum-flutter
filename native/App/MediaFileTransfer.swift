import Foundation

struct MediaFileError: Error, LocalizedError {
  let message: String
  var resumeData: Data? = nil
  var refreshSource = false
  var errorDescription: String? { message }
}

struct MediaTransferPaused: Error { let resumeData: Data? }

// Bounded, disk-backed transfers. Never use the forum or shared cookie store.
final class MediaFileTransfer: NSObject, URLSessionDownloadDelegate {
  private let limit: Int64
  private let cookies: [HTTPCookie]
  private let referer: URL?
  private let progress: (Double?) -> Void
  private let event: (String) -> Void
  private let byteProgress: (Int64, Int64) -> Void
  private var completion: ((Result<URL, Error>) -> Void)?
  private var session: URLSession?
  private var task: URLSessionDownloadTask?
  private var redirected = 0
  private var pausing = false
  private var resuming = false
  private var expectedBytes: Int64?
  private var lastProgress = Date.distantPast
  private var checkedCapacity = false
  init(limit: Int64, cookies: [HTTPCookie] = [], referer: URL? = nil,
       progress: @escaping (Double?) -> Void, event: @escaping (String) -> Void = { _ in },
       byteProgress: @escaping (Int64, Int64) -> Void = { _, _ in },
       completion: @escaping (Result<URL, Error>) -> Void) {
    self.limit = limit; self.cookies = cookies
    if let referer, var origin = URLComponents(url: referer, resolvingAgainstBaseURL: false) {
      origin.path = "/"; origin.query = nil; origin.fragment = nil; origin.user = nil; origin.password = nil
      self.referer = origin.url
    } else { self.referer = nil }
    self.progress = progress; self.event = event; self.byteProgress = byteProgress; self.completion = completion
  }
  func start(_ url: URL, resumeData: Data? = nil) {
    guard MediaPolicy.allowed(url) else { finish(.failure(MediaFileError(message: AppText.text("The media address is not supported.")))); return }
    if MediaFilePolicy.isHLS(url, mime: nil) {
      finish(.failure(MediaFileError(message: AppText.text("This is an HLS stream. Saving it to Photos is not supported yet.")))); return
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 7200
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    resuming = resumeData != nil
    if let resumeData { task = session?.downloadTask(withResumeData: resumeData) }
    else { task = session?.downloadTask(with: request(url)) }
    event("Started file transfer")
    task?.resume()
  }
  private func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.httpShouldHandleCookies = false
    for (name, value) in HTTPCookie.requestHeaderFields(with: cookies.filter { MediaPolicy.cookieMatches($0, url) }) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return request
  }
  func cancel() {
    task?.cancel()
    finish(.failure(CancellationError()))
  }
  func pause() {
    guard completion != nil, !pausing else { return }
    pausing = true
    guard let task else { finish(.failure(MediaTransferPaused(resumeData: nil))); return }
    task.cancel(byProducingResumeData: { [weak self] data in
      DispatchQueue.main.async { self?.finish(.failure(MediaTransferPaused(resumeData: data))) }
    })
  }
  private func finish(_ result: Result<URL, Error>) {
    guard let completion else { return }
    self.completion = nil
    if case .failure(let error) = result,
       error is MediaTransferPaused || (error as? MediaFileError)?.resumeData != nil {
      session?.finishTasksAndInvalidate()
    } else { session?.invalidateAndCancel() }
    session = nil; task = nil
    completion(result)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    redirected += 1
    guard redirected <= 5, let url = newRequest.url, MediaPolicy.allowed(url) else {
      completionHandler(nil); finish(.failure(MediaFileError(message: AppText.text("The download redirected to an unsupported address.")))); return
    }
    event("Redirect HTTP \(response.statusCode)")
    // Rebuild headers so credentials never cross to a nonmatching host/path.
    var redirectedRequest = request(url)
    // Preserve the system's range validator for a legitimate resumed redirect.
    for name in ["Range", "If-Range"] {
      redirectedRequest.setValue(newRequest.value(forHTTPHeaderField: name), forHTTPHeaderField: name)
    }
    completionHandler(redirectedRequest)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard completion != nil else { return }
    if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
      finish(.failure(MediaFileError(message: AppText.text("The file exceeds the download size limit.")))); return
    }
    if !checkedCapacity, totalBytesExpectedToWrite > 0 {
      checkedCapacity = true
      if let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
         let available = values.volumeAvailableCapacityForImportantUsage,
         totalBytesExpectedToWrite - totalBytesWritten > max(0, available - 64 * 1024 * 1024) {
        finish(.failure(MediaFileError(message: AppText.text("There is not enough free space for this file.")))); return
      }
    }
    if totalBytesExpectedToWrite > 0 { expectedBytes = totalBytesExpectedToWrite }
    guard Date().timeIntervalSince(lastProgress) >= 0.15 || totalBytesWritten == totalBytesExpectedToWrite else { return }
    lastProgress = Date()
    byteProgress(totalBytesWritten, totalBytesExpectedToWrite)
    progress(totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
    resuming = true
    if expectedTotalBytes > 0 { expectedBytes = expectedTotalBytes }
    byteProgress(fileOffset, expectedTotalBytes)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard completion != nil else { return }
    do {
      guard let http = downloadTask.response as? HTTPURLResponse, let url = http.url else {
        throw MediaFileError(message: AppText.text("The server returned an invalid response."))
      }
      let bytes = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
      event("HTTP \(http.statusCode), MIME \(MediaDiagnostics.mime(http.mimeType)), bytes \(bytes)")
      guard MediaPolicy.allowed(url) else { throw MediaFileError(message: AppText.text("Unsupported download address.")) }
      if let error = MediaFilePolicy.responseError(status: http.statusCode, mime: http.mimeType, url: url, bytes: bytes, limit: limit,
        resumed: resuming, contentRange: http.value(forHTTPHeaderField: "Content-Range"), expectedBytes: http.statusCode == 206 ? nil : expectedBytes) {
        throw MediaFileError(message: error, refreshSource: [401, 403, 404, 410].contains(http.statusCode) || ["text/html", "application/json"].contains(http.mimeType ?? ""))
      }
      let extensions = ["video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm", "video/x-matroska": "mkv",
                        "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp", "image/heic": "heic", "image/avif": "avif"]
      let known = Set(extensions.values).union(["m4v", "jpeg"])
      let ext = extensions[http.mimeType?.lowercased() ?? ""] ?? (known.contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "bin")
      let saved = FileManager.default.temporaryDirectory.appendingPathComponent("forum-media-\(UUID().uuidString).\(ext)")
      try FileManager.default.moveItem(at: location, to: saved)
      finish(.success(saved))
    } catch { finish(.failure(error)) }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, completion != nil, !pausing else { return }
    let value = error as NSError
    event("Network \(MediaDiagnostics.domain(value.domain)) code=\(value.code)")
    let diskError = value.domain == NSURLErrorDomain && [URLError.cannotCreateFile.rawValue, URLError.cannotWriteToFile.rawValue].contains(value.code)
    finish(.failure(MediaFileError(message: diskError ? AppText.text("Could not write the download. Check free space and try again.") : AppText.text("The download could not finish. Check your connection and try again."), resumeData: value.userInfo[NSURLSessionDownloadTaskResumeData] as? Data)))
  }
}
