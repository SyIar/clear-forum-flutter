import ForumUI
import QuickLook
import SwiftUI
import UIKit

struct LocalGalleryRequest: Identifiable {
  let id = UUID()
  let catalog: LocalFileCatalog
  let selection: LocalGallerySelection
}

struct LocalGalleryPresenter: UIViewControllerRepresentable {
  @Binding var request: LocalGalleryRequest?
  func makeUIViewController(context: Context) -> LocalGalleryHost { LocalGalleryHost() }
  func updateUIViewController(_ host: LocalGalleryHost, context: Context) {
    host.onClose = { request = nil }
    host.request = request
    host.presentIfReady()
  }
  static func dismantleUIViewController(_ host: LocalGalleryHost, coordinator: ()) { host.close() }
}

final class LocalGalleryHost: UIViewController {
  var request: LocalGalleryRequest?
  var onClose: (() -> Void)?
  private weak var gallery: LocalGalleryController?
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); presentIfReady() }
  func presentIfReady() {
    guard viewIfLoaded?.window != nil, gallery == nil, presentedViewController == nil, let request else { return }
    let controller = LocalGalleryController(request: request)
    controller.onClose = { [weak self] in
      self?.gallery = nil; self?.request = nil; self?.onClose?()
    }
    gallery = controller
    // Keep the real folder mounted underneath the interactive downward dismissal.
    controller.modalPresentationStyle = .overFullScreen
    controller.modalPresentationCapturesStatusBarAppearance = true
    controller.modalTransitionStyle = .crossDissolve
    present(controller, animated: !UIAccessibility.isReduceMotionEnabled)
  }
  func close() { gallery?.stopPlayback(); gallery?.dismiss(animated: false); gallery = nil }
}

