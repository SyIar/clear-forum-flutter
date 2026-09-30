import SwiftUI
import WebKit

struct BaiduBrowser: UIViewControllerRepresentable {
  let session: Session?
  var url: URL? = nil
  let completion: (Result<JSON?, Error>) -> Void
  func makeUIViewController(context: Context) -> UINavigationController {
    UINavigationController(rootViewController: BaiduBrowserController(session: session, url: url, completion: completion))
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
final class BaiduBrowserController: UIViewController, WKNavigationDelegate {
  private var web: WKWebView!
  private let session: Session?
  private let initial: URL?
  private let completion: (Result<JSON?, Error>) -> Void
  private var finishing = false
  init(session: Session?, url: URL?, completion: @escaping (Result<JSON?, Error>) -> Void) { self.session = session; initial = url; self.completion = completion; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
  override func viewDidLoad() {
    super.viewDidLoad()
    let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
    web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self; web.allowsBackForwardNavigationGestures = true
    view = web; title = tr(initial == nil ? "loginTitle" : "openOriginal")
    navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(close))
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: tr("done"), style: .done, target: self, action: #selector(finish))
    let login = URL(string: "https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine")!
    let target = initial ?? login
    guard target.scheme == "https", allowed(target) else { completion(.failure(APIError(message: "This Baidu page is not allowed."))); return }
    Task { @MainActor in
      if initial != nil, let session, let host = target.host, ["tieba.baidu.com", "tiebac.baidu.com"].contains(host) {
        for (name, value) in ["BDUSS": session.bduss, "STOKEN": session.stoken] {
          if let cookie = HTTPCookie(properties: [.domain: host, .path: "/", .name: name, .value: value, .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"]) { await config.websiteDataStore.httpCookieStore.setCookie(cookie) }
        }
      }
      web.load(URLRequest(url: target))
    }
  }
  private func allowed(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
    return initial == nil ? (host == "baidu.com" || host.hasSuffix(".baidu.com")) : ["tieba.baidu.com", "tiebac.baidu.com", "wappass.baidu.com", "passport.baidu.com"].contains(host)
  }
  @objc private func close() { guard !finishing else { return }; finishing = true; completion(.success(nil)) }
  @objc private func finish() {
    if initial != nil { close(); return }
    Task { @MainActor in
      let cookies = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
      let valid = cookies.filter { ($0.domain == "baidu.com" || $0.domain.hasSuffix(".baidu.com")) && $0.name.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil && $0.value.rangeOfCharacter(from: CharacterSet(charactersIn: ";\r\n")) == nil }
      guard let bduss = valid.first(where: { $0.name == "BDUSS" })?.value, let stoken = valid.first(where: { $0.name == "STOKEN" })?.value, !bduss.isEmpty, !stoken.isEmpty else {
        let alert = UIAlertController(title: tr("loginNeeded"), message: tr("accountCookiesMissing"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("done"), style: .default)); present(alert, animated: true); return
      }
      guard !finishing else { return }; finishing = true
      completion(.success(["bduss": bduss, "stoken": stoken, "cookie": valid.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")]))
    }
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
    decisionHandler(navigationAction.request.url.map(allowed) == true ? .allow : .cancel)
  }
}
