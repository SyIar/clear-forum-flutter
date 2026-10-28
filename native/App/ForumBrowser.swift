import ForumUI
import UIKit
import WebKit
final class PageRequest: NSObject, URLSessionDataDelegate {
  private let request: URLRequest
  private let maxBytes: Int
  private let htmlOnly: Bool
  private let completion: (HTTPURLResponse?, Data, Error?) -> Void
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var response: HTTPURLResponse?
  private var data = Data()
  init(request: URLRequest, maxBytes: Int = 8 * 1024 * 1024, htmlOnly: Bool = false, completion: @escaping (HTTPURLResponse?, Data, Error?) -> Void) {
    self.request = request; self.maxBytes = maxBytes; self.htmlOnly = htmlOnly; self.completion = completion
  }
  func start() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = htmlOnly ? 20 : 35
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    task = session.dataTask(with: request)
    task?.resume()
  }
  func cancel() { task?.cancel() }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    self.response = response as? HTTPURLResponse
    let validHTML = !htmlOnly || ["text/html", "application/xhtml+xml"].contains(response.mimeType?.lowercased() ?? "")
    completionHandler(response.expectedContentLength > maxBytes || !validHTML ? .cancel : .allow)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard self.data.count + data.count <= maxBytes else { dataTask.cancel(); return }
    self.data.append(data)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    completion(response, data, error)
    session.finishTasksAndInvalidate()
    self.session = nil
  }
}

