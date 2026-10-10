import SwiftUI
import UIKit

struct ImageGalleryPager: UIViewControllerRepresentable {
  let source: ImageViewerSource
  let entries: [ImageGalleryEntry]
  let images: ImageStore
  let selected: (Int, OriginalImageController?) -> Void

  func makeUIViewController(context: Context) -> ImageGalleryController {
    let controller = ImageGalleryController(source: source, entries: entries, images: images)
    controller.selected = selected
    return controller
  }
  func updateUIViewController(_ controller: ImageGalleryController, context: Context) { controller.selected = selected }
  static func dismantleUIViewController(_ controller: ImageGalleryController, coordinator: ()) { controller.stopLoading() }
}

final class ImageGalleryController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
  private let source: ImageViewerSource
  private let entries: [ImageGalleryEntry]
  private let images: ImageStore
  private var index: Int
  private var pages: [Int: OriginalImageController] = [:]
  private weak var pageScroll: UIScrollView?
  private var transitioning = false
  private var stopped = false
  var selected: ((Int, OriginalImageController?) -> Void)?

  init(source: ImageViewerSource, entries: [ImageGalleryEntry], images: ImageStore) {
    self.source = source; self.entries = entries; self.images = images
    index = entries.firstIndex { $0.url == source.url } ?? 0
    super.init(transitionStyle: .scroll, navigationOrientation: .horizontal)
  }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    dataSource = self; delegate = self
    setViewControllers([page(index)], direction: .forward, animated: false)
    pageScroll = view.subviews.compactMap { $0 as? UIScrollView }.first
    pageScroll?.isDirectionalLockEnabled = true
    view.accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: AppText.text("Previous image"), target: self, selector: #selector(previousImage)),
      UIAccessibilityCustomAction(name: AppText.text("Next image"), target: self, selector: #selector(nextImage)),
    ]
    notifySelection()
  }
  private func page(_ number: Int) -> OriginalImageController {
    if let existing = pages[number] { return existing }
    let entry = entries[number]
    let initial = entry.url == source.url ? source : ImageViewerSource(preview: UIImage(), url: entry.url)
    let child = OriginalImageController(source: initial, previewLoader: entry.url == source.url ? nil : { [images] in
      await images.load(entry.previewURL)
    })
    child.zoomChanged = { [weak self] zoomed in
      guard let self, self.index == number, !self.stopped else { return }
      self.pageScroll?.isScrollEnabled = !zoomed
    }
    child.imageChanged = { [weak self] in
      guard let self, self.index == number else { return }; self.notifySelection()
    }
    pages[number] = child
    return child
  }
  func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore controller: UIViewController) -> UIViewController? {
    neighbor(of: controller, offset: -1)
  }
  func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? {
    neighbor(of: controller, offset: 1)
  }
  private func neighbor(of controller: UIViewController, offset: Int) -> UIViewController? {
    guard !stopped, let number = pages.first(where: { $0.value === controller })?.key,
          entries.indices.contains(number + offset) else { return nil }
    return page(number + offset)
  }
  func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { transitioning = true }
  func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
    transitioning = false
    guard !stopped else { return }
    if completed, let current = viewControllers?.first, let number = pages.first(where: { $0.value === current })?.key { index = number }
    trimPages()
    notifySelection()
  }
  private func trimPages() {
    for (number, page) in pages where abs(number - index) > 1 { page.stopLoading() }
    pages = pages.filter { abs($0.key - index) <= 1 }
  }
  private func notifySelection() {
    // UIKit may prepare pages during a SwiftUI update; publish after that pass.
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.stopped else { return }
      let image = self.pages[self.index]
      self.pageScroll?.isScrollEnabled = image?.zoomed != true
      self.selected?(self.index, image)
    }
  }
  @objc private func previousImage() -> Bool { move(-1) }
  @objc private func nextImage() -> Bool { move(1) }
  override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
    switch direction {
    case .left: return move(1)
    case .right: return move(-1)
    default: return super.accessibilityScroll(direction)
    }
  }
  private func move(_ offset: Int) -> Bool {
    let next = index + offset
    guard !stopped, !transitioning, entries.indices.contains(next) else { return false }
    transitioning = true
    setViewControllers([page(next)], direction: offset > 0 ? .forward : .reverse, animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] finished in
      guard let self, !self.stopped else { return }
      self.transitioning = false
      if finished { self.index = next }
      self.trimPages(); self.notifySelection()
    }
    return true
  }
  func stopLoading() {
    stopped = true; selected = nil
    for page in pages.values { page.stopLoading() }
  }
}
