import Foundation

// A separate transfer policy: arbitrary files go to Files, never through the video/Photos pipeline.
final class GofileFileTransfer: NSObject, URLSessionDownloadDelegate {
  // Main-queue scheduler shared by file-host viewers and Gofile thumbnails.
  private static var waiting: [(GofileFileTransfer, URL)] = []
  private static var active: GofileFileTransfer?
  private static var cooldown = Date.distantPast
  private static var wake: DispatchWorkItem?
  private static var recovery = Set<UUID>()
  static func reserveRecovery(_ id: UUID) { recovery.insert(id) }
  static func releaseRecovery(_ id: UUID) { recovery.remove(id); startNext() }
  static func slowDown(until date: Date) {
    cooldown = max(cooldown, date)
  }
  private var cookies: [HTTPCookie]
  private var userAgent: String
  private let checkpointID: UUID?
  private var checkpoint: FileTransferCheckpoint?
  private var resumed = false
  private var cancelling = false
  private let name: String
  private let expectedBytes: Int64?
  private let mime: String
  private let limit: Int64
  private let progress: (Double?) -> Void
  private let activity: (FileTransferActivity) -> Void
  private var completion: ((Result<URL, Error>) -> Void)?
  private var session: URLSession?
  private var task: URLSessionDownloadTask?
  private var redirects = 0
  private let prepare: (() async throws -> HostedFileRequest)?
  private var preparing: Task<Void, Never>?
  private var hosted: HostedFileRequest?
  private var fileSize: Int64? { hosted?.size ?? expectedBytes }
  init(name: String, expectedBytes: Int64?, mime: String, cookies: [HTTPCookie], userAgent: String,
       limit: Int64 = GofilePolicy.fileLimit, checkpointID: UUID? = nil, prepare: (() async throws -> HostedFileRequest)? = nil,
       activity: @escaping (FileTransferActivity) -> Void = { _ in },
       progress: @escaping (Double?) -> Void,
       completion: @escaping (Result<URL, Error>) -> Void) {
    self.name = name; self.expectedBytes = expectedBytes; self.mime = mime
    self.cookies = cookies; self.userAgent = userAgent; self.limit = limit
    self.progress = progress; self.completion = completion
    self.prepare = prepare
    self.activity = activity
    self.checkpointID = checkpointID
  }
  func start(_ url: URL) {
    activity(.waiting)
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
    // Reattach the system's existing transfer before starting newly queued files.
    let index: Int
    if !recovery.isEmpty {
      guard let found = waiting.firstIndex(where: { $0.0.checkpointID.map { recovery.contains($0) } == true }) else { return }
      index = found
    } else { index = 0 }
    let (transfer, url) = waiting.remove(at: index)
    active = transfer; transfer.prepareAndBegin(url)
  }
  private func prepareAndBegin(_ url: URL) {
    if let checkpointID, let saved = try? FileDownloadStore.load(FileTransferCheckpoint.self, name: checkpointID.uuidString),
       saved.hosted?.accepts(saved.url) ?? GofilePolicy.fileURL(saved.url) {
      checkpoint = saved; hosted = saved.hosted; cookies = saved.cookies.compactMap(\.cookie); userAgent = saved.userAgent
      begin(saved.url); return
    }
    guard let prepare else { begin(url); return }
    activity(.resolving)
    preparing = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let resolved = try await prepare()
        try Task.checkCancellation()
        guard self.completion != nil else { return }
        self.hosted = resolved
        self.begin(resolved.url)
      } catch { self.finish(.failure(error)) }
      self.preparing = nil
    }
  }
  private func begin(_ url: URL) {
    guard hosted?.accepts(url) ?? GofilePolicy.fileURL(url), fileSize.map({ $0 <= limit }) ?? true else {
      fail(AppText.text("This file address is unavailable or the file exceeds the download limit.")); return
    }
    if let expectedBytes = fileSize,
       let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
       let available = values.volumeAvailableCapacityForImportantUsage, expectedBytes > max(0, available - 64 * 1024 * 1024) {
      fail(AppText.text("There is not enough free space for this file.")); return
    }
    let configuration: URLSessionConfiguration
    if let checkpointID {
      configuration = .background(withIdentifier: FileBackgroundEvents.identifier(checkpointID))
      configuration.sessionSendsLaunchEvents = true; configuration.isDiscretionary = false
      if checkpoint == nil { checkpoint = FileTransferCheckpoint(url: url, hosted: hosted, cookies: cookies.map(VideoDownloadCookie.init), userAgent: userAgent) }
      do { try FileDownloadStore.save(checkpoint, name: checkpointID.uuidString) }
      catch { finish(.failure(error)); return }
    } else { configuration = .ephemeral }
    // Background redirects are handled by the system. Let its cookie jar apply
    // domain/path rules instead of forwarding a hand-built Cookie header.
    let systemCookies = checkpointID != nil && hosted == nil
    configuration.httpCookieStorage = systemCookies ? HTTPCookieStorage.shared : nil
    configuration.httpShouldSetCookies = systemCookies
    if systemCookies {
      for cookie in cookies where MediaPolicy.cookieMatches(cookie, url) { HTTPCookieStorage.shared.setCookie(cookie) }
    }
    configuration.urlCredentialStorage = nil; configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 7200
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    session?.getAllTasks { [weak self] tasks in
      DispatchQueue.main.async {
        guard let self, self.completion != nil, !self.cancelling else { return }
        if let existing = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first {
          self.task = existing; self.resumed = true
        } else if let data = self.checkpoint?.data {
          self.task = self.session?.downloadTask(withResumeData: data); self.resumed = true
        } else { self.task = self.session?.downloadTask(with: self.request(url)) }
        self.activity(.downloading); self.task?.resume()
      }
    }
  }
  private func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.httpShouldHandleCookies = checkpointID != nil && hosted == nil
    for (key, value) in HTTPCookie.requestHeaderFields(with: hosted == nil && checkpointID == nil ? cookies.filter { MediaPolicy.cookieMatches($0, url) } : []) {
      request.setValue(value, forHTTPHeaderField: key)
    }
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(hosted?.referer.absoluteString ?? "https://gofile.io/", forHTTPHeaderField: "Referer")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return request
  }
  func cancel() {
    guard !cancelling, completion != nil else { return }
    cancelling = true
    guard checkpointID != nil, let task else { finish(.failure(CancellationError())); return }
    task.cancel(byProducingResumeData: { [weak self] data in
      DispatchQueue.main.async {
        guard let self else { return }
        self.keepResumeData(data); self.finish(.failure(CancellationError()))
      }
    })
  }
  private func keepResumeData(_ data: Data?) {
    guard let checkpointID, var checkpoint else { return }
    checkpoint.data = data; self.checkpoint = checkpoint
    try? FileDownloadStore.save(checkpoint, name: checkpointID.uuidString)
  }
  private func fail(_ message: String) { finish(.failure(MediaFileError(message: message))) }
  private func finish(_ result: Result<URL, Error>) {
    guard let completion else { return }
    self.completion = nil
    if case .failure(let error) = result, let date = (error as? GofileFailure)?.retryDate { Self.slowDown(until: date) }
    if case .failure(let error) = result, let date = (error as? HostedFileFailure)?.retryDate { Self.slowDown(until: date) }
    preparing?.cancel(); preparing = nil
    if case .failure = result, !cancelling { task?.cancel() }
    session?.finishTasksAndInvalidate(); session = nil; task = nil
    if checkpointID != nil, hosted == nil {
      for cookie in cookies {
        for stored in HTTPCookieStorage.shared.cookies ?? [] where stored.name == cookie.name && stored.domain == cookie.domain && stored.path == cookie.path && stored.value == cookie.value {
          HTTPCookieStorage.shared.deleteCookie(stored)
        }
      }
    }
    Self.waiting.removeAll { $0.0 === self }
    if Self.active === self { Self.active = nil }
    if let checkpointID { Self.recovery.remove(checkpointID) }
    completion(result)
    Self.startNext()
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    redirects += 1
    guard redirects <= 5, let url = newRequest.url,
          hosted?.accepts(url) ?? (GofilePolicy.fileURL(url) &&
          url.path.split(separator: "/").dropFirst(2).first == task.originalRequest?.url?.path.split(separator: "/").dropFirst(2).first) else {
      completionHandler(nil)
      fail(AppText.text("The server redirected outside the file endpoint. Refresh the folder or open the website to check access."))
      return
    }
    completionHandler(request(url))
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard completion != nil else { return }
    guard totalBytesWritten <= limit, totalBytesExpectedToWrite <= limit else { fail(AppText.text("This file exceeds the download size limit.")); return }
    let expected = fileSize ?? totalBytesExpectedToWrite
    progress(expected > 0 ? min(1, Double(totalBytesWritten) / Double(expected)) : nil)
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard completion != nil else { return }
    activity(.saving)
    var directory: URL?
    do {
      guard let response = downloadTask.response as? HTTPURLResponse, let url = response.url else { throw MediaFileError(message: AppText.text("Invalid download response.")) }
      if response.statusCode == 429 || response.statusCode == 503 {
        let retry = response.value(forHTTPHeaderField: "Retry-After")
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let date = retry.flatMap { format.date(from: $0) }
          ?? Date().addingTimeInterval(max(60, retry.flatMap(Double.init) ?? 60))
        if hosted != nil { throw HostedFileFailure.rateLimited(date) }
        throw GofileFailure.rateLimited(date)
      }
      if hosted != nil {
        if [404, 410].contains(response.statusCode) { throw HostedFileFailure.missing }
        if [401, 403, 424, 451].contains(response.statusCode) { throw HostedFileFailure.access }
      }
      if response.statusCode == 404 || response.statusCode == 410 { throw GofileFailure.notFound }
      if response.statusCode == 401 || response.statusCode == 403 { throw GofileFailure.access }
      let bytes = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
      guard bytes <= limit else { throw MediaFileError(message: AppText.text("This file exceeds the download size limit.")) }
      let handle = try FileHandle(forReadingFrom: location)
      let prefix = try handle.read(upToCount: 512) ?? Data()
      try handle.close()
      let error: String?
      if let hosted {
        guard hosted.accepts(url) else { throw HostedFileFailure.access }
        error = HostedFilePolicy.responseError(status: DownloadQueuePolicy.completedResponse(status: response.statusCode,
          contentRange: response.value(forHTTPHeaderField: "Content-Range"), bytes: bytes, resumed: resumed), mime: response.mimeType,
                                              bytes: bytes, expected: fileSize, prefix: prefix)
      } else {
        error = GofilePolicy.responseError(status: DownloadQueuePolicy.completedResponse(status: response.statusCode,
          contentRange: response.value(forHTTPHeaderField: "Content-Range"), bytes: bytes, resumed: resumed), url: url, mime: response.mimeType, expectedMIME: mime,
                                           bytes: bytes, expectedBytes: expectedBytes, prefix: prefix, limit: limit)
      }
      if let error {
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
      if let checkpointID { FileDownloadStore.remove(checkpointID.uuidString) }
      finish(.failure(error))
    }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, completion != nil, !cancelling else { return }
    let failure = error as NSError
    if resumed, failure.userInfo[NSURLSessionDownloadTaskResumeData] == nil, failure.code != NSURLErrorCancelled {
      if let checkpointID { FileDownloadStore.remove(checkpointID.uuidString) }
      fail(AppText.text("The saved connection expired. Continue to restart this file.")); return
    }
    keepResumeData(failure.userInfo[NSURLSessionDownloadTaskResumeData] as? Data)
    if (error as NSError).code == NSURLErrorCancelled { finish(.failure(CancellationError())) }
    else { fail(AppText.text("The file could not finish downloading. Check the connection and try again.")) }
  }
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    if let checkpointID { DispatchQueue.main.async { FileBackgroundEvents.eventsReady(checkpointID) } }
  }
  static func remove(_ file: URL) {
    let parent = file.deletingLastPathComponent()
    guard parent.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL,
          parent.lastPathComponent.hasPrefix("gofile-") else { return }
    try? FileManager.default.removeItem(at: parent)
  }
}
