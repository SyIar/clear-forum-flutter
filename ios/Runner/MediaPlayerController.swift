import AVKit
import AVFoundation
import UIKit
import WebKit

final class MediaPlayerController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  private let initialURL: URL
  private let direct: Bool
  private let completion: () -> Void
  private let store = WKWebsiteDataStore.nonPersistent()
  private let diagnostics = MediaDiagnostics()
  private var webView: WKWebView!
  private let playerController = AVPlayerViewController()
  private let statusLabel = UILabel()
  private let waitingView = UIView()
  private let messageLabel = UILabel()
  private let hintLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .large)
  private let retryButton = UIButton(type: .system)
  private let webButton = UIButton(type: .system)
  private var resolver: TurboResolver?
  private var statusObservation: NSKeyValueObservation?
  private var playbackObservation: NSKeyValueObservation?
  private var notifications: [NSObjectProtocol] = []
  private var timeout: Timer?
  private var generation = 0
  private var closed = false
  private var attempted = false
  private var useWeb = false
  private var webReady = false
  private var activeNavigation: WKNavigation?
  private var failed = false
  private var hasPlayed = false
  private var loggedMediaErrors = 0
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
    let reloadButton = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(reload))
    reloadButton.accessibilityLabel = "Reload"
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(title: "Details", style: .plain, target: self, action: #selector(showDetails)),
      reloadButton,
    ]
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
    statusLabel.adjustsFontForContentSizeCategory = true
    statusLabel.textColor = .secondaryLabel
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(statusLabel)
    view.addSubview(webView)
    addChild(playerController)
    playerController.allowsPictureInPicturePlayback = false
    playerController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playerController.view)
    playerController.didMove(toParent: self)
    waitingView.backgroundColor = .systemBackground
    waitingView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(waitingView)
    configureWaitingView()
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
      waitingView.topAnchor.constraint(equalTo: webView.topAnchor),
      waitingView.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
      waitingView.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
      waitingView.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
    ])
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    diagnostics.record("app", "build=\(build), iOS=\(UIDevice.current.systemVersion)")
    diagnostics.record("provider", MediaPolicy.turboID(initialURL) == nil ? (direct ? "direct-media" : "generic-embed") : "turbo")
    // Keep provider scripts intact when the user explicitly opens its web player.
    let rules = #" [{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".adsbygoogle,.advertisement,.ad-container,.adContainer,[data-ad-slot]"}}] "#
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "media-cosmetic-v1", encodedContentRuleList: rules) { [weak self] list, _ in
      DispatchQueue.main.async {
        guard let self = self, !self.closed else { return }
        if let list = list { configuration.userContentController.add(list) }
        self.reload()
      }
    }
  }

  private func configureWaitingView() {
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    waitingView.addSubview(scroll)
    messageLabel.font = .preferredFont(forTextStyle: .title2)
    messageLabel.adjustsFontForContentSizeCategory = true
    messageLabel.numberOfLines = 0
    messageLabel.textAlignment = .center
    hintLabel.font = .preferredFont(forTextStyle: .body)
    hintLabel.adjustsFontForContentSizeCategory = true
    hintLabel.textColor = .secondaryLabel
    hintLabel.numberOfLines = 0
    hintLabel.textAlignment = .center
    retryButton.configuration = .filled()
    retryButton.setTitle("Retry", for: .normal)
    retryButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
    webButton.configuration = .bordered()
    webButton.setTitle("Web player", for: .normal)
    webButton.addTarget(self, action: #selector(showWeb), for: .touchUpInside)
    webButton.isHidden = direct
    let stack = UIStackView(arrangedSubviews: [spinner, messageLabel, hintLabel, retryButton, webButton])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: waitingView.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: waitingView.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: waitingView.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: waitingView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 48),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
      retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      webButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
  }

  private func waiting(_ title: String, hint: String, busy: Bool) {
    statusLabel.text = title
    messageLabel.text = title
    hintLabel.text = hint
    waitingView.isHidden = false
    webView.isUserInteractionEnabled = false
    busy ? spinner.startAnimating() : spinner.stopAnimating()
    spinner.isHidden = !busy
    retryButton.isHidden = busy
    webButton.isHidden = direct
  }
  private func resetPlayer() {
    timeout?.invalidate()
    timeout = nil
    statusObservation?.invalidate()
    statusObservation = nil
    playbackObservation?.invalidate()
    playbackObservation = nil
    notifications.forEach { NotificationCenter.default.removeObserver($0) }
    notifications.removeAll()
    playerController.player?.pause()
    playerController.player?.replaceCurrentItem(with: nil)
    playerController.player = nil
  }
  private func stopWork() {
    resolver?.cancel()
    resolver = nil
    webView.stopLoading()
    activeNavigation = nil
    webReady = false
    resetPlayer()
  }

  @objc private func reload() {
    guard !closed else { return }
    generation += 1
    stopWork()
    attempted = false
    candidateFrame = nil
    useWeb = false
    failed = false
    hasPlayed = false
    playerController.view.isHidden = true
    webView.isHidden = false
    diagnostics.record("attempt", "Reload")
    waiting("Preparing video", hint: "Please wait. Details shows playback progress.", busy: true)
    if direct {
      startPlayer(initialURL, cookies: [])
    } else if let id = MediaPolicy.turboID(initialURL) {
      // Normal provider requests run without creating a player page or ad overlay.
      resolveTurbo(id)
    } else {
      loadWebPage()
      scheduleTimeout("No playable stream was found. Check Details or open Web player.", stage: "discovery")
    }
  }
  private func resolveTurbo(_ id: String) {
    let epoch = generation
    waiting("Resolving video", hint: "Connecting to the video provider.", busy: true)
    scheduleTimeout("The provider did not finish responding. Check Details and retry.", stage: "resolver")
    store.httpCookieStore.getAllCookies { [weak self] cookies in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        let resolver = TurboResolver(id: id, cookies: cookies, event: { [weak self] stage, detail in
          guard let self = self, self.active(epoch) else { return }
          self.diagnostics.record(stage, detail)
          self.statusLabel.text = stage == "sign" ? "Resolving stream" : "Connecting to provider"
        }, completion: { [weak self] result in
          guard let self = self, self.active(epoch) else { return }
          self.resolver = nil
          switch result {
          case .success(let media):
            self.startPlayer(media.url, cookies: media.cookies)
          case .failure(let error):
            if let underlying = error.underlying { self.diagnostics.error("resolver", underlying) }
            self.fail(error.reason, stage: "resolver")
          }
        })
        self.resolver = resolver
        resolver.start()
      }
    }
  }
  private func active(_ epoch: Int) -> Bool { !closed && generation == epoch && !useWeb && !failed }
  private func loadWebPage() {
    var request = URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.setValue("https://simpcity.cr/", forHTTPHeaderField: "Referer")
    diagnostics.record("web", "Loading provider page")
    activeNavigation = webView.load(request)
  }
  private func scheduleTimeout(_ message: String, stage: String) {
    timeout?.invalidate()
    let epoch = generation
    timeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
      guard let self = self, self.active(epoch) else { return }
      self.recordPlayerErrors()
      self.fail(message, stage: stage + "-timeout")
    }
  }

  private func startPlayer(_ url: URL, cookies: [HTTPCookie]) {
    guard !closed, !attempted, !useWeb, !failed, MediaPolicy.allowed(url) else { return }
    attempted = true
    loggedMediaErrors = 0
    let epoch = generation
    diagnostics.record("avkit", "Preparing validated HTTPS candidate")
    waiting("Opening system player", hint: "Waiting for the video to start.", busy: true)
    scheduleTimeout("The stream did not start. Check Details for the error and retry.", stage: "avkit")
    let applicable = cookies.filter { MediaPolicy.cookieMatches($0, url) }
    let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: applicable])
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    playerController.player = player
    notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak self] _ in
      guard let self = self, self.active(epoch) else { return }
      self.recordPlayerErrors()
    })
    notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
      guard let self = self, self.active(epoch) else { return }
      self.diagnostics.error("playback", note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)
      self.recordPlayerErrors()
      self.fail("Playback stopped with an error. Check Details and retry.", stage: "playback")
    })
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        if item.status == .failed {
          self.diagnostics.error("avkit", item.error as NSError?)
          self.recordPlayerErrors()
          self.fail("The system player could not load this stream. Check Details and retry.", stage: "avkit")
        } else if item.status == .readyToPlay {
          self.diagnostics.record("avkit", "readyToPlay")
          if let frame = self.candidateFrame {
            self.webView.callAsyncJavaScript("document.querySelectorAll('video,audio').forEach(element => element.pause());", arguments: [:], in: frame, in: .defaultClient, completionHandler: nil)
          }
          self.webView.isHidden = true
          self.playerController.view.isHidden = false
          self.statusLabel.text = "Buffering video"
          do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
          } catch {
            self.diagnostics.error("audio-session", error as NSError)
          }
          player.play()
        }
      }
    }
    playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        if player.timeControlStatus == .playing {
          self.timeout?.invalidate()
          if !self.hasPlayed { self.diagnostics.record("playback", "playing") }
          self.hasPlayed = true
          self.waitingView.isHidden = true
          self.spinner.stopAnimating()
          self.statusLabel.text = "System player"
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
          self.statusLabel.text = "Buffering video"
          self.diagnostics.record("playback", "waitingToPlay")
          self.scheduleTimeout("Playback stalled. Check Details and retry.", stage: "buffering")
        } else if self.hasPlayed {
          self.timeout?.invalidate()
          self.statusLabel.text = "Paused"
        }
      }
    }
  }
  private func recordPlayerErrors() {
    guard let item = playerController.player?.currentItem else { return }
    let events = item.errorLog()?.events ?? []
    for event in events.dropFirst(loggedMediaErrors).suffix(3) {
      diagnostics.record("media-error", "\(MediaDiagnostics.domain(event.errorDomain)) code=\(event.errorStatusCode)")
    }
    loggedMediaErrors = events.count
  }
  private func fail(_ message: String, stage: String) {
    guard !closed, !failed else { return }
    diagnostics.record(stage, message)
    generation += 1
    failed = true
    stopWork()
    playerController.view.isHidden = true
    // Failure never switches to an interactive advertising page.
    waiting(hasPlayed ? "Playback interrupted" : "Could not start video", hint: message, busy: false)
  }
  @objc private func showWeb() {
    guard !closed, !direct else { return }
    generation += 1
    stopWork()
    failed = false
    useWeb = true
    diagnostics.record("web", "Opened explicitly by user")
    waitingView.isHidden = true
    spinner.stopAnimating()
    playerController.view.isHidden = true
    webView.isHidden = false
    webView.isUserInteractionEnabled = true
    statusLabel.text = "Web player. Reload retries system playback."
    loadWebPage()
  }
  @objc private func showDetails() {
    let controller = UIViewController()
    controller.title = "Playback details"
    controller.view.backgroundColor = .systemBackground
    let text = UITextView()
    text.text = diagnostics.report
    text.isEditable = false
    text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    text.adjustsFontForContentSizeCategory = true
    text.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(text)
    NSLayoutConstraint.activate([
      text.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
      text.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor),
      text.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 12),
      text.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -12),
    ])
    controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak controller] _ in
      controller?.dismiss(animated: true)
    })
    controller.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy", primaryAction: UIAction { [weak controller, weak text] _ in
      UIPasteboard.general.setItems([["public.utf8-plain-text": text?.text ?? ""]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
      controller?.navigationItem.rightBarButtonItem?.title = "Copied"
    })
    present(UINavigationController(rootViewController: controller), animated: true)
  }
  @objc private func close() {
    guard !closed else { return }
    closed = true
    generation += 1
    stopWork()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaCandidate", contentWorld: .defaultClient)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    dismiss(animated: true) { self.completion() }
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard !closed, !direct, !useWeb, !failed, !attempted, webReady, MediaPolicy.turboID(initialURL) == nil,
          message.name == "mediaCandidate", let frameURL = message.frameInfo.request.url,
          MediaPolicy.sameOrigin(frameURL, initialURL), let body = message.body as? [String: Any],
          let value = body["url"] as? String, let url = URL(string: value), MediaPolicy.allowed(url) else { return }
    candidateFrame = message.frameInfo
    diagnostics.record("discovery", "HTTPS candidate observed")
    let epoch = generation
    store.httpCookieStore.getAllCookies { [weak self] cookies in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        self.startPlayer(url, cookies: cookies)
      }
    }
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard !closed, action.targetFrame != nil, let url = action.request.url else { decisionHandler(.cancel); return }
    if action.targetFrame?.isMainFrame == true {
      decisionHandler(MediaPolicy.sameOrigin(url, initialURL) ? .allow : .cancel)
    } else {
      decisionHandler(MediaPolicy.allowed(url) || url.scheme == "about" ? .allow : .cancel)
    }
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
      diagnostics.record("web", "HTTP \(http.statusCode), MIME \(MediaDiagnostics.mime(http.mimeType))")
    }
    decisionHandler(closed ? .cancel : .allow)
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    if let navigation = navigation, navigation === activeNavigation { webReady = true }
  }
  private func webFailed(_ error: Error) {
    let error = error as NSError
    guard !closed, error.code != NSURLErrorCancelled else { return }
    diagnostics.error("web", error)
    if useWeb {
      statusLabel.text = "Web page failed to load. Check Details or Reload."
    } else {
      fail("Could not load the media page. Check Details and retry.", stage: "web")
    }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if let navigation = navigation, navigation === activeNavigation { webFailed(error) }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if let navigation = navigation, navigation === activeNavigation { webFailed(error) }
  }
}
