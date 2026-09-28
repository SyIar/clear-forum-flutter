import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var sessionBridge: ForumSessionBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    sessionBridge = ForumSessionBridge(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

private enum SitePolicy {
  static let host = "simpcity.cr"
  static func sameOrigin(_ url: URL) -> Bool {
    url.scheme == "https" && url.host?.lowercased() == host && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
  }
  static func readable(_ url: URL) -> Bool {
    guard sameOrigin(url), !url.path.contains("%"), !url.path.contains("\\"), !url.path.components(separatedBy: "/").contains("..") else { return false }
    let pattern = #"^/(?:(?:forums|threads)/[^/]+\.\d+(?:/(?:page-\d+/?)?)?|posts/\d+/?|search-forums/[^/]+(?:/(?:page-\d+/?)?)?|whats-new/(?:posts/)?|watched/threads/?)$"#
    guard url.path == "/" || url.path.range(of: pattern, options: .regularExpression) != nil else { return false }
    var keys = Set<String>()
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
      guard keys.insert(item.name).inserted, let value = item.value else { return false }
      if item.name == "page" {
        guard value.range(of: #"^[1-9]\d{0,4}$"#, options: .regularExpression) != nil else { return false }
      } else if item.name == "order" {
        guard ["post_date", "last_post_date", "reaction_score"].contains(value) else { return false }
      } else { return false }
    }
    return true
  }
  static func domainMatches(_ cookie: HTTPCookie) -> Bool {
    cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host
  }
  static func matches(_ cookie: HTTPCookie, url: URL) -> Bool {
    guard sameOrigin(url), domainMatches(cookie), cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
    let path = url.path.isEmpty ? "/" : url.path
    return path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
  }
}

private final class ForumSessionBridge {
  private let channel: FlutterMethodChannel
  private let store = WKWebsiteDataStore.default()
  private var requests: [UUID: PageRequest] = [:]
  private var browser: ForumBrowserController?
  private var generation = 0
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "dev.sylar.clearforum/session", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "unavailable", message: "Session unavailable.", details: nil)); return }
      switch call.method {
      case "loadPage": self.load(call.arguments, result: result)
      case "openBrowser": self.openBrowser(call.arguments, result: result)
      case "clearSession": self.clear(result: result)
      case "openExternal":
        guard let value = call.arguments as? String, let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { self.fail(result); return }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened ? nil : FlutterError(code: "open_failed", message: "Could not open link.", details: nil)) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func fail(_ result: FlutterResult) { result(FlutterError(code: "invalid_request", message: "This request is not allowed.", details: nil)) }
  private func load(_ argument: Any?, result: @escaping FlutterResult) {
    guard let value = argument as? String, let url = URL(string: value), SitePolicy.readable(url), requests.count < 4 else { fail(result); return }
    let currentGeneration = generation
    store.httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self = self, currentGeneration == self.generation else { result(FlutterError(code: "cancelled", message: "Session changed.", details: nil)); return }
      let id = UUID()
      var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
      request.httpMethod = "GET"
      request.httpShouldHandleCookies = false
      request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
      request.setValue("ClearForum/0.1", forHTTPHeaderField: "User-Agent")
      let applicable = cookies.filter { SitePolicy.matches($0, url: url) }.sorted { $0.path.count > $1.path.count }
      for (key, value) in HTTPCookie.requestHeaderFields(with: applicable) { request.setValue(value, forHTTPHeaderField: key) }
      let operation = PageRequest(request: request) { [weak self] response, data, error in
        DispatchQueue.main.async {
          guard let self = self else { result(FlutterError(code: "unavailable", message: "Session unavailable.", details: nil)); return }
          self.requests.removeValue(forKey: id)
          guard currentGeneration == self.generation, error == nil, let response = response else { result(FlutterError(code: "network", message: "Could not load page.", details: nil)); return }
          var headers: [String: String] = [:]
          for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
          let updatedCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter { SitePolicy.domainMatches($0) }
          let group = DispatchGroup()
          for cookie in updatedCookies {
            group.enter()
            if cookie.expiresDate.map({ $0 <= Date() }) ?? false { self.store.httpCookieStore.delete(cookie) { group.leave() } }
            else { self.store.httpCookieStore.setCookie(cookie) { group.leave() } }
          }
          group.notify(queue: .main) {
            guard currentGeneration == self.generation else { result(FlutterError(code: "cancelled", message: "Session changed.", details: nil)); return }
            result(["status": response.statusCode, "html": String(data: data, encoding: .utf8) ?? "", "location": response.value(forHTTPHeaderField: "Location") ?? ""])
          }
        }
      }
      self.requests[id] = operation
      operation.start()
    }
  }
  private func openBrowser(_ argument: Any?, result: @escaping FlutterResult) {
    guard browser == nil, let value = argument as? String, let url = URL(string: value), SitePolicy.sameOrigin(url) else { fail(result); return }
    guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController, root.presentedViewController == nil else { fail(result); return }
    let browser = ForumBrowserController(url: url, store: store) { [weak self] page in
      self?.browser = nil
      result(page)
    }
    self.browser = browser
    let navigation = UINavigationController(rootViewController: browser)
    navigation.modalPresentationStyle = .fullScreen
    root.present(navigation, animated: true)
  }
  private func clear(result: @escaping FlutterResult) {
    guard browser == nil else { fail(result); return }
    generation += 1
    let active = Array(requests.values)
    requests.removeAll()
    active.forEach { $0.cancel() }
    store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { result(nil) }
  }
}

