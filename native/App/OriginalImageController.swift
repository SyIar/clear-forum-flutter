import ForumUI
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
  private let previewLoader: (() async -> UIImage?)?
  private let localSourceLoader: (() async throws -> URL?)?
  private var localLookup: Task<Void, Never>?
  private var preview: UIImage
  private var gallerySelected = true
  private let scroll = ImageScrollView()
  private let imageView = UIImageView()
  private let originalButton = UIButton(type: .system)
  private var transfer: MediaFileTransfer?
  private var file: URL?
  private var originalLoaded = false
  private var decoding: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?
  private let spinner = UIActivityIndicatorView(style: .large)
  var zoomChanged: ((Bool) -> Void)?
  var imageChanged: (() -> Void)?
  var zoomed: Bool { scroll.zoomScale > scroll.minimumZoomScale + 0.001 }
  var canShare: Bool { file != nil || (imageView.image?.size.width ?? 0) > 0 }
  init(source: ImageViewerSource, localSourceLoader: (() async throws -> URL?)? = nil, previewLoader: (() async -> UIImage?)? = nil) {
    self.source = source; self.preview = source.preview; self.previewLoader = previewLoader; self.localSourceLoader = localSourceLoader
    super.init(nibName: nil, bundle: nil)
  }
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
    configuration.image = ForumIcons.image( "magnifyingglass")
    configuration.cornerStyle = .capsule; configuration.baseForegroundColor = .white
    originalButton.configuration = configuration
    originalButton.accessibilityLabel = AppText.text("View source image at full resolution")
    originalButton.translatesAutoresizingMaskIntoConstraints = false
    originalButton.addTarget(self, action: #selector(loadOriginal), for: .touchUpInside)
    view.addSubview(originalButton)
    NSLayoutConstraint.activate([
      originalButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      originalButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      originalButton.widthAnchor.constraint(equalToConstant: 48), originalButton.heightAnchor.constraint(equalToConstant: 48),
    ])
    spinner.translatesAutoresizingMaskIntoConstraints = false; spinner.color = .white
    view.addSubview(spinner)
    NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    if let previewLoader {
      spinner.startAnimating()
      previewTask = Task { [weak self] in
        let preview = await previewLoader()
        guard let self, !Task.isCancelled else { return }
        self.previewTask = nil; self.spinner.stopAnimating()
        if let preview { self.preview = preview }
        guard !self.originalLoaded, self.transfer == nil, self.decoding == nil else { return }
        if let preview {
          self.imageView.image = preview; self.view.setNeedsLayout(); self.imageChanged?()
        } else if self.gallerySelected { self.loadOriginal() }
      }
    }
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Keep system delegates intact: edge return wins; zoomed content keeps pan.
    if let edge = navigationController?.interactivePopGestureRecognizer { scroll.panGestureRecognizer.require(toFail: edge) }
    if #available(iOS 26.0, *), let content = navigationController?.interactiveContentPopGestureRecognizer {
      content.require(toFail: scroll.panGestureRecognizer)
    }
    if gallerySelected && source.loadOriginalOnOpen && !originalLoaded { loadOriginal() }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
          scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
    let fit = min(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
    scroll.maximumZoomScale = max(8, image.scale / (fit * max(1, traitCollection.displayScale)))
  }
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
  func scrollViewDidZoom(_ scrollView: UIScrollView) { zoomChanged?(zoomed) }
  @objc private func zoom() { scroll.setZoomScale(scroll.zoomScale > 1 ? 1 : 2.5, animated: true) }
  @objc private func loadOriginal() {
    if originalLoaded { zoom(); return }
    guard transfer == nil, decoding == nil, localLookup == nil else { return }
    originalButton.configuration?.showsActivityIndicator = true
    if let localSourceLoader {
      localLookup = Task { [weak self] in
        do {
          guard let file = try await localSourceLoader() else {
            throw MediaFileError(message: AppText.text("This image has not been downloaded. Continue the thread download to save it."))
          }
          guard let self, !Task.isCancelled else { try? FileManager.default.removeItem(at: file); return }
          self.localLookup = nil
          self.decode(file)
        } catch {
          guard let self, !Task.isCancelled else { return }
          self.localLookup = nil; self.failed(error)
        }
      }
      return
    }
    let transfer = MediaFileTransfer(limit: MediaFilePolicy.imageLimit, referer: source.url.deletingLastPathComponent(), progress: { _ in }, completion: { [weak self] result in
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
    decoding = Task { [weak self] in
      let result = await Task.detached(priority: .userInitiated) { () -> Result<UIImage, Error> in
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = values[kCGImagePropertyPixelWidth] as? Int, let height = values[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 80_000_000 else {
          return .failure(MediaFileError(message: AppText.text("This image is invalid or exceeds the full-resolution memory limit.")))
        }
        guard let image = UIImage(contentsOfFile: file.path) else { return .failure(MediaFileError(message: AppText.text("Could not open the source image."))) }
        return .success(image)
      }.value
      guard let self, !Task.isCancelled else { return }
      self.decoding = nil
      self.originalButton.configuration?.showsActivityIndicator = false
      switch result {
      case .success(let image):
        self.scroll.setZoomScale(1, animated: false)
        self.imageView.image = image; self.originalLoaded = true
        self.imageChanged?()
        self.view.setNeedsLayout()
        self.originalButton.accessibilityLabel = AppText.text("Zoom source image")
      case .failure(let error): self.failed(error)
      }
    }
  }
  private func failed(_ error: Error) {
    originalButton.configuration?.showsActivityIndicator = false
    if let file { try? FileManager.default.removeItem(at: file); self.file = nil }
    guard !(error is CancellationError), viewIfLoaded?.window != nil, presentedViewController == nil else { return }
    let message = (error as? MediaFileError)?.message ?? AppText.text("Could not open the source image. Tap the magnifier to retry.")
    ForumDialogs.notice(title: AppText.text("Image"), message: message, close: AppText.text("OK"))
  }
  func stopLoading() {
    localLookup?.cancel(); localLookup = nil
    previewTask?.cancel(); previewTask = nil
    transfer?.cancel(); transfer = nil
    decoding?.cancel(); decoding = nil
  }
  func setGallerySelected(_ selected: Bool) {
    gallerySelected = selected
    guard isViewLoaded else { return }
    if selected {
      if previewTask == nil && !originalLoaded && (source.loadOriginalOnOpen || preview.size.width == 0) { loadOriginal() }
    } else {
      // Neighbors retain only previews, never several full-resolution bitmaps.
      localLookup?.cancel(); localLookup = nil
      transfer?.cancel(); transfer = nil; decoding?.cancel(); decoding = nil
      imageView.image = preview; originalLoaded = false
      scroll.setZoomScale(1, animated: false)
      if let file { try? FileManager.default.removeItem(at: file); self.file = nil }
      originalButton.configuration?.showsActivityIndicator = false
      originalButton.accessibilityLabel = AppText.text("View source image at full resolution")
    }
  }
  deinit { if let file { try? FileManager.default.removeItem(at: file) } }
  func shareImage() {
    guard canShare else { return }
    let items: [Any] = file.map { [$0] } ?? [imageView.image ?? source.preview]
    let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
    share.popoverPresentationController?.sourceView = originalButton
    present(share, animated: true)
  }
}
