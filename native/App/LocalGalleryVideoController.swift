import AVFoundation
import ForumUI
import UIKit

private final class LocalVideoCanvas: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Seeking is owned exclusively by the slider, leaving the video canvas for gallery gestures.
final class LocalGalleryVideoController: UIViewController {
  private let file: URL
  private let player = AVPlayer()
  private let canvas = LocalVideoCanvas()
  private let play = UIButton(type: .system)
  private let fullscreen = UIButton(type: .system)
  private let slider = UISlider()
  private let time = UILabel()
  private let controls = UIStackView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let error = UILabel()
  private var status: NSKeyValueObservation?
  private var playbackStatus: NSKeyValueObservation?
  private var failure: NSObjectProtocol?
  private var background: NSObjectProtocol?
  private var timer: Any?
  private var active = false
  private var scrubbing = false
  private var resumeAfterSeek = false
  private var audioActive = false
  private var prepared = false
  private var position: Double
  private var duration: Double = 0
  private var seekToken = UUID()
  private var scrub = VideoScrubState()
  var savePosition: ((Double) -> Void)?
  var toggleChrome: (() -> Void)?
  var scrubbingChanged: ((Bool) -> Void)?

  init(file: URL, position: Double = 0) { self.file = file; self.position = position; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    canvas.playerLayer.player = player; canvas.playerLayer.videoGravity = .resizeAspect
    for child in [canvas, controls, fullscreen, spinner, error] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
    configureButton(play, symbol: "play", title: AppText.text("Play"))
    configureButton(fullscreen, symbol: "arrow.up.left.and.arrow.down.right", title: AppText.text("Full screen"))
    play.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
    fullscreen.addTarget(self, action: #selector(toggleFullscreen), for: .touchUpInside)
    time.textColor = .white; time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    time.text = "0:00 / 0:00"; time.setContentCompressionResistancePriority(.required, for: .horizontal)
    slider.minimumValue = 0; slider.maximumValue = 1; slider.tintColor = .white
    slider.accessibilityLabel = AppText.text("Video progress")
    slider.addTarget(self, action: #selector(beginSeek), for: .touchDown)
    slider.addTarget(self, action: #selector(changeSeek), for: .valueChanged)
    slider.addTarget(self, action: #selector(endSeek), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    controls.axis = .horizontal; controls.alignment = .center; controls.spacing = 10
    controls.isLayoutMarginsRelativeArrangement = true
    controls.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 12)
    controls.backgroundColor = UIColor.black.withAlphaComponent(0.6); controls.layer.cornerRadius = 25
    [play, slider, time].forEach { controls.addArrangedSubview($0) }
    spinner.color = .white
    error.textColor = .white; error.textAlignment = .center; error.numberOfLines = 0
    error.font = .preferredFont(forTextStyle: .body); error.isHidden = true
    NSLayoutConstraint.activate([
      canvas.topAnchor.constraint(equalTo: view.topAnchor), canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12), controls.heightAnchor.constraint(equalToConstant: 54),
      play.widthAnchor.constraint(equalToConstant: 44), play.heightAnchor.constraint(equalToConstant: 44),
      slider.heightAnchor.constraint(equalToConstant: 44),
      fullscreen.trailingAnchor.constraint(equalTo: controls.trailingAnchor), fullscreen.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -12),
      fullscreen.widthAnchor.constraint(equalToConstant: 48), fullscreen.heightAnchor.constraint(equalToConstant: 48),
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      error.centerYAnchor.constraint(equalTo: view.centerYAnchor), error.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      error.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
    ])
    background = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.seekToken = UUID(); self.resumeAfterSeek = false; self.scrubbing = false
        self.scrub.cancel(); self.player.currentItem?.cancelPendingSeeks()
        self.scrubbingChanged?(false); self.player.pause()
      }
    }
    setChromeHidden(false)
  }

  func setChromeHidden(_ hidden: Bool) {
    loadViewIfNeeded()
    fullscreen.configuration?.image = ForumIcons.image(hidden ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 22)
    fullscreen.accessibilityLabel = AppText.text(hidden ? "Exit full screen" : "Full screen")
  }
  func setActive(_ value: Bool) {
    guard value != active else { return }
    active = value
    if value { loadViewIfNeeded(); open() } else { stop() }
  }
  func isControlArea(_ point: CGPoint) -> Bool { controls.frame.contains(point) || fullscreen.frame.insetBy(dx: -8, dy: -8).contains(point) }

  private func configureButton(_ button: UIButton, symbol: String, title: String) {
    var config = UIButton.Configuration.glass()
    config.image = ForumIcons.image(symbol, size: 22); config.baseForegroundColor = .white; config.cornerStyle = .capsule
    button.configuration = config; button.accessibilityLabel = title
  }
  private func open() {
    prepared = false; duration = 0; renderTime(0)
    error.isHidden = true; spinner.startAnimating(); play.isEnabled = false; slider.isEnabled = false
    guard file.isFileURL, FileManager.default.isReadableFile(atPath: file.path) else { failed(); return }
    let item = AVPlayerItem(url: file)
    player.replaceCurrentItem(with: item)
    status = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
      Task { @MainActor [weak self, weak item] in
        guard let self, let item, self.active, self.player.currentItem === item else { return }
        if item.status == .failed { self.failed() }
        else if item.status == .readyToPlay { self.ready(item) }
      }
    }
    playbackStatus = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
      Task { @MainActor [weak self] in self?.updatePlayButton() }
    }
    failure = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
      Task { @MainActor [weak self, weak item] in
        guard let self, self.active, self.player.currentItem === item else { return }; self.failed()
      }
    }
    timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak item] current in
      Task { @MainActor [weak self, weak item] in
        guard let self, self.active, !self.scrubbing, self.error.isHidden, self.player.currentItem === item else { return }
        if let duration = self.player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
          self.duration = duration; self.slider.isEnabled = true
        }
        self.renderTime(current.seconds)
      }
    }
  }
  private func ready(_ item: AVPlayerItem) {
    guard !prepared else { return }; prepared = true
    duration = item.duration.seconds.isFinite ? max(0, item.duration.seconds) : 0
    slider.isEnabled = duration > 0; play.isEnabled = true; spinner.stopAnimating()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true); audioActive = true
    } catch { failed(); return }
    let start = position.isFinite && position < duration - 0.5 ? max(0, position) : 0
    let token = UUID(); seekToken = token
    player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
      Task { @MainActor [weak self, weak item] in
        guard let self, finished, self.active, !self.scrubbing, self.seekToken == token,
              self.player.currentItem === item, UIApplication.shared.applicationState == .active else { return }
        self.player.play()
      }
    }
  }
  private func renderTime(_ seconds: Double) {
    guard seconds.isFinite else { return }
    slider.value = duration > 0 ? Float(min(1, max(0, seconds / duration))) : 0
    time.text = "\(clock(seconds)) / \(clock(duration))"
    slider.accessibilityValue = time.text
  }
  private func clock(_ seconds: Double) -> String {
    let value = Int(max(0, min(seconds.isFinite ? seconds : 0, 86_400_000)))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
  }
  private func updatePlayButton() {
    let playing = player.timeControlStatus != .paused
    play.configuration?.image = ForumIcons.image(playing ? "pause" : "play", size: 22)
    play.accessibilityLabel = AppText.text(playing ? "Pause" : "Play")
  }
  @objc private func togglePlayback() {
    seekToken = UUID(); scrubbing = false; scrubbingChanged?(false)
    scrub.cancel(); player.currentItem?.cancelPendingSeeks()
    if player.timeControlStatus != .paused { player.pause() }
    else if duration > 0, player.currentTime().seconds >= duration - 0.2 {
      player.seek(to: .zero); player.play()
    } else { player.play() }
  }
  @objc private func toggleFullscreen() { toggleChrome?() }
  @objc private func beginSeek() {
    guard active, prepared, duration > 0 else { return }
    if !scrubbing { resumeAfterSeek = player.timeControlStatus != .paused }
    seekToken = UUID()
    player.currentItem?.cancelPendingSeeks(); scrub.begin()
    scrubbing = true; scrubbingChanged?(true)
    player.pause()
  }
  @objc private func changeSeek() {
    time.text = "\(clock(Double(slider.value) * duration)) / \(clock(duration))"
    slider.accessibilityValue = time.text
    // VoiceOver changes the slider without a touch-down sequence.
    if !slider.isTracking && !scrubbing {
      beginSeek(); endSeek()
    } else if let request = scrub.update(seekTarget) { seekFrame(request) }
  }
  @objc private func endSeek() {
    scrubbingChanged?(false)
    if let request = scrub.end(seekTarget) { seekFrame(request) }
  }
  private var seekTarget: Double { min(max(0, duration - 1.0 / 600), max(0, Double(slider.value) * duration)) }
  private func seekFrame(_ request: VideoScrubState.Request) {
    guard active, duration > 0 else { return }
    let token = seekToken
    let item = player.currentItem
    player.seek(to: CMTime(seconds: request.seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
      Task { @MainActor [weak self, weak item] in
        guard let self, self.active, self.player.currentItem === item, self.seekToken == token else { return }
        switch self.scrub.complete(request, succeeded: finished) {
        case .next(let next): self.seekFrame(next)
        case .finished:
          self.scrubbing = false
          if self.resumeAfterSeek, UIApplication.shared.applicationState == .active { self.player.play() }
        case .failed:
          self.scrubbing = false; self.scrubbingChanged?(false)
        case .ignored, .waiting: break
        }
      }
    }
  }
  private func failed() {
    seekToken = UUID(); scrubbing = false; scrubbingChanged?(false)
    scrub.cancel(); player.currentItem?.cancelPendingSeeks()
    spinner.stopAnimating(); player.pause(); play.isEnabled = false; slider.isEnabled = false
    error.text = AppText.text("This video or audio cannot be played by the built-in player. Its format may be unsupported or the file may be incomplete. You can share or export it.")
    error.isHidden = false
  }
  private func stop() {
    seekToken = UUID()
    scrub.cancel(); player.currentItem?.cancelPendingSeeks()
    let seconds = player.currentTime().seconds
    if seconds.isFinite { position = seconds; savePosition?(seconds) }
    player.pause(); status = nil; playbackStatus = nil; scrubbing = false
    scrubbingChanged?(false)
    if let timer { player.removeTimeObserver(timer) }; timer = nil
    if let failure { NotificationCenter.default.removeObserver(failure) }; failure = nil
    player.replaceCurrentItem(with: nil)
    if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); audioActive = false }
  }
  deinit {
    if let timer { player.removeTimeObserver(timer) }
    if let failure { NotificationCenter.default.removeObserver(failure) }
    if let background { NotificationCenter.default.removeObserver(background) }
    player.pause()
  }
}
