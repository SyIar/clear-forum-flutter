import UIKit
import ImageIO

private final class ImageScrollView: UIScrollView {
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === panGestureRecognizer, zoomScale <= minimumZoomScale + 0.001 { return false }
    return super.gestureRecognizerShouldBegin(gestureRecognizer)
  }
}

final class OriginalImageController: UIViewController, UIScrollViewDelegate {
  private let source: ImageViewerSource
  private let scroll = ImageScrollView()
  private let imageView = UIImageView()
  private let originalButton = UIButton(type: .system)
  private let statusLabel = UILabel()
  private var transfer: MediaFileTransfer?
  private var file: URL?
  private var originalLoaded = false
  private var decoding: Task<Void, Never>?
  init(source: ImageViewerSource) { self.source = source; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    overrideUserInterfaceStyle = .dark
    scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 8
    scroll.delegate = self; scroll.translatesAutoresizingMaskIntoConstraints = false
    imageView.image = source.preview; imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(imageView); view.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor), imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
    ])
    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoom))
    doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
    var configuration = UIButton.Configuration.glass()
    configuration.image = UIImage(systemName: "magnifyingglass")
    configuration.cornerStyle = .capsule; configuration.baseForegroundColor = .white
    originalButton.configuration = configuration
    originalButton.accessibilityLabel = "View source image at full resolution"
    originalButton.translatesAutoresizingMaskIntoConstraints = false
    originalButton.addTarget(self, action: #selector(loadOriginal), for: .touchUpInside)
    view.addSubview(originalButton)
    statusLabel.textColor = .white; statusLabel.font = .preferredFont(forTextStyle: .caption1)
    statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    statusLabel.layer.cornerRadius = 6; statusLabel.clipsToBounds = true
    statusLabel.textAlignment = .right; statusLabel.numberOfLines = 3
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.isAccessibilityElement = true
    view.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      originalButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      originalButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      originalButton.widthAnchor.constraint(equalToConstant: 48), originalButton.heightAnchor.constraint(equalToConstant: 48),
      statusLabel.trailingAnchor.constraint(equalTo: originalButton.leadingAnchor, constant: -12),
      statusLabel.centerYAnchor.constraint(equalTo: originalButton.centerYAnchor),
      statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
    ])
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Keep system delegates intact: edge return wins; zoomed content keeps pan.
    if let edge = navigationController?.interactivePopGestureRecognizer { scroll.panGestureRecognizer.require(toFail: edge) }
    if #available(iOS 26.0, *), let content = navigationController?.interactiveContentPopGestureRecognizer {
      content.require(toFail: scroll.panGestureRecognizer)
    }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
          scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
    let fit = min(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
    scroll.maximumZoomScale = max(8, image.scale / (fit * max(1, traitCollection.displayScale)))
  }
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
  @objc private func zoom() { scroll.setZoomScale(scroll.zoomScale > 1 ? 1 : 2.5, animated: true) }
  @objc private func loadOriginal() {
    if originalLoaded { zoom(); return }
    guard transfer == nil, decoding == nil else { return }
    originalButton.configuration?.showsActivityIndicator = true
    statusLabel.text = "Loading source image..."
    let transfer = MediaFileTransfer(limit: MediaFilePolicy.imageLimit, referer: source.url.deletingLastPathComponent(), progress: { [weak self] progress in
      self?.statusLabel.text = progress.map { "Loading source image \(Int($0 * 100))%" } ?? "Loading source image..."
    }, completion: { [weak self] result in
      guard let self else { if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }; return }
      self.transfer = nil
      switch result {
      case .success(let file): self.decode(file)
      case .failure(let error): self.failed(error)
      }
    })
    self.transfer = transfer; transfer.start(source.url)
  }
  private func decode(_ file: URL) {
    self.file = file
    statusLabel.text = "Opening full resolution..."
    decoding = Task { [weak self] in
      let result = await Task.detached(priority: .userInitiated) { () -> Result<(UIImage, Int, Int), Error> in
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = values[kCGImagePropertyPixelWidth] as? Int, let height = values[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 80_000_000 else {
          return .failure(MediaFileError(message: "This image is invalid or exceeds the full-resolution memory limit."))
        }
        guard let image = UIImage(contentsOfFile: file.path) else { return .failure(MediaFileError(message: "Could not open the source image.")) }
        return .success((image, width, height))
      }.value
      guard let self, !Task.isCancelled else { return }
      self.decoding = nil
      self.originalButton.configuration?.showsActivityIndicator = false
      switch result {
      case .success(let (image, width, height)):
        self.scroll.setZoomScale(1, animated: false)
        self.imageView.image = image; self.originalLoaded = true
        self.view.setNeedsLayout()
        self.statusLabel.text = "Source \(width) \u{00D7} \(height)"
        self.originalButton.accessibilityLabel = "Zoom source image"
      case .failure(let error): self.failed(error)
      }
    }
  }
  private func failed(_ error: Error) {
    originalButton.configuration?.showsActivityIndicator = false
    statusLabel.text = error is CancellationError ? nil : (error as? MediaFileError)?.message ?? "Could not open the source image. Tap to retry."
    if let file { try? FileManager.default.removeItem(at: file); self.file = nil }
  }
  func stopLoading() {
    transfer?.cancel(); transfer = nil
    decoding?.cancel(); decoding = nil
  }
  deinit { if let file { try? FileManager.default.removeItem(at: file) } }
  func shareImage() {
    let items: [Any] = file.map { [$0] } ?? [source.preview]
    let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
    share.popoverPresentationController?.sourceView = originalButton
    present(share, animated: true)
  }
}
