import AVKit
import AVFoundation
import UIKit
import WebKit

enum MediaPolicy {
  static func allowed(_ url: URL) -> Bool {
    url.scheme == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) && url.absoluteString.utf8.count <= 8192
  }
  static func sameOrigin(_ url: URL, _ other: URL) -> Bool {
    allowed(url) && allowed(other) && url.host?.lowercased() == other.host?.lowercased()
  }
  static func cookieMatches(_ cookie: HTTPCookie, _ url: URL) -> Bool {
    guard allowed(url), let host = url.host?.lowercased(), cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
    let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let matchesDomain = host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix("." + domain))
    let path = url.path.isEmpty ? "/" : url.path
    let matchesPath = path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
    return matchesDomain && matchesPath
  }
}

final class MediaPlayerController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  private let initialURL: URL
  private let direct: Bool
  private let completion: () -> Void
  // Media providers never receive the forum browser's cookie store.
  private let store = WKWebsiteDataStore.nonPersistent()
  private var webView: WKWebView!
  private let playerController = AVPlayerViewController()
  private let statusLabel = UILabel()
  private var statusObservation: NSKeyValueObservation?
  private var playbackObservation: NSKeyValueObservation?
  private var timeout: Timer?
  private var generation = 0
  private var closed = false
  private var attempted = false
  private var useWeb = false
  private var candidateFrame: WKFrameInfo?

  init(url: URL, direct: Bool, completion: @escaping () -> Void) {
    initialURL = url
    self.direct = direct
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = initialURL.host
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
    var actions = [UIBarButtonItem(title: "Reload", style: .plain, target: self, action: #selector(reload))]
    if !direct { actions.append(UIBarButtonItem(title: "Web player", style: .plain, target: self, action: #selector(showWeb))) }
    navigationItem.rightBarButtonItems = actions

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = store
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    if !direct {
      configuration.userContentController.add(self, contentWorld: .defaultClient, name: "mediaCandidate")
      if let file = Bundle.main.url(forResource: "MediaProbe", withExtension: "js"), let source = try? String(contentsOf: file, encoding: .utf8) {
        configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient))
      }
    }
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.numberOfLines = 0
    statusLabel.font = .preferredFont(forTextStyle: .footnote)
    statusLabel.textColor = .secondaryLabel
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(statusLabel)
    view.addSubview(webView)
    addChild(playerController)
    playerController.allowsPictureInPicturePlayback = false
    playerController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playerController.view)
    playerController.didMove(toParent: self)
    NSLayoutConstraint.activate([
      statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
      webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      playerController.view.topAnchor.constraint(equalTo: webView.topAnchor),
      playerController.view.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
      playerController.view.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
      playerController.view.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
    ])
    // Cosmetic filtering preserves scripts that a provider may need to initialize.
    // Popup and off-origin top-level navigation are handled by the delegates.
    let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".adsbygoogle,.advertisement,.ad-container,.adContainer,[data-ad-slot]"}}]"#
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "media-cosmetic-v1", encodedContentRuleList: rules) { [weak self] list, _ in
      DispatchQueue.main.async {
        guard let self = self, !self.closed else { return }
        if let list = list { configuration.userContentController.add(list) }
        self.reload()
      }
    }
  }

  private func resetPlayer() {
    timeout?.invalidate()
    timeout = nil
    statusObservation?.invalidate()
    statusObservation = nil
    playbackObservation?.invalidate()
    playbackObservation = nil
    playerController.player?.pause()
    playerController.player?.replaceCurrentItem(with: nil)
    playerController.player = nil
  }

  @objc private func reload() {
    guard !closed else { return }
    generation += 1
    resetPlayer()
    attempted = false
    candidateFrame = nil
    useWeb = false
    playerController.view.isHidden = !direct
    webView.isHidden = direct
    if direct {
      startPlayer(initialURL)
    } else {
      statusLabel.text = "Loading player. Browser verification may require your interaction."
      webView.stopLoading()
      var request = URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
      // Match a cross-origin embedded request without disclosing the thread path.
      request.setValue("https://simpcity.cr/", forHTTPHeaderField: "Referer")
      webView.load(request)
      scheduleTimeout("No direct stream was found. Try the web player's Play button or Reload.")
    }
  }

  private func scheduleTimeout(_ message: String) {
    timeout?.invalidate()
    timeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
      guard let self = self, !self.closed else { return }
      self.fallback(message)
    }
  }

  private func startPlayer(_ url: URL) {
    guard !closed, !attempted, !useWeb, MediaPolicy.allowed(url) else { return }
    attempted = true
    timeout?.invalidate()
    statusLabel.text = "Opening system player..."
    let epoch = generation
    store.httpCookieStore.getAllCookies { [weak self] cookies in
      DispatchQueue.main.async {
        guard let self = self, !self.closed, self.generation == epoch, !self.useWeb else { return }
        let applicable = cookies.filter { MediaPolicy.cookieMatches($0, url) }
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: applicable])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.playerController.player = player
        self.statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
          DispatchQueue.main.async {
            guard let self = self, !self.closed, self.generation == epoch, !self.useWeb else { return }
            if item.status == .failed {
              self.fallback("System playback failed. The stream may require its web player, may have expired, or may be unavailable.")
            } else if item.status == .readyToPlay {
              if !self.direct, let frame = self.candidateFrame {
                self.webView.callAsyncJavaScript("document.querySelectorAll('video,audio').forEach(element => element.pause());", arguments: [:], in: frame, in: .defaultClient, completionHandler: nil)
              }
              self.webView.isHidden = true
              self.playerController.view.isHidden = false
              self.statusLabel.text = "Buffering video..."
              try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
              try? AVAudioSession.sharedInstance().setActive(true)
              self.playerController.player?.play()
            }
          }
        }
        self.playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
          DispatchQueue.main.async {
            guard let self = self, !self.closed, self.generation == epoch, !self.useWeb else { return }
            if player.timeControlStatus == .playing {
              self.timeout?.invalidate()
              self.statusLabel.text = "System player"
            } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
              self.statusLabel.text = "Buffering video..."
            }
          }
        }
        self.scheduleTimeout("The stream did not start. Try the web player or Reload.")
      }
    }
  }

  private func fallback(_ message: String) {
    guard !closed else { return }
    generation += 1
    resetPlayer()
    useWeb = true
    statusLabel.text = direct ? "Could not play this stream. Check the connection or tap Reload." : message
    playerController.view.isHidden = !direct
    webView.isHidden = direct
  }
  @objc private func showWeb() {
    guard !direct else { return }
    fallback("Web player. Tap Play if needed. Reload retries system playback.")
  }
  @objc private func close() {
    guard !closed else { return }
    closed = true
    generation += 1
    resetPlayer()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaCandidate", contentWorld: .defaultClient)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    dismiss(animated: true) { self.completion() }
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard !closed, !direct, message.name == "mediaCandidate", let frameURL = message.frameInfo.request.url, MediaPolicy.sameOrigin(frameURL, initialURL), let body = message.body as? [String: Any], let value = body["url"] as? String, let url = URL(string: value) else { return }
    guard !attempted, !useWeb else { return }
    candidateFrame = message.frameInfo
    startPlayer(url)
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard !closed, action.targetFrame != nil, let url = action.request.url else { decisionHandler(.cancel); return }
    if action.targetFrame?.isMainFrame == true {
      decisionHandler(MediaPolicy.sameOrigin(url, initialURL) ? .allow : .cancel)
    } else {
      decisionHandler(MediaPolicy.allowed(url) || url.scheme == "about" ? .allow : .cancel)
    }
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if !closed, (error as NSError).code != NSURLErrorCancelled { fallback("Could not load the media page. Check the connection and tap Reload.") }
  }
}
