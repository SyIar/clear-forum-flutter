import Foundation

struct MediaFileError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

// Bounded, disk-backed transfers. Never use the forum or shared cookie store.
final class MediaFileTransfer: NSObject, URLSessionDownloadDelegate {
  private let limit: Int64
  private let cookies: [HTTPCookie]
  private let referer: URL?
  private let progress: (Double?) -> Void
  private let event: (String) -> Void
  private var completion: ((Result<URL, Error>) -> Void)?
  private var session: URLSession?
  private var task: URLSessionDownloadTask?
  private var redirected = 0
  init(limit: Int64, cookies: [HTTPCookie] = [], referer: URL? = nil,
       progress: @escaping (Double?) -> Void, event: @escaping (String) -> Void = { _ in },
       completion: @escaping (Result<URL, Error>) -> Void) {
    self.limit = limit; self.cookies = cookies
    if let referer, var origin = URLComponents(url: referer, resolvingAgainstBaseURL: false) {
      origin.path = "/"; origin.query = nil; origin.fragment = nil; origin.user = nil; origin.password = nil
      self.referer = origin.url
    } else { self.referer = nil }
    self.progress = progress; self.event = event; self.completion = completion
  }
  func start(_ url: URL) {
    guard MediaPolicy.allowed(url) else { finish(.failure(MediaFileError(message: "The media address is not supported."))); return }
    if MediaFilePolicy.isHLS(url, mime: nil) {
      finish(.failure(MediaFileError(message: "This is an HLS stream. Saving it to Photos is not supported yet."))); return
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 7200
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    task = session?.downloadTask(with: request(url))
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
    return request
  }
  func cancel() {
    task?.cancel()
    finish(.failure(CancellationError()))
  }
  private func finish(_ result: Result<URL, Error>) {
    guard let completion else { return }
    self.completion = nil
    session?.invalidateAndCancel(); session = nil; task = nil
    completion(result)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    redirected += 1
    guard redirected <= 5, let url = newRequest.url, MediaPolicy.allowed(url) else {
      completionHandler(nil); finish(.failure(MediaFileError(message: "The download redirected to an unsupported address."))); return
    }
    event("Redirect HTTP \(response.statusCode)")
    // Rebuild headers so credentials never cross to a nonmatching host/path.
    completionHandler(request(url))
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard completion != nil else { return }
    if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
      finish(.failure(MediaFileError(message: "The file exceeds the download size limit."))); return
    }
    progress(totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard completion != nil else { return }
    do {
      guard let http = downloadTask.response as? HTTPURLResponse, let url = http.url else {
        throw MediaFileError(message: "The server returned an invalid response.")
      }
      let bytes = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
      event("HTTP \(http.statusCode), MIME \(MediaDiagnostics.mime(http.mimeType)), bytes \(bytes)")
      if let error = MediaFilePolicy.responseError(status: http.statusCode, mime: http.mimeType, url: url, bytes: bytes, limit: limit) {
        throw MediaFileError(message: error)
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
    guard let error, completion != nil else { return }
    let value = error as NSError
    event("Network \(MediaDiagnostics.domain(value.domain)) code=\(value.code)")
    finish(.failure(MediaFileError(message: "The download could not finish. Check your connection or refresh the source.")))
  }
}
