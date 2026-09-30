import AVKit
import AVFoundation
import UIKit
import WebKit
import Network

final class MediaPlayerController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  var requestClose: (() -> Void)?
  var immersiveChanged: ((Bool) -> Void)?
  var downloadAvailabilityChanged: ((Bool) -> Void)?
  private let initialURL: URL
  private let forumReferer: URL
  private let direct: Bool
  private let completion: () -> Void
  private let store = WKWebsiteDataStore.nonPersistent()
  private var webView: WKWebView!
  private let playerController = AVPlayerViewController()
  private let fullscreenButton = UIButton(type: .system)
  private let download: VideoDownload
  private var downloadSource: (url: URL, cookies: [HTTPCookie])?
  private var immersive = false
  private var regularBounds: [NSLayoutConstraint] = []
  private var fullscreenBounds: [NSLayoutConstraint] = []
  private let waitingView = UIView()
  private let messageLabel = UILabel()
  private let hintLabel = UILabel()
  private let errorScroll = UIScrollView()
  private let networkMonitor = NWPathMonitor()
  private let networkQueue = DispatchQueue(label: "forum.video.connection")
  private var networkLossWork: DispatchWorkItem?
  private var networkUnavailable = false
  private var networkMessageShown = false
  private var waitingForPlayback = false
  private let spinner = UIActivityIndicatorView(style: .large)
  private let webButton = UIButton(type: .system)
  private var resolver: TurboResolver?
  private var statusObservation: NSKeyValueObservation?
  private var playbackObservation: NSKeyValueObservation?
  private var notifications: [NSObjectProtocol] = []
  private var generation = 0
  private var closed = false
  private var attempted = false
  private var useWeb = false
  private var webReady = false
  private var activeNavigation: WKNavigation?
  private var failed = false
  private var hasPlayed = false
  private var candidateFrame: WKFrameInfo?
  private var genericEmbed: Bool { !direct && MediaPolicy.turboID(initialURL) == nil }

  init(url: URL, direct: Bool, referer: URL = URL(string: "https://simpcity.cr/")!, download: VideoDownload, completion: @escaping () -> Void) {
    initialURL = url
    forumReferer = referer
    self.direct = direct
    self.download = download
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Video"
    view.backgroundColor = .systemBackground
    // The parent SwiftUI destination owns the navigation bar and system back gesture.
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = store
    configuration.allowsInlineMediaPlayback = true
    // Opening this destination already follows an explicit Play tap. Cyberdrop
    // needs its primary media element started to reveal/load its stream.
    configuration.mediaTypesRequiringUserActionForPlayback = MediaPolicy.cyberdropPage(initialURL) ? [] : .all
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
    regularBounds = [
      webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
    ]
    fullscreenBounds = [
      webView.topAnchor.constraint(equalTo: view.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ]
    NSLayoutConstraint.activate(regularBounds)
    NSLayoutConstraint.activate([
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
    configureFullscreenButton()
    networkMonitor.pathUpdateHandler = { [weak self] path in
      let unavailable = path.status == .unsatisfied
      DispatchQueue.main.async {
        guard let self, !self.closed else { return }
        self.networkUnavailable = unavailable
        self.updateConnectionState()
      }
    }
    networkMonitor.start(queue: networkQueue)
    // Keep the established script/gesture behavior of non-Turbo web players.
    let rules = #" [{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".adsbygoogle,.advertisement,.ad-container,.adContainer,[data-ad-slot]"}}] "#
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "media-cosmetic-v1", encodedContentRuleList: rules) { [weak self] list, _ in
      DispatchQueue.main.async {
        guard let self = self, !self.closed else { return }
        if let list = list { configuration.userContentController.add(list) }
        self.reload()
      }
    }
  }

  override var prefersStatusBarHidden: Bool { immersive }
  override var prefersHomeIndicatorAutoHidden: Bool { immersive }
  override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateDownloadButton()
  }

  private func configureFullscreenButton() {
    fullscreenButton.addTarget(self, action: #selector(toggleFullscreen), for: .touchUpInside)
    fullscreenButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(fullscreenButton)
    NSLayoutConstraint.activate([
      fullscreenButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      // Leave the AVKit transport/scrubber touch region unobstructed.
      fullscreenButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -76),
      fullscreenButton.heightAnchor.constraint(equalToConstant: 48),
      fullscreenButton.widthAnchor.constraint(equalToConstant: 48),
    ])
    updateDownloadButton()
    updateFullscreenButton()
  }
  private func updateFullscreenButton() {
    var configuration: UIButton.Configuration
    configuration = .glass()
    configuration.image = UIImage(systemName: immersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = .label
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    fullscreenButton.configuration = configuration
    fullscreenButton.accessibilityLabel = immersive ? "Exit full screen" : "Full screen"
    fullscreenButton.accessibilityHint = immersive ? "Restore the title bar" : "Hide the title bar without restarting playback"
  }
  private func updateDownloadButton() {
    guard !closed else { return }
    downloadAvailabilityChanged?(downloadSource != nil)
  }
  func downloadVideo() {
    guard !download.busy, let source = downloadSource else { return }
    download.start(url: source.url, cookies: source.cookies, turboID: MediaPolicy.turboID(initialURL), referer: forumReferer, direct: direct)
  }
  @objc func openInBrowser() {
    guard !closed, presentedViewController == nil, let browser = ExternalBrowser.make(initialURL) else { return }
    playerController.player?.pause()
    present(browser, animated: true)
  }
  @objc private func toggleFullscreen() {
    guard !closed, navigationController?.transitionCoordinator == nil else { return }
    view.layoutIfNeeded()
    immersive.toggle()
    NSLayoutConstraint.deactivate(immersive ? regularBounds : fullscreenBounds)
    NSLayoutConstraint.activate(immersive ? fullscreenBounds : regularBounds)
    overrideUserInterfaceStyle = immersive ? .dark : .unspecified
    updateFullscreenButton()
    let animated = !UIAccessibility.isReduceMotionEnabled
    if let immersiveChanged { immersiveChanged(immersive) }
    else { navigationController?.setNavigationBarHidden(immersive, animated: animated) }
    setNeedsUpdateOfHomeIndicatorAutoHidden()
    navigationController?.setNeedsUpdateOfHomeIndicatorAutoHidden()
    UIView.animate(withDuration: animated ? 0.25 : 0) {
      self.setNeedsStatusBarAppearanceUpdate()
      self.navigationController?.setNeedsStatusBarAppearanceUpdate()
      self.view.layoutIfNeeded()
    }
  }

  private func configureWaitingView() {
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.accessibilityLabel = "Loading video"
    waitingView.addSubview(spinner)
    errorScroll.translatesAutoresizingMaskIntoConstraints = false
    errorScroll.isHidden = true
    waitingView.addSubview(errorScroll)
    spinner.startAnimating()
    messageLabel.font = AppTypography.uiFont(.title2, bold: true)
    messageLabel.adjustsFontForContentSizeCategory = true
    messageLabel.numberOfLines = 0
    messageLabel.textAlignment = .center
    hintLabel.font = AppTypography.uiFont(.body)
    hintLabel.adjustsFontForContentSizeCategory = true
    hintLabel.textColor = .secondaryLabel
    hintLabel.numberOfLines = 0
    hintLabel.textAlignment = .center
    webButton.configuration = .glass()
    let browserFont = AppTypography.uiFont(.body)
    webButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = browserFont
      return attributes
    }
    webButton.setTitle("Open in browser", for: .normal)
    webButton.addTarget(self, action: #selector(openInBrowser), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [messageLabel, hintLabel, webButton])
    stack.axis = .vertical; stack.alignment = .fill; stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    errorScroll.addSubview(stack)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: waitingView.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: waitingView.centerYAnchor),
      errorScroll.topAnchor.constraint(equalTo: waitingView.topAnchor),
      errorScroll.bottomAnchor.constraint(equalTo: waitingView.bottomAnchor),
      errorScroll.leadingAnchor.constraint(equalTo: waitingView.leadingAnchor),
      errorScroll.trailingAnchor.constraint(equalTo: waitingView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: errorScroll.contentLayoutGuide.topAnchor, constant: 48),
      stack.bottomAnchor.constraint(equalTo: errorScroll.contentLayoutGuide.bottomAnchor, constant: -32),
      stack.leadingAnchor.constraint(equalTo: errorScroll.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: errorScroll.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: errorScroll.frameLayoutGuide.widthAnchor, constant: -48),
      webButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
  }
  private func showLoading() {
    waitingForPlayback = true
    networkMessageShown = false
    waitingView.isHidden = false
    errorScroll.isHidden = true
    webView.isUserInteractionEnabled = false
    spinner.startAnimating()
    updateConnectionState()
  }
  private func hideLoading() {
    waitingForPlayback = false
    networkMessageShown = false
    networkLossWork?.cancel(); networkLossWork = nil
    waitingView.isHidden = true
    spinner.stopAnimating()
  }
  private func showError(_ message: String) {
    waitingView.isHidden = false
    errorScroll.isHidden = false
    spinner.stopAnimating()
    messageLabel.text = networkMessageShown ? "Connection lost" : (hasPlayed ? "Playback interrupted" : "Could not start video")
    hintLabel.text = message
    webView.isUserInteractionEnabled = false
  }
  private func updateConnectionState() {
    guard !closed, !failed else { return }
    if !networkUnavailable {
      networkLossWork?.cancel(); networkLossWork = nil
      if networkMessageShown { showLoading() }
      return
    }
    guard waitingForPlayback, networkLossWork == nil, !networkMessageShown else { return }
    let epoch = generation
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.networkLossWork = nil
      guard !self.closed, !self.failed, self.generation == epoch,
            self.networkUnavailable, self.waitingForPlayback else { return }
      // Keep the player alive so a brief network change can recover in place.
      self.networkMessageShown = true
      self.showError("Check your connection, then try again.")
    }
    networkLossWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
  }
  private func resetPlayer() {
    networkLossWork?.cancel(); networkLossWork = nil
    waitingForPlayback = false
    networkMessageShown = false
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

  @objc func reload() {
    guard !closed else { return }
    generation += 1
    stopWork()
    attempted = false
    candidateFrame = nil
    useWeb = false
    failed = false
    hasPlayed = false
    downloadSource = nil
    updateDownloadButton()
    playerController.view.isHidden = true
    webView.isHidden = false
    showLoading()
    if direct {
      startPlayer(initialURL, cookies: [])
    } else if let id = MediaPolicy.turboID(initialURL) {
      // Normal provider requests run without creating a player page or ad overlay.
      resolveTurbo(id)
    } else {
      // Some providers expose their source only after a real Play gesture.
      loadWebPage()
    }
  }
  private func resolveTurbo(_ id: String) {
    let epoch = generation
    store.httpCookieStore.getAllCookies { [weak self] cookies in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        let resolver = TurboResolver(id: id, cookies: cookies, referer: self.forumReferer, event: { _, _ in }, completion: { [weak self] result in
          guard let self = self, self.active(epoch) else { return }
          self.resolver = nil
          switch result {
          case .success(let media):
            self.startPlayer(media.url, cookies: media.cookies)
          case .failure:
            self.fail("The video provider could not load this video. Refresh or open it in the browser.")
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
    request.setValue(forumReferer.absoluteString, forHTTPHeaderField: "Referer")
    activeNavigation = webView.load(request)
  }
  private func startPlayer(_ url: URL, cookies: [HTTPCookie]) {
    guard !closed, !attempted, !useWeb, !failed, MediaPolicy.allowed(url) else { return }
    attempted = true
    let epoch = generation
    showLoading()
    let applicable = cookies.filter { MediaPolicy.cookieMatches($0, url) }
    let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: applicable])
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    playerController.player = player
    notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
      guard let self = self, self.active(epoch) else { return }
      self.fail("The video stopped loading. Refresh or open it in the browser.", allowWebFallback: true)
    })
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        if item.status == .failed {
          self.fail("This video could not be played. Refresh or open it in the browser.", allowWebFallback: true)
        } else if item.status == .readyToPlay {
          self.downloadSource = (url, applicable)
          self.updateDownloadButton()
          if let frame = self.candidateFrame {
            self.webView.callAsyncJavaScript("document.querySelectorAll('video,audio').forEach(element => element.pause());", arguments: [:], in: frame, in: .defaultClient, completionHandler: nil)
          }
          self.webView.isHidden = true
          // Stop the provider element after native playback is ready, preventing
          // double audio. Do not click controls or mutate provider navigation.
          self.webView.evaluateJavaScript("window.dispatchEvent(new Event('forumNativePlayback')); document.querySelectorAll('video,audio').forEach(node => node.pause())", in: self.candidateFrame, in: .defaultClient) { _ in }
          self.playerController.view.isHidden = false
          try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
          try? AVAudioSession.sharedInstance().setActive(true)
          player.play()
        }
      }
    }
    playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        if player.timeControlStatus == .playing {
          self.hasPlayed = true
          self.hideLoading()
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
          // AVPlayer resumes when enough data is ready; a slow CDN is not an error.
          self.showLoading()
        } else if self.hasPlayed {
          self.hideLoading()
        }
      }
    }
  }
  private func fail(_ message: String, allowWebFallback: Bool = false) {
    guard !closed, !failed else { return }
    if genericEmbed && allowWebFallback && webReady && !networkUnavailable {
      downloadSource = nil
      updateDownloadButton()
      // Preserve the established page/gesture fallback for non-Turbo providers.
      generation += 1
      resetPlayer()
      useWeb = true
      hideLoading()
      playerController.view.isHidden = true
      webView.isHidden = false
      webView.isUserInteractionEnabled = true
      return
    }
    generation += 1
    failed = true
    stopWork()
    playerController.view.isHidden = true
    showError(message)
  }
  @objc func close() {
    guard !closed else { return }
    if let requestClose { requestClose(); return }
    finishPlayback()
    dismiss(animated: true) { self.completion() }
  }
  // Called only after a committed return, never when an edge swipe is cancelled.
  func finishPlayback() {
    guard !closed else { return }
    closed = true
    networkMonitor.cancel()
    generation += 1
    guard isViewLoaded else { return }
    stopWork()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaCandidate", contentWorld: .defaultClient)
    webView.loadHTMLString("", baseURL: nil)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard !closed, !direct, !useWeb, !failed, !attempted, webReady, MediaPolicy.turboID(initialURL) == nil,
          message.name == "mediaCandidate", let frameURL = message.frameInfo.request.url,
          MediaPolicy.sameOrigin(frameURL, initialURL), let body = message.body as? [String: Any],
          let value = body["url"] as? String, let url = URL(string: value), MediaPolicy.allowed(url) else { return }
    candidateFrame = message.frameInfo
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
    if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
      decisionHandler(.cancel)
      fail("The video page is unavailable. Refresh or open it in the browser.")
      return
    }
    decisionHandler(closed ? .cancel : .allow)
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    if let navigation = navigation, navigation === activeNavigation {
      webReady = true
      if genericEmbed && (!attempted || useWeb) {
        hideLoading()
        webView.isUserInteractionEnabled = true
      }
    }
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard !closed, !failed, let navigation, navigation === activeNavigation, !attempted || useWeb else { return }
    hideLoading()
    webView.isUserInteractionEnabled = true
  }
  private func webFailed(_ error: Error) {
    let error = error as NSError
    guard !closed, error.code != NSURLErrorCancelled else { return }
    fail("The video page could not load. Check your connection or open it in the browser.")
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if let navigation = navigation, navigation === activeNavigation { webFailed(error) }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if let navigation = navigation, navigation === activeNavigation { webFailed(error) }
  }
}
