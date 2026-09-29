import Foundation
import WebKit
import UIKit

@MainActor
final class ForumSession: ObservableObject {
  let site: ForumSite
  let store: WKWebsiteDataStore
  let browserUserAgent: String
  let images = ImageStore()
  let pages = PageCache()
  private var operations: [UUID: PageRequest] = [:]
  @Published private(set) var generation = 0
  private var memoryObserver: NSObjectProtocol?
  private var browserActive = false
  init(site: ForumSite) {
    self.site = site
    browserUserAgent = BrowserIdentity.userAgent(for: site, systemVersion: UIDevice.current.systemVersion, isPad: UIDevice.current.userInterfaceIdiom == .pad)
    // Keep the existing Simp login; South gets an isolated persistent WebKit profile.
    store = site == .simp ? .default() : WKWebsiteDataStore(forIdentifier: UUID(uuidString: "1F621C45-387F-478D-A8E2-56DB533EA481")!)
    memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in
        self?.pages.removeAll()
        self?.images.releaseCachedImages()
      }
    }
  }
  deinit { if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) } }
  func beginBrowsing() {
    browserActive = true
    invalidatePages()
  }
  func endBrowsing() {
    browserActive = false
    invalidatePages()
  }
  private func request(_ request: URLRequest, maxBytes: Int = 8 * 1024 * 1024, htmlOnly: Bool = false) async throws -> (HTTPURLResponse, Data) {
    let id = UUID()
    let epoch = generation
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let operation = PageRequest(request: request, maxBytes: maxBytes, htmlOnly: htmlOnly) { [weak self] response, data, error in
          Task { @MainActor in
            guard let self else { continuation.resume(throwing: CancellationError()); return }
            self.operations.removeValue(forKey: id)
            guard epoch == self.generation else { continuation.resume(throwing: CancellationError()); return }
            guard error == nil, let response else { continuation.resume(throwing: ReaderFailure.network); return }
            continuation.resume(returning: (response, data))
          }
        }
        operations[id] = operation
        operation.start()
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.operations[id]?.cancel() }
    }
  }
  func load(_ url: URL, cacheResult: Bool = false) async throws -> ForumPage {
    guard site.accepts(url) else { throw ReaderFailure.unsupported }
    guard !browserActive else { throw CancellationError() }
    let epoch = generation
    let userAgent = browserUserAgent
    var current = SitePolicy.withoutFragment(url)
    for _ in 0..<6 {
      try Task.checkCancellation()
      guard generation == epoch else { throw CancellationError() }
      let cookies = await store.httpCookieStore.allCookies()
      try Task.checkCancellation()
      guard generation == epoch else { throw CancellationError() }
      let query = try ForumRequest.page(site: site, url: current, userAgent: userAgent, cookies: cookies)
      let (response, data) = try await request(query)
      try Task.checkCancellation()
      guard generation == epoch, !browserActive else { throw CancellationError() }
      var headers: [String: String] = [:]
      for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
      for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: current).filter({ site.domainMatches($0) }) {
        guard generation == epoch, !browserActive else { throw CancellationError() }
        if cookie.expiresDate.map({ $0 <= Date() }) ?? false { await store.httpCookieStore.deleteCookie(cookie) }
        else { await store.httpCookieStore.saveCookie(cookie) }
      }
      guard generation == epoch else { throw CancellationError() }
      if (300..<400).contains(response.statusCode) {
        guard let next = SitePolicy.resolve(response.value(forHTTPHeaderField: "Location"), from: current) else { throw ReaderFailure.unsupported }
        if site.isLogin(next) { throw ReaderFailure.login }
        guard site.accepts(next) else { throw ReaderFailure.unsupported }
        current = SitePolicy.withoutFragment(next)
        continue
      }
      var finalComponents = URLComponents(url: current, resolvingAgainstBaseURL: false)!
      finalComponents.fragment = url.fragment
      let source = try HTMLDecoder.decode(data, encodingName: response.textEncodingName)
      let finalURL = finalComponents.url ?? current
      let status = response.statusCode
      let page = try await Task.detached(priority: .userInitiated) { try ForumParser().parse(source, url: finalURL, status: status) }.value
      try Task.checkCancellation()
      guard generation == epoch else { throw CancellationError() }
      if cacheResult { pages.store(page) }
      return page
    }
    throw ReaderFailure.network
  }
  func posterHTML(_ url: URL) async -> String? {
    guard MediaPolicy.posterPage(url) else { return nil }
    var query = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
    query.httpShouldHandleCookies = false
    query.setValue("text/html", forHTTPHeaderField: "Accept")
    query.setValue(site.base.absoluteString, forHTTPHeaderField: "Referer")
    guard let (response, data) = try? await request(query, maxBytes: 2 * 1024 * 1024, htmlOnly: true), (200..<300).contains(response.statusCode) else { return nil }
    return String(data: data, encoding: .utf8)
  }
  func maximumPostNumber(from initial: ForumPage) async throws -> Int {
    guard site.accepts(initial.url), let key = SitePolicy.threadKey(initial.url), initial.kind == .posts else { throw ReaderFailure.unsupported }
    var page = initial
    if URLComponents(url: page.url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "order" }) == true,
       let root = SitePolicy.threadRoot(page.url) { page = try await load(root) }
    // Follow the last-page link, including a page added while this request is in flight.
    for attempt in 0..<3 {
      try Task.checkCancellation()
      guard site.accepts(page.url), SitePolicy.threadKey(page.url) == key, page.kind == .posts else { throw ReaderFailure.unsupported }
      if let maximum = page.maximumPostNumber, maximum >= 0 { return maximum }
      guard attempt < 2, let last = page.url(forPage: page.pageCount) ?? page.lastPage ?? page.next,
            SitePolicy.threadKey(last) == key, SitePolicy.pageNumber(last) > page.pageNumber else { throw ReaderFailure.unsupported }
      page = try await load(last)
    }
    throw ReaderFailure.unsupported
  }
  func invalidatePages() {
    generation += 1
    pages.removeAll()
    let active = Array(operations.values)
    operations.removeAll()
    active.forEach { $0.cancel() }
  }
  func clear() async {
    invalidatePages()
    images.releaseCachedImages()
    await withCheckedContinuation { continuation in
      store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { continuation.resume() }
    }
  }
}
extension WKHTTPCookieStore {
  func allCookies() async -> [HTTPCookie] { await withCheckedContinuation { continuation in getAllCookies { continuation.resume(returning: $0) } } }
  func saveCookie(_ cookie: HTTPCookie) async { await withCheckedContinuation { continuation in setCookie(cookie) { continuation.resume() } } }
  func deleteCookie(_ cookie: HTTPCookie) async { await withCheckedContinuation { continuation in delete(cookie) { continuation.resume() } } }
}

@MainActor
final class PosterStore: ObservableObject {
  private var tasks: [URL: Task<URL?, Never>] = [:]
  private var active = 0
  func resolve(_ block: BodyBlock, session: ForumSession) async -> URL? {
    if let poster = block.poster { return poster }
    guard !block.direct, let url = block.url, MediaPolicy.posterPage(url) else { return nil }
    if let task = tasks[url] { return await task.value }
    guard tasks.count < 128 else { return nil }
    let task = Task { [weak self] () -> URL? in
      guard let self else { return nil }
      while self.active >= 2 {
        do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return nil }
      }
      guard !Task.isCancelled else { return nil }
      self.active += 1
      defer { self.active -= 1 }
      guard let source = await session.posterHTML(url) else { return nil }
      return ForumParser.poster(source, page: url)
    }
    tasks[url] = task
    return await task.value
  }
  func cancel() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
}
