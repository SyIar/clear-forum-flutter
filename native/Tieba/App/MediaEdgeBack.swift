import SwiftUI
import UIKit

@MainActor
final class MediaEdgeBackGesture: NSObject, UIGestureRecognizerDelegate {
  var action: () -> Void
  private lazy var gesture: UIScreenEdgePanGestureRecognizer = {
    let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handle(_:)))
    gesture.edges = .left
    gesture.maximumNumberOfTouches = 1
    gesture.delegate = self
    return gesture
  }()
  init(action: @escaping () -> Void) { self.action = action }
  func attach(to view: UIView) {
    guard gesture.view !== view else { return }
    detach()
    view.addGestureRecognizer(gesture)
  }
  func detach() { gesture.view?.removeGestureRecognizer(gesture) }
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    let velocity = gesture.velocity(in: gesture.view)
    return velocity.x > 0 && velocity.x > abs(velocity.y)
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    // Reserve only the screen edge; central paging, zooming and scrubbing remain unchanged.
    guard gestureRecognizer === gesture, other is UIPanGestureRecognizer,
          let root = gesture.view, let otherView = other.view else { return false }
    return otherView.isDescendant(of: root)
  }
  @objc private func handle(_ gesture: UIScreenEdgePanGestureRecognizer) {
    guard gesture.state == .ended, let view = gesture.view else { return }
    let distance = gesture.translation(in: view)
    let velocity = gesture.velocity(in: view)
    let threshold = min(120, view.bounds.width * 0.28)
    guard distance.x > abs(distance.y), velocity.x >= 0,
          distance.x >= threshold || (distance.x >= 24 && velocity.x >= 700) else { return }
    action()
  }
}

struct MediaEdgeBack: UIViewControllerRepresentable {
  var action: () -> Void
  func makeUIViewController(context: Context) -> Controller { Controller(action: action) }
  func updateUIViewController(_ controller: Controller, context: Context) { controller.edge.action = action }
  static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.edge.detach() }

  final class Controller: UIViewController {
    let edge: MediaEdgeBackGesture
    init(action: @escaping () -> Void) {
      edge = MediaEdgeBackGesture(action: action)
      super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
    }
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      var root: UIViewController = self
      while let parent = root.parent { root = parent }
      edge.attach(to: root.view)
    }
    override func viewWillDisappear(_ animated: Bool) {
      edge.detach()
      super.viewWillDisappear(animated)
    }
  }
}
