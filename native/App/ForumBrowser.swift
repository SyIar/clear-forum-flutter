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
  private var rewrittenThread: URL?
  private var rewriteAttempts = 0
  init(url: URL, session: ForumSession, completion: @escaping ([String: Any]?) -> Void) { site = session.site; initialURL = SouthSitePolicy.canonicalThreadURL(url); self.session = session; self.completion = completion; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = site.host
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: AppText.text("Done"), style: .plain, target: self, action: #selector(close))
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: AppText.text("Read page"), style: .done, target: self, action: #selector(readPage))
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    if site == .south { configuration.defaultWebpagePreferences.preferredContentMode = .desktop }
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
  private func finish(_ page: [String: Any]?) {
    guard !finished else { return }
    finished = true
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
    // Keep login/logout structure for the parser, but never copy entered form values.
    let script = #"(()=>{const root=document.documentElement.cloneNode(true);root.querySelectorAll('script,style,object,embed,textarea,select,svg,noscript').forEach(e=>e.remove());root.querySelectorAll('input').forEach(e=>{const marker=document.createElement('input');for(const name of ['name','type']){if(e.hasAttribute(name))marker.setAttribute(name,e.getAttribute(name));}e.replaceWith(marker);});return {url:location.href,html:root.outerHTML,hasPurchases:!!root.querySelector('h6.quote.jumbotron input[type=button]'),hasPoll:!!root.querySelector('form[name=vote]')};})()"#
    webView.evaluateJavaScript(script) { [weak self] value, error in
      guard let self = self else { return }
      self.capturing = false
      guard !self.finished, error == nil, let page = value as? [String: Any], let html = page["html"] as? String, html.utf8.count <= 8 * 1024 * 1024, let address = page["url"] as? String, let finalURL = URL(string: address), self.site.accepts(finalURL) else { self.notice(AppText.text("This page is not ready for clean view. Finish loading or sign in and try again.")); return }
      self.finish(page)
    }
  }
  private func notice(_ text: String) {
    guard presentedViewController == nil, !finished else { return }
    let alert = UIAlertController(title: AppText.text("Site browser"), message: text, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: AppText.text("OK"), style: .default))
    present(alert, animated: true)
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
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { notice(AppText.text("Could not load this page. Check the connection and try again.")) } }
}