private final class PageRequest: NSObject, URLSessionDataDelegate {
  private let request: URLRequest
  private let completion: (HTTPURLResponse?, Data, Error?) -> Void
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var response: HTTPURLResponse?
  private var data = Data()
  init(request: URLRequest, completion: @escaping (HTTPURLResponse?, Data, Error?) -> Void) { self.request = request; self.completion = completion }
  func start() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = 35
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    task = session.dataTask(with: request)
    task?.resume()
  }
  func cancel() { task?.cancel() }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    self.response = response as? HTTPURLResponse
    completionHandler(response.expectedContentLength > 8 * 1024 * 1024 ? .cancel : .allow)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard self.data.count + data.count <= 8 * 1024 * 1024 else { dataTask.cancel(); return }
    self.data.append(data)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    completion(response, data, error)
    session.finishTasksAndInvalidate()
    self.session = nil
  }
}

private final class ForumBrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate {
  private let initialURL: URL
  private let dataStore: WKWebsiteDataStore
  private let completion: ([String: Any]?) -> Void
  private var webView: WKWebView!
  private let progress = UIProgressView(progressViewStyle: .default)
  private var observation: NSKeyValueObservation?
  private var finished = false
  private var capturing = false
  init(url: URL, store: WKWebsiteDataStore, completion: @escaping ([String: Any]?) -> Void) { initialURL = url; dataStore = store; self.completion = completion; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = SitePolicy.host
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(close))
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Read page", style: .done, target: self, action: #selector(readPage))
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)
    progress.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(progress)
    NSLayoutConstraint.activate([webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), webView.bottomAnchor.constraint(equalTo: view.bottomAnchor), webView.leadingAnchor.constraint(equalTo: view.leadingAnchor), webView.trailingAnchor.constraint(equalTo: view.trailingAnchor), progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), progress.leadingAnchor.constraint(equalTo: view.leadingAnchor), progress.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
    observation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in self?.progress.progress = Float(webView.estimatedProgress); self?.progress.isHidden = webView.estimatedProgress >= 1 }
    let rules = #"[{"trigger":{"url-filter":"^https?://([^/]+\\.)?clickadu\\.net/"},"action":{"type":"block"}},{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".adsbygoogle,.advertisement,.ad-container,.adContainer,[data-ad-slot]"}}]"#
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "clear-forum-basic-v1", encodedContentRuleList: rules) { [weak self] list, _ in
      DispatchQueue.main.async { guard let self = self, !self.finished else { return }; if let list = list { self.webView.configuration.userContentController.add(list) }; self.webView.load(URLRequest(url: self.initialURL)) }
    }
  }
  @objc private func close() { finish(nil) }
  private func finish(_ page: [String: Any]?) { guard !finished else { return }; finished = true; webView.stopLoading(); dismiss(animated: true) { self.completion(page) } }
  @objc private func readPage() {
    guard !capturing, let url = webView.url, SitePolicy.readable(url) else { notice("Open a forum or thread before choosing Read page."); return }
    capturing = true
    let script = #"(()=>{const root=document.documentElement.cloneNode(true);root.querySelectorAll('script,style,iframe,object,embed,input,textarea,select,svg,noscript,.p-nav,.p-header,.p-footer,.p-body-sidebar').forEach(e=>e.remove());root.querySelectorAll('form').forEach(e=>e.replaceWith(...e.childNodes));return {url:location.href,html:root.outerHTML};})()"#
    webView.evaluateJavaScript(script) { [weak self] value, error in
      guard let self = self else { return }
      self.capturing = false
      guard !self.finished, error == nil, let page = value as? [String: Any], let html = page["html"] as? String, html.utf8.count <= 8 * 1024 * 1024, let address = page["url"] as? String, let finalURL = URL(string: address), SitePolicy.readable(finalURL) else { self.notice("This page is not ready for clean view. Finish loading or sign in and try again."); return }
      self.finish(page)
    }
  }
  private func notice(_ text: String) {
    guard presentedViewController == nil, !finished else { return }
    let alert = UIAlertController(title: "Site browser", message: text, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
    if navigationAction.targetFrame?.isMainFrame == true && !SitePolicy.sameOrigin(url) {
      decisionHandler(.cancel)
      if navigationAction.navigationType == .linkActivated { notice("External links open from the clean reader. This browser keeps your forum session on the forum domain.") }
      return
    }
    decisionHandler(url.scheme == "https" || url.scheme == "about" ? .allow : .cancel)
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, SitePolicy.sameOrigin(url) { webView.load(navigationAction.request) }
    return nil
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { notice("Could not load this page. Check the connection and try again.") } }
}