final class LocalGalleryController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
  private let request: LocalGalleryRequest
  private let backdrop = UIView()
  private let container = UIView()
  private let header = UIStackView()
  private let name = UILabel()
  private let count = UILabel()
  private let share = UIButton(type: .system)
  private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
  private var pageScroll: UIScrollView?
  private var pages: [Int: LocalGalleryPageController] = [:]
  private var positions: [Int: Double] = [:]
  private var index: Int
  private var changingPage = false
  private var closing = false
  private var dragging = false
  private var chromeHidden = false
  private lazy var drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))
  var onClose: (() -> Void)?

  init(request: LocalGalleryRequest) { self.request = request; index = request.selection.initialIndex; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
  override var prefersStatusBarHidden: Bool { chromeHidden }
  override func viewDidLoad() {
    super.viewDidLoad()
    overrideUserInterfaceStyle = .dark
    view.backgroundColor = .clear; backdrop.backgroundColor = .black
    [backdrop, container].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    NSLayoutConstraint.activate([backdrop.topAnchor.constraint(equalTo: view.topAnchor), backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor), backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      container.topAnchor.constraint(equalTo: view.topAnchor), container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      container.leadingAnchor.constraint(equalTo: view.leadingAnchor), container.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
    container.clipsToBounds = true; container.backgroundColor = .black
    pager.dataSource = self; pager.delegate = self
    addChild(pager); container.addSubview(pager.view); pager.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([pager.view.topAnchor.constraint(equalTo: container.topAnchor), pager.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      pager.view.leadingAnchor.constraint(equalTo: container.leadingAnchor), pager.view.trailingAnchor.constraint(equalTo: container.trailingAnchor)])
    pager.didMove(toParent: self)
    drag.delegate = self; drag.maximumNumberOfTouches = 1; container.addGestureRecognizer(drag)
    pageScroll = pager.view.subviews.compactMap { $0 as? UIScrollView }.first
    pageScroll?.panGestureRecognizer.require(toFail: drag)
    pageScroll?.delaysContentTouches = false
    makeHeader()
    let selected = page(index)
    pager.setViewControllers([selected], direction: .forward, animated: false)
    selected.setActive(true)
    updateHeader(reset: true)
    view.accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: AppText.text("Previous file"), target: self, selector: #selector(previous)),
      UIAccessibilityCustomAction(name: AppText.text("Next file"), target: self, selector: #selector(next)),
    ]
  }
  private func makeHeader() {
    let close = UIButton(type: .system)
    configure(close, symbol: "xmark", title: AppText.text("Close"))
    configure(share, symbol: "square.and.arrow.up", title: AppText.text("Share"))
    close.addTarget(self, action: #selector(closeViewer), for: .touchUpInside)
    share.addTarget(self, action: #selector(shareFile), for: .touchUpInside)
    name.font = .systemFont(ofSize: 15, weight: .semibold); name.numberOfLines = 2; name.textAlignment = .center; name.textColor = .white
    count.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); count.textColor = .lightGray; count.textAlignment = .center
    let labels = UIStackView(arrangedSubviews: [name, count]); labels.axis = .vertical; labels.spacing = 3
    header.axis = .horizontal; header.alignment = .center; header.spacing = 12
    [close, labels, share].forEach { header.addArrangedSubview($0) }
    header.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(header)
    NSLayoutConstraint.activate([header.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
      header.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      header.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
      share.widthAnchor.constraint(equalToConstant: 44), share.heightAnchor.constraint(equalToConstant: 44)])
    name.layer.shadowColor = UIColor.black.cgColor; name.layer.shadowOpacity = 0.8; name.layer.shadowRadius = 6
  }
  private func configure(_ button: UIButton, symbol: String, title: String) {
    var config = UIButton.Configuration.glass(); config.cornerStyle = .capsule
    config.image = ForumIcons.image(symbol, size: 22); config.baseForegroundColor = .white
    button.configuration = config; button.accessibilityLabel = title
  }
  private func page(_ number: Int) -> LocalGalleryPageController {
    if let existing = pages[number] { return existing }
    let entry = request.selection.files[number]
    let child = LocalGalleryPageController(index: number, file: try? request.catalog.url(for: entry.path), position: positions[number] ?? 0)
    child.zoomChanged = { [weak self] zoomed in
      guard let self, self.index == number else { return }
      self.pageScroll?.isScrollEnabled = !zoomed && !self.dragging
    }
    child.toggleChrome = { [weak self] in
      guard let self, self.index == number else { return }; self.setChromeHidden(!self.chromeHidden)
    }
    child.savePosition = { [weak self] time in self?.positions[number] = time }
    child.scrubbingChanged = { [weak self] scrubbing in
      guard let self, self.index == number else { return }
      self.pageScroll?.isScrollEnabled = !scrubbing && !self.dragging
    }
    child.dismissPan = drag
    pages[number] = child
    return child
  }
  func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
    guard let page = viewController as? LocalGalleryPageController, let number = request.selection.neighbor(of: page.index, offset: -1) else { return nil }
    return self.page(number)
  }
  func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
    guard let page = viewController as? LocalGalleryPageController, let number = request.selection.neighbor(of: page.index, offset: 1) else { return nil }
    return self.page(number)
  }
  func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { changingPage = true }
  func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
    changingPage = false
    guard completed, let current = pager.viewControllers?.first as? LocalGalleryPageController else { return }
    select(current.index)
  }
  private func select(_ number: Int) {
    guard !closing else { return }
    // Stop the previous video before activating its replacement. Preloaded neighbors never play.
    pages[index]?.setActive(false)
    index = number; page(number).setActive(true)
    pages = pages.filter { abs($0.key - number) <= 1 }
    pageScroll?.isScrollEnabled = !page(number).zoomed
    updateHeader(reset: true)
  }
  private func updateHeader(reset: Bool) {
    name.text = request.selection.files[index].name
    count.text = "\(index + 1) / \(request.selection.files.count)"
    count.accessibilityLabel = AppText.format("File %@ of %@", String(index + 1), String(request.selection.files.count))
    share.isEnabled = pages[index]?.file != nil
    if reset { setChromeHidden(pages[index]?.isImage == true, animated: false) }
  }
  private func setChromeHidden(_ hidden: Bool, animated: Bool = true) {
    chromeHidden = hidden
    header.isUserInteractionEnabled = !hidden; header.accessibilityElementsHidden = hidden
    UIView.animate(withDuration: animated && !UIAccessibility.isReduceMotionEnabled ? 0.2 : 0) { self.header.alpha = hidden ? 0 : 1 }
    pages[index]?.setChromeHidden(hidden)
    setNeedsStatusBarAppearanceUpdate()
  }
  @objc private func previous() -> Bool { move(-1) }
  @objc private func next() -> Bool { move(1) }
  private func move(_ offset: Int) -> Bool {
    guard !changingPage, !dragging, !closing, let next = request.selection.neighbor(of: index, offset: offset) else { return false }
    changingPage = true
    pager.setViewControllers([page(next)], direction: offset > 0 ? .forward : .reverse, animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] finished in
      guard let self else { return }; self.changingPage = false
      if finished { self.select(next) }
    }
    return true
  }
  override func accessibilityPerformEscape() -> Bool { closeViewer(); return true }
  @objc private func shareFile() {
    guard !closing, presentedViewController == nil, let file = pages[index]?.file else { return }
    let shareController = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    shareController.popoverPresentationController?.sourceView = share
    present(shareController, animated: true)
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    var touched = touch.view
    while let current = touched {
      if current is UIControl || current === header { return false }
      touched = current.superview
    }
    return pages[index]?.acceptsDrag(at: touch.location(in: pages[index]?.view)) ?? false
  }
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard !changingPage, !closing, presentedViewController == nil, let current = pages[index] else { return false }
    let velocity = drag.velocity(in: view)
    return current.canDismiss && LocalGalleryDrag.canBegin(x: Double(velocity.x), y: Double(velocity.y), zoomed: current.zoomed)
  }
  @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
    let offset = gesture.translation(in: view)
    switch gesture.state {
    case .began:
      dragging = true; pageScroll?.isScrollEnabled = false
    case .changed:
      let distance = max(0, offset.y)
      let progress = min(1, distance / max(view.bounds.height, 1))
      let scale = UIAccessibility.isReduceMotionEnabled ? 1 : 1 - progress * 0.3
      container.transform = CGAffineTransform(translationX: offset.x * 0.15, y: distance).scaledBy(x: scale, y: scale)
      container.layer.cornerRadius = min(28, distance / 4)
      backdrop.alpha = max(0, 1 - progress * 1.8)
    case .ended:
      if LocalGalleryDrag.shouldClose(distance: Double(offset.y), velocity: Double(gesture.velocity(in: view).y), height: Double(view.bounds.height)) {
        closeViewer()
      } else { cancelDrag() }
    case .cancelled, .failed: cancelDrag()
    default: break
    }
  }
  private func cancelDrag() {
    UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.28, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
      self.container.transform = .identity; self.container.layer.cornerRadius = 0; self.backdrop.alpha = 1
    } completion: { _ in
      self.dragging = false; self.pageScroll?.isScrollEnabled = self.pages[self.index]?.zoomed != true
    }
  }
  @objc private func closeViewer() {
    guard !closing else { return }; closing = true
    view.isUserInteractionEnabled = false
    stopPlayback()
    UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.22) {
      if self.dragging && !UIAccessibility.isReduceMotionEnabled { self.container.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height) }
      self.container.alpha = 0; self.backdrop.alpha = 0
    } completion: { _ in self.dismiss(animated: false, completion: self.onClose) }
  }
  func stopPlayback() { for page in pages.values { page.setActive(false) } }
}