final class ForumBrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate {
  private let site: ForumSite
  private let initialURL: URL
  private let session: ForumSession
  private var dataStore: WKWebsiteDataStore { session.store }
  private let completion: ([String: Any]?) -> Void
  private var webView: WKWebView!
  private let progress = UIProgressView(progressViewStyle: .default)
  private var observation: NSKeyValueObservation?
  private var finished = false
  private var capturing = false
  private let automaticallyReads: Bool
  private var verificationEncountered = false
  private var verificationTask: Task<Void, Never>?
  private var verificationDeadline: Date?
  private var navigationID = UUID()
  private var rewrittenThread: URL?
  private var rewriteAttempts = 0
  init(url: URL, session: ForumSession, automaticallyReads: Bool = false, completion: @escaping ([String: Any]?) -> Void) { site = session.site; initialURL = SouthSitePolicy.canonicalThreadURL(url); self.session = session; self.automaticallyReads = automaticallyReads; self.completion = completion; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = site.host
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: AppText.text("Done"), style: .plain, target: self, action: #selector(close))
    let copy = UIBarButtonItem(image: UIImage(systemName: "ladybug"), style: .plain, target: self, action: #selector(copyPageHTML))
    copy.accessibilityLabel = AppText.text("Copy page HTML")
    navigationItem.rightBarButtonItems = [UIBarButtonItem(title: AppText.text("Read page"), style: .done, target: self, action: #selector(readPage)), copy]
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    if site != .simp { configuration.defaultWebpagePreferences.preferredContentMode = .desktop }
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.customUserAgent = session.browserUserAgent
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
      Task { @MainActor in
        guard let self, !self.finished else { return }
        if let list { self.webView.configuration.userContentController.add(list) }
        self.webView.load(URLRequest(url: self.initialURL))
      }
    }
  }
  @objc private func close() { finish(nil) }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if automaticallyReads || verificationEncountered { monitorVerification() }
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    verificationTask?.cancel(); verificationTask = nil
  }
  private func finish(_ page: [String: Any]?) {
    guard !finished else { return }
    finished = true
    verificationTask?.cancel(); verificationTask = nil
    webView.stopLoading()
    Task { @MainActor in
      // Finish a cookie-store round trip before handing control back to the reader.
      _ = await dataStore.httpCookieStore.allCookies()
      dismiss(animated: true) { self.completion(page) }
    }
  }
  @objc private func readPage() {
    guard !capturing, let url = webView.url, site.accepts(url) else { notice(AppText.text("Open a forum or thread before choosing Read page.")); return }
    capturing = true
    let expectedNavigation = navigationID
    // Keep login/logout structure for the parser, but never copy entered form values.
    webView.evaluateJavaScript(Self.captureScript) { [weak self] value, error in
      guard let self = self else { return }
      guard !self.finished, error == nil, let page = value as? [String: Any], let html = page["html"] as? String, html.utf8.count <= 8 * 1024 * 1024, let address = page["url"] as? String, let finalURL = URL(string: address), self.site.accepts(finalURL) else { self.capturing = false; self.notice(AppText.text("This page is not ready for clean view. Finish loading or sign in and try again.")); return }
      Task { @MainActor in
        var challenge = false
        if self.site == .simp {
          challenge = (try? await Task.detached(priority: .utility) { try SimpBrowserVerification.required(html) }.value) == true
        }
        self.capturing = false
        guard !self.finished, expectedNavigation == self.navigationID else { return }
        if challenge {
          self.verificationEncountered = true
          self.monitorVerification()
          self.notice(AppText.text("Complete the site's verification in Site browser, then choose Read page."))
        } else { self.finish(page) }
      }
    }
  }
  // Observe a normal WebKit navigation. Never solve a CAPTCHA or replay a POST.
  // The browser itself executes the site's scripts using the existing data store.
  private func monitorVerification() {
    guard site == .simp, verificationTask == nil, !finished else { return }
    let deadline = verificationDeadline ?? Date().addingTimeInterval(90)
    verificationDeadline = deadline
    guard Date() < deadline else { return }
    verificationTask = Task { [weak self] in
      for _ in 0..<90 {
        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        guard let self, !self.finished else { return }
        guard Date() < deadline else { self.verificationTask = nil; return }
        self.inspectVerificationPage()
      }
      self?.verificationTask = nil
    }
  }
  private func inspectVerificationPage() {
    guard site == .simp, !finished, !capturing, !webView.isLoading,
          UIApplication.shared.applicationState == .active, viewIfLoaded?.window != nil,
          presentedViewController == nil, let address = webView.url, site.sameOrigin(address) else { return }
    let expectedNavigation = navigationID
    capturing = true
    webView.evaluateJavaScript(Self.captureScript) { [weak self] value, error in
      guard let self else { return }
      guard !self.finished, error == nil, let page = value as? [String: Any],
            let html = page["html"] as? String, html.utf8.count <= 8 * 1024 * 1024,
            let address = page["url"] as? String, let url = URL(string: address), self.site.sameOrigin(url) else {
        self.capturing = false; return
      }
      let expectedURL = self.initialURL
      Task { @MainActor in
        let result = await Task.detached(priority: .utility) { () -> (challenge: Bool, readable: Bool) in
          let challenge = (try? SimpBrowserVerification.required(html)) == true
          let readable = !challenge && SimpBrowserVerification.canResume(expected: expectedURL, actual: url) &&
            (try? ForumParser().parse(html, url: url)) != nil
          return (challenge, readable)
        }.value
        self.capturing = false
        guard !self.finished, expectedNavigation == self.navigationID, !self.webView.isLoading,
              UIApplication.shared.applicationState == .active, self.viewIfLoaded?.window != nil,
              self.presentedViewController == nil else { return }
        if result.challenge {
          self.verificationEncountered = true
          self.monitorVerification()
        } else if result.readable, self.automaticallyReads || self.verificationEncountered {
          self.finish(page)
        }
      }
    }
  }
  private static let captureScript = #"(()=>{const root=document.documentElement.cloneNode(true);root.querySelectorAll('script,style,object,embed,textarea,select,svg,noscript').forEach(e=>e.remove());root.querySelectorAll('input').forEach(e=>{const marker=document.createElement('input');for(const name of ['name','type']){if(e.hasAttribute(name))marker.setAttribute(name,e.getAttribute(name));}e.replaceWith(marker);});return {url:location.href,html:root.outerHTML,hasPurchases:!!root.querySelector('h6.quote.jumbotron input[type=button]'),hasPoll:!!root.querySelector('form[name=vote]')};})()"#
  @objc private func copyPageHTML() {
    guard !capturing, !finished, let url = webView.url, site.sameOrigin(url) else { return }
    capturing = true
    webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
      guard let self else { return }
      self.capturing = false
      guard !self.finished, error == nil, let html = value as? String else { self.notice(AppText.text("Could not load page")); return }
      Task { @MainActor in
        let sanitized = await Task.detached(priority: .utility) { ReaderDiagnostics.html(html) }.value
        guard !self.finished else { return }
        let report = "Browser DOM\n" + ReaderDiagnostics.address(url.absoluteString) + "\n\n" + ReaderDiagnostics.htmlExport(sanitized)
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: report]], options: [.localOnly: true])
        self.notice(AppText.text("Copied"))
      }
    }
  }
  private func notice(_ text: String) {
    guard presentedViewController == nil, !finished else { return }
    ForumDialogs.notice(from: self, title: AppText.text("Site browser"), message: text, close: AppText.text("OK"))
  }
  private func openExternal(_ url: URL) {
    guard !finished, presentedViewController == nil, let browser = ExternalBrowser.make(url) else { return }
    present(browser, animated: true)
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
    if site == .south, navigationAction.targetFrame?.isMainFrame == true,
       (navigationAction.request.httpMethod ?? "GET").uppercased() == "GET" {
      if [.linkActivated, .backForward, .reload].contains(navigationAction.navigationType) {
        rewrittenThread = nil; rewriteAttempts = 0
      }
      let target = SouthSitePolicy.canonicalThreadURL(url)
      if target != url {
        rewriteAttempts = rewrittenThread == target ? rewriteAttempts + 1 : 1
        rewrittenThread = target
        decisionHandler(.cancel)
        guard rewriteAttempts <= 3 else {
          notice(AppText.text("The website repeatedly redirected this thread. Reload or try another page."))
          return
        }
        var request = navigationAction.request
        request.url = target
        webView.load(request)
        return
      }
    }
    if site == .simp, navigationAction.navigationType == .linkActivated,
       let direct = SimpSitePolicy.browserRedirectDestination(url), direct != url {
      decisionHandler(.cancel)
      if !site.sameOrigin(direct) { openExternal(direct) }
      else if site.accepts(direct) { webView.load(URLRequest(url: direct)) }
      return
    }
    if navigationAction.targetFrame?.isMainFrame == true && !site.sameOrigin(url) {
      decisionHandler(.cancel)
      if navigationAction.navigationType == .linkActivated { openExternal(url) }
      return
    }
    decisionHandler(url.scheme == "https" || url.scheme == "about" ? .allow : .cancel)
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if navigationAction.navigationType == .linkActivated, let requested = navigationAction.request.url {
      let url = site == .simp ? SimpSitePolicy.browserRedirectDestination(requested) ?? requested : SouthSitePolicy.canonicalThreadURL(requested)
      if site.sameOrigin(url) { webView.load(url == requested ? navigationAction.request : URLRequest(url: url)) }
      else { openExternal(url) }
    }
    return nil
  }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { navigationID = UUID() }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { inspectVerificationPage() }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { notice(AppText.text("Could not load this page. Check the connection and try again.")) } }
}
