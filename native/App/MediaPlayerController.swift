import AVKit
import AVFoundation
import UIKit
import WebKit
import Combine

final class MediaPlayerController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  var requestClose: (() -> Void)?
  var immersiveChanged: ((Bool) -> Void)?
  private let initialURL: URL
  private let forumReferer: URL
  private let direct: Bool
  private let completion: () -> Void
  private let store = WKWebsiteDataStore.nonPersistent()
  private let diagnostics = MediaDiagnostics()
  private var webView: WKWebView!
  private let playerController = AVPlayerViewController()
  private let fullscreenButton = UIButton(type: .system)
  private let downloadButton = UIButton(type: .system)
  private let downloadLabel = UILabel()
  private lazy var download = VideoDownload.existingOrNew(for: initialURL)
  private var downloadObservation: AnyCancellable?
  private var downloadSource: (url: URL, cookies: [HTTPCookie])?
  private var downloadFailureShown = false
  private var immersive = false
  private var regularBounds: [NSLayoutConstraint] = []
  private var fullscreenBounds: [NSLayoutConstraint] = []
  private let waitingView = UIView()
  private let messageLabel = UILabel()
  private let hintLabel = UILabel()
  private let bufferLabel = UILabel()
  private let transferLabel = UILabel()
  private let bufferProgress = UIProgressView(progressViewStyle: .default)
  private var loadingTimer: Timer?
  private var loadingStarted: TimeInterval = 0
  private var loadingHint = ""
  private var transferRate = PlaybackTransferRate()
  private var bufferReport = "No playback buffer metrics yet."
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
  private var genericEmbed: Bool { !direct && MediaPolicy.turboID(initialURL) == nil }

  init(url: URL, direct: Bool, referer: URL = URL(string: "https://simpcity.cr/")!, completion: @escaping () -> Void) {
    initialURL = url
    forumReferer = referer
    self.direct = direct
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = initialURL.host
    view.backgroundColor = .systemBackground
    // Standard bar items receive UIKit's native Liquid Glass on iOS 26+.
    // Keep the navigation bar's system background and touch handling intact.
    let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(close))
    backButton.accessibilityLabel = "Back to thread"
    backButton.tintColor = .label
    navigationItem.leftBarButtonItem = backButton
    let reloadButton = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(reload))
    reloadButton.accessibilityLabel = "Refresh video"
    reloadButton.tintColor = .label
    navigationItem.rightBarButtonItems = [reloadButton, UIBarButtonItem(title: "Details", style: .plain, target: self, action: #selector(showDetails))]
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
    let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
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

  override var prefersStatusBarHidden: Bool { immersive }
  override var prefersHomeIndicatorAutoHidden: Bool { immersive }
  override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateDownloadButton()
  }

  private func configureFullscreenButton() {
    fullscreenButton.addTarget(self, action: #selector(toggleFullscreen), for: .touchUpInside)
    downloadButton.addTarget(self, action: #selector(downloadVideo), for: .touchUpInside)
    let glass = UIGlassEffect(style: .regular)
    glass.isInteractive = true
    let group = UIVisualEffectView(effect: glass)
    // UIGlassEffect supplies its native capsule shape and optical edge.
    group.translatesAutoresizingMaskIntoConstraints = false
    let stack = UIStackView(arrangedSubviews: [downloadButton, fullscreenButton])
    stack.axis = .horizontal; stack.distribution = .fillEqually
    stack.translatesAutoresizingMaskIntoConstraints = false
    group.contentView.addSubview(stack); view.addSubview(group)
    downloadLabel.font = .preferredFont(forTextStyle: .caption1)
    downloadLabel.numberOfLines = 2; downloadLabel.textAlignment = .right
    downloadLabel.backgroundColor = .secondarySystemBackground
    downloadLabel.layer.cornerRadius = 8; downloadLabel.clipsToBounds = true
    downloadLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(downloadLabel)
    NSLayoutConstraint.activate([
      group.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      // Leave the AVKit transport/scrubber touch region unobstructed.
      group.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -76),
      group.heightAnchor.constraint(equalToConstant: 48), group.widthAnchor.constraint(equalToConstant: 104),
      stack.topAnchor.constraint(equalTo: group.contentView.topAnchor), stack.bottomAnchor.constraint(equalTo: group.contentView.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor), stack.trailingAnchor.constraint(equalTo: group.contentView.trailingAnchor),
      downloadLabel.bottomAnchor.constraint(equalTo: group.topAnchor, constant: -8),
      downloadLabel.trailingAnchor.constraint(equalTo: group.trailingAnchor),
      downloadLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
    ])
    downloadObservation = download.objectWillChange.sink { [weak self] in
      DispatchQueue.main.async { self?.updateDownloadButton() }
    }
    updateDownloadButton()
    updateFullscreenButton()
  }
  private func updateFullscreenButton() {
    var configuration: UIButton.Configuration
    configuration = .plain()
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
    var configuration = UIButton.Configuration.plain()
    let symbol = download.canCancel ? "xmark" : (download.phase == .saved ? "checkmark" : "arrow.down.to.line")
    configuration.image = UIImage(systemName: symbol)
    configuration.baseForegroundColor = .label
    configuration.showsActivityIndicator = download.phase == .saving
    downloadButton.configuration = configuration
    downloadButton.isEnabled = download.canCancel || (!download.busy && downloadSource != nil)
    downloadButton.accessibilityLabel = download.canCancel ? "Cancel video download" : "Download video to Photos"
    downloadLabel.text = download.progress.map { "Downloading \(Int($0 * 100))%" } ?? download.message
    downloadLabel.isHidden = download.message.isEmpty
    if download.phase == .failed, !downloadFailureShown, viewIfLoaded?.window != nil, presentedViewController == nil {
      downloadFailureShown = true
      let alert = UIAlertController(title: "Video download", message: download.message, preferredStyle: .alert)
      if let file = download.exportFile {
        alert.addAction(UIAlertAction(title: "Save to Files", style: .default) { [weak self] _ in
          self?.present(UIDocumentPickerViewController(forExporting: [file], asCopy: true), animated: true)
        })
      }
      alert.addAction(UIAlertAction(title: "OK", style: .cancel))
      present(alert, animated: true)
    }
  }
  @objc private func downloadVideo() {
    if download.canCancel { download.cancel(); return }
    guard !download.busy, let source = downloadSource else { return }
    downloadFailureShown = false
    download.start(url: source.url, cookies: source.cookies, turboID: MediaPolicy.turboID(initialURL), referer: forumReferer)
  }
  @objc func showDetails() {
    guard presentedViewController == nil else { return }
    let controller = MediaDetailsController { [weak self] in
      guard let self else { return "Playback closed." }
      let available = self.downloadSource != nil ? "available" : "not available (web-only or still resolving)"
      return self.diagnostics.report + "\n\n" + self.bufferReport + "\n\nDownload source: " + available + "\n" + self.download.diagnostics.report
    }
    present(UINavigationController(rootViewController: controller), animated: true)
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
    for label in [bufferLabel, transferLabel] {
      label.font = .preferredFont(forTextStyle: .subheadline)
      label.adjustsFontForContentSizeCategory = true
      label.textColor = .secondaryLabel
      label.numberOfLines = 0
      label.textAlignment = .center
    }
    bufferProgress.accessibilityLabel = "Buffered portion of video"
    retryButton.configuration = .filled()
    retryButton.setTitle("Retry", for: .normal)
    retryButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
    webButton.configuration = .bordered()
    webButton.setTitle("Web player", for: .normal)
    webButton.addTarget(self, action: #selector(showWeb), for: .touchUpInside)
    webButton.isHidden = direct
    let stack = UIStackView(arrangedSubviews: [spinner, messageLabel, hintLabel, bufferLabel, bufferProgress, transferLabel, retryButton, webButton])
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
    loadingHint = hint
    messageLabel.text = title
    hintLabel.text = hint
    waitingView.isHidden = false
    webView.isUserInteractionEnabled = false
    busy ? spinner.startAnimating() : spinner.stopAnimating()
    spinner.isHidden = !busy
    retryButton.isHidden = busy
    webButton.isHidden = direct
    bufferLabel.isHidden = true
    bufferProgress.isHidden = true
    transferLabel.isHidden = true
  }
  private func startLoadingMetrics() {
    loadingTimer?.invalidate()
    loadingStarted = ProcessInfo.processInfo.systemUptime
    transferRate = PlaybackTransferRate()
    bufferReport = "Resolving playback source; buffer and transfer speed are not available yet."
    loadingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.updateLoadingMetrics()
    }
    updateLoadingMetrics()
  }
  private func updateLoadingMetrics() {
    guard !closed, !failed, !hasPlayed, !waitingView.isHidden else { return }
    let now = ProcessInfo.processInfo.systemUptime
    let elapsed = max(0, Int(now - loadingStarted))
    hintLabel.text = "\(loadingHint)\nWaiting \(elapsed)s"
    guard let item = playerController.player?.currentItem else { return }
    let ranges = item.loadedTimeRanges.map { value -> (start: Double, end: Double) in
      let range = value.timeRangeValue
      return (range.start.seconds, CMTimeRangeGetEnd(range).seconds)
    }
    let metrics = PlaybackBufferMetrics(ranges: ranges, duration: item.duration.seconds, position: item.currentTime().seconds)
    let ahead = String(format: "%.1f s ready ahead", metrics.secondsAhead)
    bufferLabel.isHidden = false
    if let fraction = metrics.fraction {
      let percent = String(format: "%.1f%% of video buffered", fraction * 100)
      bufferLabel.text = "\(percent)\n\(ahead)"
      bufferProgress.isHidden = false
      bufferProgress.setProgress(Float(fraction), animated: !UIAccessibility.isReduceMotionEnabled)
    } else {
      bufferLabel.text = ahead
      bufferProgress.isHidden = true
    }
    let events = item.accessLog()?.events ?? []
    let available = !events.isEmpty && events.allSatisfy { $0.numberOfBytesTransferred >= 0 && $0.transferDuration.isFinite && $0.transferDuration >= 0 }
    let bytes = available ? events.reduce(Int64(0)) { $0 + $1.numberOfBytesTransferred } : nil
    let duration = available ? events.reduce(0.0) { $0 + $1.transferDuration } : nil
    let rate = transferRate.sample(bytes: bytes, transferDuration: duration, now: now)
    if let rate {
      let formatted = ByteCountFormatter.string(fromByteCount: Int64(min(rate, 1e15)), countStyle: .decimal)
      transferLabel.text = "Recent transfer ~\(formatted)/s"
    } else {
      transferLabel.text = "Transfer speed unavailable"
    }
    transferLabel.isHidden = false
    bufferReport = "Waiting \(elapsed)s\n\(bufferLabel.text ?? "")\n\(transferLabel.text ?? "")\nPercent measures buffered video time, not readiness to start. Speed uses recent access-log transfer counters."
  }
  private func resetPlayer() {
    loadingTimer?.invalidate()
    loadingTimer = nil
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
    diagnostics.record("attempt", "Reload")
    waiting("Preparing video", hint: "Please wait for the video to load.", busy: true)
    startLoadingMetrics()
    if direct {
      startPlayer(initialURL, cookies: [])
    } else if let id = MediaPolicy.turboID(initialURL) {
      // Normal provider requests run without creating a player page or ad overlay.
      resolveTurbo(id)
    } else {
      // Some providers expose their source only after a real Play gesture.
      waitingView.isHidden = true
      spinner.stopAnimating()
      webView.isUserInteractionEnabled = true
      loadWebPage()
    }
  }
  private func resolveTurbo(_ id: String) {
    let epoch = generation
    waiting("Resolving video", hint: "Connecting to the video provider.", busy: true)
    scheduleTimeout("The provider did not finish responding. Please refresh to try again.", stage: "resolver")
    store.httpCookieStore.getAllCookies { [weak self] cookies in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        let resolver = TurboResolver(id: id, cookies: cookies, referer: self.forumReferer, event: { [weak self] stage, detail in
          guard let self = self, self.active(epoch) else { return }
          self.diagnostics.record(stage, detail)
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
    request.setValue(forumReferer.absoluteString, forHTTPHeaderField: "Referer")
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
    if !genericEmbed {
      waiting("Buffering video", hint: "Playback starts when enough data is ready.", busy: true)
    }
    scheduleTimeout("The stream did not start. Please refresh to try again.", stage: "avkit")
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
      self.fail("Playback stopped with an error. Please refresh to try again.", stage: "playback")
    })
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, self.active(epoch) else { return }
        if item.status == .failed {
          self.diagnostics.error("avkit", item.error as NSError?)
          self.recordPlayerErrors()
          self.fail("The system player could not load this stream. Please refresh to try again.", stage: "avkit")
        } else if item.status == .readyToPlay {
          self.downloadSource = (url, applicable)
          self.updateDownloadButton()
          self.diagnostics.record("avkit", "readyToPlay")
          if let frame = self.candidateFrame {
            self.webView.callAsyncJavaScript("document.querySelectorAll('video,audio').forEach(element => element.pause());", arguments: [:], in: frame, in: .defaultClient, completionHandler: nil)
          }
          self.webView.isHidden = true
          self.playerController.view.isHidden = false
          if self.genericEmbed {
            self.waiting("Buffering video", hint: "Playback starts when enough data is ready.", busy: true)
          }
          self.updateLoadingMetrics()
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
          self.loadingTimer?.invalidate()
          self.loadingTimer = nil
          self.waitingView.isHidden = true
          self.spinner.stopAnimating()
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
          self.diagnostics.record("playback", "waitingToPlay")
          self.scheduleTimeout("Playback stalled. Please refresh to try again.", stage: "buffering")
        } else if self.hasPlayed {
          self.timeout?.invalidate()
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
    if genericEmbed {
      downloadSource = nil
      updateDownloadButton()
      // Keep the initialized page and its user gesture/session intact.
      generation += 1
      resetPlayer()
      useWeb = true
      waitingView.isHidden = true
      spinner.stopAnimating()
      playerController.view.isHidden = true
      webView.isHidden = false
      webView.isUserInteractionEnabled = true
      return
    }
    generation += 1
    failed = true
    stopWork()
    playerController.view.isHidden = true
    // Turbo failures never switch to an interactive advertising page.
    waiting(hasPlayed ? "Playback interrupted" : "Could not start video", hint: message, busy: false)
  }
  @objc private func showWeb() {
    guard !closed, !direct else { return }
    generation += 1
    stopWork()
    failed = false
    useWeb = true
    downloadSource = nil
    updateDownloadButton()
    diagnostics.record("web", "Opened explicitly by user")
    waitingView.isHidden = true
    spinner.stopAnimating()
    playerController.view.isHidden = true
    webView.isHidden = false
    webView.isUserInteractionEnabled = true
    loadWebPage()
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
      waiting("Could not load video", hint: "Please refresh to try again.", busy: false)
    } else {
      fail("Could not load the media page. Please refresh to try again.", stage: "web")
    }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if let navigation = navigation, navigation === activeNavigation { webFailed(error) }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if let navigation = navigation, navigation === activeNavigation { webFailed(error) }
  }
}