private final class LocalGalleryPageController: UIViewController {
  let index: Int
  let file: URL?
  private let position: Double
  private var image: LocalGalleryImageController?
  private var video: LocalGalleryVideoController?
  private var active = false
  var zoomChanged: ((Bool) -> Void)?
  var toggleChrome: (() -> Void)?
  var savePosition: ((Double) -> Void)?
  var scrubbingChanged: ((Bool) -> Void)?
  weak var dismissPan: UIPanGestureRecognizer?
  var zoomed: Bool { image?.zoomed ?? false }
  var isImage: Bool { file.map { LocalMediaKind.kind($0) == .image } ?? false }
  var canDismiss: Bool {
    if image != nil || video != nil { return !zoomed }
    // A document first scrolls back to its top before it can dismiss downward.
    func canDismiss(_ view: UIView) -> Bool {
      if let scroll = view as? UIScrollView,
         scroll.zoomScale > scroll.minimumZoomScale + 0.01 || scroll.contentOffset.y > -scroll.adjustedContentInset.top + 2 { return false }
      return view.subviews.allSatisfy(canDismiss)
    }
    return canDismiss(view)
  }
  init(index: Int, file: URL?, position: Double) { self.index = index; self.file = file; self.position = position; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("Not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    let child: UIViewController
    if let file, isImage {
      let image = LocalGalleryImageController(file: file)
      image.zoomChanged = { [weak self] in self?.zoomChanged?($0) }
      image.toggleChrome = { [weak self] in self?.toggleChrome?() }
      self.image = image; child = image
      image.loadViewIfNeeded()
      if let dismissPan { image.scroll.panGestureRecognizer.require(toFail: dismissPan) }
    } else if let file, [.video, .audio].contains(LocalMediaKind.kind(file)) {
      let video = LocalGalleryVideoController(file: file, position: position)
      video.toggleChrome = { [weak self] in self?.toggleChrome?() }
      video.savePosition = { [weak self] in self?.savePosition?($0) }
      video.scrubbingChanged = { [weak self] in self?.scrubbingChanged?($0) }
      self.video = video; child = video
    } else if let file { child = UIHostingController(rootView: LocalFilePreview(file: file)) }
    else { child = UIHostingController(rootView: ForumUnavailableView(AppText.text("File unavailable"), forumSymbol: "doc").foregroundStyle(.white)) }
    addChild(child); view.addSubview(child.view); child.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([child.view.topAnchor.constraint(equalTo: view.topAnchor), child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
    child.didMove(toParent: self)
  }
  func setActive(_ value: Bool) {
    loadViewIfNeeded(); active = value; image?.setActive(value); video?.setActive(value)
  }
  func setChromeHidden(_ hidden: Bool) { video?.setChromeHidden(hidden) }
  func acceptsDrag(at point: CGPoint) -> Bool { video?.isControlArea(point) != true }
}
