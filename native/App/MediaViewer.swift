import SwiftUI
import UIKit

enum MediaViewerItem: Identifiable {
  case image(UUID, UIImage)
  case video(URL, Bool, URL)
  var id: String {
    switch self {
    case .image(let id, _): return id.uuidString
    case .video(let url, let direct, let referer): return "\(referer.host ?? ""):\(direct):\(url.absoluteString)"
    }
  }
}

// UIKit owns the entire presentation, including cancellation and completion.
// Keep the reader mounted and change its binding only after dismissal.
struct MediaViewerPresenter: UIViewControllerRepresentable {
  @Binding var item: MediaViewerItem?
  func makeUIViewController(context: Context) -> Controller { Controller() }
  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.pending = item
    controller.didClose = { id in if item?.id == id { item = nil } }
    controller.showIfReady()
  }
  static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
    controller.didClose = nil
    let active = controller.active
    active?.dismiss(animated: false)
    active?.finishDismissal()
  }

  final class Controller: UIViewController {
    var pending: MediaViewerItem?
    var active: MediaNavigationController?
    var didClose: ((String) -> Void)?
    override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); showIfReady() }
    func showIfReady() {
      guard let item = pending, active == nil, viewIfLoaded?.window != nil else { return }
      let controller = MediaNavigationController(item: item) { [weak self] in
        self?.active = nil
        self?.pending = nil
        self?.didClose?(item.id)
      }
      active = controller
      present(controller, animated: true)
    }
  }
}

final class MediaNavigationController: UINavigationController {
  private let slide = MediaSlideTransition()
  private var onClose: (() -> Void)?
  private var player: MediaPlayerController?
  convenience init(item: MediaViewerItem, completion: @escaping () -> Void) {
    let root: UIViewController
    switch item {
    case .image(_, let image): root = ImageViewerController(image: image)
    case .video(let url, let direct, let referer): root = MediaPlayerController(url: url, direct: direct, referer: referer, completion: {})
    }
    self.init(rootViewController: root)
    if case .image = item { overrideUserInterfaceStyle = .dark }
    onClose = completion
    player = root as? MediaPlayerController
    player?.requestClose = { [weak self] in self?.closeViewer() }
    (root as? ImageViewerController)?.requestClose = { [weak self] in self?.closeViewer() }
    modalPresentationStyle = .fullScreen
    transitioningDelegate = slide
    slide.owner = self
  }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
  override func viewDidLoad() { super.viewDidLoad(); slide.attach(to: view) }
  func closeViewer() {
    guard transitionCoordinator == nil, presentedViewController == nil else { return }
    dismiss(animated: true)
  }
  func finishDismissal() {
    player?.finishPlayback()
    let completion = onClose
    onClose = nil
    completion?()
  }
}

@MainActor
private final class MediaSlideTransition: NSObject, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
  weak var owner: MediaNavigationController?
  private var interaction: UIPercentDrivenInteractiveTransition?
  private lazy var edge: UIScreenEdgePanGestureRecognizer = {
    let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(pan(_:)))
    gesture.edges = .left
    gesture.maximumNumberOfTouches = 1
    gesture.delegate = self
    return gesture
  }()
  func attach(to view: UIView) { view.addGestureRecognizer(edge) }
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    let velocity = edge.velocity(in: edge.view)
    return owner?.transitionCoordinator == nil && owner?.presentedViewController == nil &&
      velocity.x > 0 && velocity.x > abs(velocity.y)
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === edge, other is UIPanGestureRecognizer,
          let root = edge.view, let child = other.view else { return false }
    return child.isDescendant(of: root)
  }
  @objc private func pan(_ gesture: UIScreenEdgePanGestureRecognizer) {
    guard let view = gesture.view else { return }
    let distance = gesture.translation(in: view).x
    let progress = max(0, min(1, distance / max(1, view.bounds.width)))
    switch gesture.state {
    case .began:
      let driver = UIPercentDrivenInteractiveTransition()
      driver.completionCurve = .easeOut
      interaction = driver
      owner?.dismiss(animated: true)
    case .changed: interaction?.update(progress)
    case .ended:
      let velocity = gesture.velocity(in: view).x
      let finish = velocity >= 0 && (progress >= 0.33 || (distance >= 24 && velocity >= 700))
      if finish { interaction?.finish() } else { interaction?.cancel() }
      interaction = nil
    case .cancelled, .failed: interaction?.cancel(); interaction = nil
    default: break
    }
  }
  func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    MediaSlideAnimator(presenting: true)
  }
  func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    MediaSlideAnimator(presenting: false) { [weak owner] in owner?.finishDismissal() }
  }
  func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? { interaction }
}

@MainActor
private final class MediaSlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
  private let presenting: Bool
  private let completion: (() -> Void)?
  init(presenting: Bool, completion: (() -> Void)? = nil) { self.presenting = presenting; self.completion = completion }
  func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
    UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.36
  }
  func animateTransition(using context: UIViewControllerContextTransitioning) {
    guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
          let toController = context.viewController(forKey: .to) else { context.completeTransition(false); return }
    let container = context.containerView
    to.frame = context.finalFrame(for: toController)
    let width = container.bounds.width
    let parallax: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0 : width * 0.25
    if presenting {
      container.addSubview(to)
      to.transform = CGAffineTransform(translationX: width, y: 0)
    } else {
      container.insertSubview(to, belowSubview: from)
      to.transform = CGAffineTransform(translationX: -parallax, y: 0)
    }
    let shade = UIView(frame: container.bounds)
    shade.backgroundColor = .black
    shade.isUserInteractionEnabled = false
    shade.alpha = presenting ? 0 : 0.16
    container.insertSubview(shade, belowSubview: presenting ? to : from)
    let options: UIView.AnimationOptions = context.isInteractive ? [.curveLinear] : [.curveEaseOut]
    UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: options) {
      from.transform = CGAffineTransform(translationX: self.presenting ? -parallax : width, y: 0)
      to.transform = .identity
      shade.alpha = self.presenting ? 0.16 : 0
    } completion: { _ in
      let completed = !context.transitionWasCancelled
      from.transform = .identity
      to.transform = .identity
      shade.removeFromSuperview()
      context.completeTransition(completed)
      if completed { self.completion?() }
    }
  }
}

private final class ImageViewerController: UIHostingController<AnyView> {
  var requestClose: (() -> Void)?
  private let image: UIImage
  init(image: UIImage) {
    self.image = image
    super.init(rootView: AnyView(ZoomImage(image: image).background(.black).ignoresSafeArea(edges: .bottom)))
    overrideUserInterfaceStyle = .dark
  }
  @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    let back = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(close))
    back.accessibilityLabel = "Back to thread"
    navigationItem.leftBarButtonItem = back
    let share = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareImage))
    share.accessibilityLabel = "Share image"
    navigationItem.rightBarButtonItem = share
  }
  @objc private func close() { requestClose?() }
  @objc private func shareImage() {
    let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    controller.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
    present(controller, animated: true)
  }
}
