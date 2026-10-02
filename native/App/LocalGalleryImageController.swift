import ImageIO
import UIKit

private final class LocalImageScroll: UIScrollView {
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === panGestureRecognizer { return zoomScale > minimumZoomScale + 0.01 }
    return super.gestureRecognizerShouldBegin(gestureRecognizer)
  }
}

final class LocalGalleryImageController: UIViewController, UIScrollViewDelegate {
  private let file: URL
  let scroll: UIScrollView = LocalImageScroll()
  private let image = UIImageView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let error = UILabel()
  private var decoding: Task<Void, Never>?
  private var decodedLimit = 0
  private var requestedLimit = 0
  private var generation = UUID()
  var zoomChanged: ((Bool) -> Void)?
  var toggleChrome: (() -> Void)?
  var zoomed: Bool { scroll.zoomScale > scroll.minimumZoomScale + 0.01 }

  init(file: URL) { self.file = file; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
    scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
    scroll.contentInsetAdjustmentBehavior = .never
    image.contentMode = .scaleAspectFit
    for child in [scroll, image, spinner, error] { child.translatesAutoresizingMaskIntoConstraints = false }
    view.addSubview(scroll); scroll.addSubview(image); view.addSubview(spinner); view.addSubview(error)
    spinner.color = .white
    error.textColor = .white; error.textAlignment = .center; error.numberOfLines = 0
    error.font = .preferredFont(forTextStyle: .body); error.isHidden = true
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      image.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), image.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      image.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), image.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      image.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor), image.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      error.centerYAnchor.constraint(equalTo: view.centerYAnchor), error.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      error.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
    ])
    let single = UITapGestureRecognizer(target: self, action: #selector(tap))
    let double = UITapGestureRecognizer(target: self, action: #selector(zoom))
    double.numberOfTapsRequired = 2
    single.require(toFail: double)
    scroll.addGestureRecognizer(single); scroll.addGestureRecognizer(double)
    loadImage(limit: 1024)
  }

  func setActive(_ active: Bool) {
    loadViewIfNeeded()
    if !active { scroll.setZoomScale(1, animated: false) }
    loadImage(limit: active ? 4096 : 1024)
  }
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
  func scrollViewDidZoom(_ scrollView: UIScrollView) { zoomChanged?(zoomed) }
  @objc private func tap() { toggleChrome?() }
  @objc private func zoom(_ gesture: UITapGestureRecognizer) {
    if zoomed { scroll.setZoomScale(1, animated: true); return }
    let point = gesture.location(in: image)
    let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
    scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
  }
  private func loadImage(limit: Int) {
    guard requestedLimit != limit || (decoding == nil && decodedLimit != limit) else { return }
    decoding?.cancel(); decoding = nil; requestedLimit = limit
    let token = UUID(); generation = token
    guard decodedLimit != limit else { spinner.stopAnimating(); return }
    if image.image == nil { spinner.startAnimating() }
    let file = file
    decoding = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) { () -> UIImage? in
        guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: limit,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary), !Task.isCancelled else { return nil }
        return UIImage(cgImage: decoded)
      }
      let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
      guard let self, !Task.isCancelled, token == self.generation else { return }
      self.decoding = nil
      self.spinner.stopAnimating()
      if let result { self.image.image = result; self.decodedLimit = limit; self.error.isHidden = true }
      else if self.image.image == nil { self.error.text = AppText.text("Could not open the source image."); self.error.isHidden = false }
    }
  }
  deinit { decoding?.cancel() }
}
