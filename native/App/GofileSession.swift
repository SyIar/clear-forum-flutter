import SwiftUI
import WebKit
import ImageIO

@MainActor
final class GofileSession: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
  // Gofile never shares its cookie store with either forum or Safari.
  static let store = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "D547C825-60B1-4AD0-B49B-DA80AC745E24")!)
  let url: URL
  @Published private(set) var listing: GofileListing?
  @Published private(set) var loading = false
  @Published private(set) var revision = 0
  @Published private(set) var error: String?
  @Published var showingWebsite = false
  @Published private(set) var downloads: [String: GofileDownloadState] = [:]
  @Published var export: GofileLocalFile?
  @Published var preview: GofileLocalFile?
  @Published var video: GofileVideoSource?
  private(set) var webView: WKWebView!
  private var pageNumber = 1
  private var generation = 0
  private var timer: Task<Void, Never>?
  private var transfers: [String: GofileFileTransfer] = [:]
  private var thumbnailTransfers: [UUID: GofileFileTransfer] = [:]
  private let thumbnails = NSCache<NSString, UIImage>()
  private var cookies: [HTTPCookie] = []
  private var userAgent = ""
  private var ready = false
  private var bridgeSource = ""
  init(url: URL) {
    self.url = GofilePolicy.pageURL(url) ?? url
    super.init()
    thumbnails.countLimit = 100; thumbnails.totalCostLimit = 24 * 1024 * 1024
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = Self.store
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    let source = Bundle.main.url(forResource: "GofileBridge", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    bridgeSource = source ?? ""
    configuration.userContentController.add(GofileWeakHandler(self), name: "gofile")
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.allowsBackForwardNavigationGestures = true
  }
  func load(page: Int? = nil) {
    if let page { pageNumber = max(1, page) }
    generation += 1; let epoch = generation
    loading = true; ready = false; error = nil
    timer?.cancel()
    webView.stopLoading()
    webView.configuration.userContentController.removeAllUserScripts()
    webView.configuration.userContentController.addUserScript(WKUserScript(source: bridgeSource.replacingOccurrences(of: "__FORUM_GENERATION__", with: String(generation)), injectionTime: .atDocumentStart, forMainFrameOnly: true))
    webView.load(URLRequest(url: GofilePolicy.page(url, number: pageNumber), cachePolicy: .reloadIgnoringLocalCacheData))
    timer = Task { [weak self] in
      try? await Task.sleep(for: .seconds(30))
      guard let self, !Task.isCancelled, self.generation == epoch, self.loading else { return }
      self.loading = false; self.error = GofileFailure.website.localizedDescription
    }
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https",
          message.frameInfo.securityOrigin.host == "gofile.io", let payload = message.body as? [String: Any],
          payload["generation"] as? String == String(generation) else { return }
    do {
      let value = try GofileListing.parse(payload, requested: url, page: pageNumber)
      timer?.cancel()
      let epoch = generation
      Task { [weak self] in
        guard let self else { return }
        let cookies = await Self.store.httpCookieStore.allCookies()
        let agent = try? await self.webView.evaluateJavaScript("navigator.userAgent") as? String
        guard self.generation == epoch else { return }
        self.cookies = cookies.filter { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == "gofile.io" || $0.domain.lowercased().hasSuffix(".gofile.io") }
        self.userAgent = agent ?? ""
        self.listing = value; self.loading = false; self.error = nil; self.ready = true; self.revision += 1
        if !self.showingWebsite { self.webView.stopLoading() }
      }
    } catch GofileFailure.stale { return }
    catch { timer?.cancel(); loading = false; ready = false; self.error = error.localizedDescription }
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
    guard let target = navigationAction.request.url, GofilePolicy.website(target) else { decisionHandler(.cancel); return }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if (error as NSError).code != NSURLErrorCancelled { loading = false; self.error = "Could not connect to Gofile. Check the connection and refresh." }
  }
  func showWebsite() { showingWebsite = true; webView.load(URLRequest(url: GofilePolicy.page(url, number: pageNumber))) }
  func returnToFiles() { showingWebsite = false; load() }
  func open(_ entry: GofileEntry) {
    if let file = downloads[entry.id]?.file { preview = GofileLocalFile(url: file); return }
    if entry.isVideo, let link = entry.link, ready, !entry.unavailable {
      video = GofileVideoSource(entry: entry, url: link, cookies: cookies.filter { MediaPolicy.cookieMatches($0, link) })
    } else { download(entry, previewWhenReady: true) }
  }
  func download(_ entry: GofileEntry, previewWhenReady: Bool = false) {
    guard !entry.folder else { return }
    if let file = downloads[entry.id]?.file {
      if previewWhenReady { preview = GofileLocalFile(url: file) } else { export = GofileLocalFile(url: file) }
      return
    }
    guard transfers[entry.id] == nil else { return }
    guard transfers.count < 2 else { downloads[entry.id] = .init(error: "Two downloads are already running."); return }
    guard ready, !entry.unavailable, let link = entry.link else {
      downloads[entry.id] = .init(error: "Refresh the folder or open the website to check this file's availability."); return
    }
    downloads[entry.id] = .init(busy: true)
    let transfer = GofileFileTransfer(name: entry.name, expectedBytes: entry.size, mime: entry.mime, cookies: cookies, userAgent: userAgent,
      progress: { [weak self] value in self?.downloads[entry.id]?.progress = value }, completion: { [weak self] result in
        guard let self else { if case .success(let file) = result { GofileFileTransfer.remove(file) }; return }
        self.transfers[entry.id] = nil
        switch result {
        case .success(let file):
          self.downloads[entry.id] = .init(file: file)
          if self.preview == nil && self.export == nil && self.video == nil && !self.showingWebsite {
            if previewWhenReady { self.preview = GofileLocalFile(url: file) }
            else { self.export = GofileLocalFile(url: file) }
          }
        case .failure(let error):
          self.downloads[entry.id] = .init(error: error is CancellationError ? nil : error.localizedDescription)
        }
      })
    transfers[entry.id] = transfer; transfer.start(link)
  }
  func cancel(_ id: String) { transfers[id]?.cancel() }
  func thumbnail(_ entry: GofileEntry) async -> UIImage? {
    guard let url = entry.thumbnail, ready else { return nil }
    if let cached = thumbnails.object(forKey: url.absoluteString as NSString) { return cached }
    let epoch = generation
    while thumbnailTransfers.count >= 4 {
      do { try await Task.sleep(for: .milliseconds(80)) } catch { return nil }
      guard generation == epoch, ready else { return nil }
    }
    guard !Task.isCancelled else { return nil }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let transfer = GofileFileTransfer(name: "thumbnail", expectedBytes: nil, mime: "image/jpeg", cookies: cookies, userAgent: userAgent,
          limit: 4 * 1024 * 1024, progress: { _ in }, completion: { [weak self] result in
            self?.thumbnailTransfers[id] = nil
            var image: UIImage?
            if case .success(let file) = result {
              defer { GofileFileTransfer.remove(file) }
              if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                 let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceThumbnailMaxPixelSize: 160, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                image = UIImage(cgImage: thumb)
                if let image { self?.thumbnails.setObject(image, forKey: url.absoluteString as NSString, cost: thumb.width * thumb.height * 4) }
              }
            }
            continuation.resume(returning: image)
          })
        thumbnailTransfers[id] = transfer; transfer.start(url)
      }
    } onCancel: { Task { @MainActor [weak self] in self?.thumbnailTransfers[id]?.cancel() } }
  }
  deinit {
    timer?.cancel()
    transfers.values.forEach { $0.cancel() }; thumbnailTransfers.values.forEach { $0.cancel() }
    downloads.values.compactMap(\.file).forEach(GofileFileTransfer.remove)
  }
}

@MainActor
private final class GofileWeakHandler: NSObject, WKScriptMessageHandler {
  weak var owner: GofileSession?
  init(_ owner: GofileSession) { self.owner = owner }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    owner?.userContentController(userContentController, didReceive: message)
  }
}

struct GofileDownloadState {
  var busy = false
  var progress: Double?
  var file: URL?
  var error: String?
}
struct GofileLocalFile: Identifiable, Hashable { let url: URL; var id: String { url.path } }
struct GofileVideoSource: Identifiable, Hashable {
  let entry: GofileEntry
  let url: URL
  let cookies: [HTTPCookie]
  var id: String { entry.id }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
