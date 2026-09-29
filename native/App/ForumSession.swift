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
  private let purchases = SouthPurchaseService()
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
    var current = url
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
        guard let next = ForumRequest.redirect(response.value(forHTTPHeaderField: "Location"), from: current) else { throw ReaderFailure.unsupported }
        if site.isLogin(next) { throw ReaderFailure.login }
        guard site.accepts(next) else { throw ReaderFailure.unsupported }
        current = next
        continue
      }
      let source = try HTMLDecoder.decode(data, encodingName: response.textEncodingName)
      let finalURL = current
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
  func search(_ query: SimpSearchQuery) async throws -> ForumPage {
    guard site == .simp, !browserActive else { throw ReaderFailure.unsupported }
    let epoch = generation
    let form = try await searchHTML(SimpSearch.formURL)
    let body = try SimpSearch.formBody(form.source, url: form.url, status: form.status, query: query)
    try Task.checkCancellation()
    guard generation == epoch, !browserActive else { throw CancellationError() }
    let result = try await searchHTML(SimpSearch.formURL, body: body)
    guard SimpSitePolicy.searchResults(result.url) else {
      // Submission errors are returned at the form URL, without a result ID.
      _ = try SimpSearch.formBody(result.source, url: result.url, status: result.status, query: query)
      throw ReaderFailure.unsupported
    }
    let page = try await Task.detached(priority: .userInitiated) {
      try ForumParser().parse(result.source, url: result.url, status: result.status)
    }.value
    try Task.checkCancellation()
    guard generation == epoch, !browserActive else { throw CancellationError() }
    return page
  }
  private func searchHTML(_ url: URL, body: Data? = nil) async throws -> (source: String, url: URL, status: Int) {
    let epoch = generation
    var current = url
    var pendingBody = body
    for _ in 0..<6 {
      try Task.checkCancellation()
      guard generation == epoch, !browserActive else { throw CancellationError() }
      let cookies = await store.httpCookieStore.allCookies()
      try Task.checkCancellation()
      guard generation == epoch, !browserActive else { throw CancellationError() }
      let query = try site == .simp
        ? SimpSearch.request(url: current, body: pendingBody, userAgent: browserUserAgent, cookies: cookies)
        : SouthSearch.request(url: current, body: pendingBody, userAgent: browserUserAgent, cookies: cookies)
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
      guard generation == epoch, !browserActive else { throw CancellationError() }
      if (300..<400).contains(response.statusCode) {
        guard let next = SitePolicy.resolve(response.value(forHTTPHeaderField: "Location"), from: current) else { throw ReaderFailure.unsupported }
        if site.isLogin(next) { throw ReaderFailure.login }
        guard pendingBody == nil || [301, 302, 303].contains(response.statusCode) else { throw ReaderFailure.unsupported }
        // A POST is never replayed. Redirects rebuild cookies for the validated destination.
        pendingBody = nil
        current = SitePolicy.withoutFragment(next)
        continue
      }
      return (try HTMLDecoder.decode(data, encodingName: response.textEncodingName), current, response.statusCode)
    }
    throw ReaderFailure.network
  }
  func search(_ query: SouthSearchQuery) async throws -> ForumPage {
    guard site == .south, !browserActive else { throw ReaderFailure.unsupported }
    let epoch = generation
    let form = try await searchHTML(SouthSearch.formURL)
    let body = try SouthSearch.formBody(form.source, url: form.url, status: form.status, query: query)
    try Task.checkCancellation()
    guard generation == epoch, !browserActive else { throw CancellationError() }
    let result = try await searchHTML(SouthSearch.formURL, body: body)
    let page = try await Task.detached(priority: .userInitiated) {
      try SouthSearch.parse(result.source, url: result.url, status: result.status)
    }.value
    try Task.checkCancellation()
    guard generation == epoch, !browserActive else { throw CancellationError() }
    return page
  }
  func purchaseContent(in page: ForumPage, selected: SouthPurchaseOffer? = nil, excludingAuthors blocked: Set<String> = [], onUpdate: SouthPurchaseService.Update = { _ in }) async throws -> SouthPurchaseResult {
    guard site == .south, site.accepts(page.url), !browserActive else { throw ReaderFailure.unsupported }
    let epoch = generation
    let read: SouthPurchaseService.Load = { [self] url in
      try Task.checkCancellation()
      guard generation == epoch, !browserActive else { throw CancellationError() }
      return try await load(url)
    }
    let submit: SouthPurchaseService.Submit = { [self] offer, url in
      let cookies = await store.httpCookieStore.allCookies()
      try Task.checkCancellation()
      guard generation == epoch, !browserActive else { throw CancellationError() }
      let query = try SouthPurchase.request(offer, page: url, userAgent: browserUserAgent, cookies: cookies)
      pages.removeThread(url)
      // PageRequest never follows redirects or replays the mutation automatically.
      let (response, _) = try await request(query, maxBytes: 2 * 1024 * 1024)
      try Task.checkCancellation()
      guard generation == epoch, !browserActive else { throw CancellationError() }
      var headers: [String: String] = [:]
      for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
      for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: offer.action).filter({ site.domainMatches($0) }) {
        guard generation == epoch, !browserActive else { throw CancellationError() }
        if cookie.expiresDate.map({ $0 <= Date() }) ?? false { await store.httpCookieStore.deleteCookie(cookie) }
        else { await store.httpCookieStore.saveCookie(cookie) }
      }
      if response.statusCode == 429 { throw ReaderFailure.rateLimit }
      if response.statusCode == 401 { throw ReaderFailure.login }
      if response.statusCode == 403 { throw ReaderFailure.forbidden }
      guard (200..<400).contains(response.statusCode) else { throw ReaderFailure.network }
      if let location = response.value(forHTTPHeaderField: "Location") {
        guard let target = SouthSitePolicy.resolve(location, from: offer.action), site.sameOrigin(target) else { throw ReaderFailure.unsupported }
        if site.isLogin(target) { throw ReaderFailure.login }
      }
    }
    if let selected { return try await purchases.buy(selected, page: page, excludingAuthors: blocked, load: read, submit: submit, onUpdate: onUpdate) }
    return try await purchases.unlockFree(in: page, excludingAuthors: blocked, load: read, submit: submit, onUpdate: onUpdate)
  }
  func maximumPostNumber(from initial: ForumPage) async throws -> Int {
    guard site.accepts(initial.url), let key = SitePolicy.threadKey(initial.url), initial.kind == .posts else { throw ReaderFailure.unsupported }
    var page = initial
    let filteredAuthor = SouthSitePolicy.authorID(page.url) != nil
    if filteredAuthor || URLComponents(url: page.url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "order" }) == true,
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
