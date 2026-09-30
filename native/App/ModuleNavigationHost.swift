import SwiftUI
import UIKit

// Module navigation owns only the selector-to-module transition. Each module
// keeps its own tab navigation, and decides when its root can be popped.
struct ModuleNavigationHost<Root: View, Module: View>: UIViewControllerRepresentable {
  @Binding var isPresented: Bool
  var canReturn: () -> Bool
  var root: Root
  var module: Module

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> UINavigationController {
    let coordinator = context.coordinator
    let navigation = UINavigationController(rootViewController: coordinator.root)
    navigation.setNavigationBarHidden(true, animated: false)
    navigation.delegate = coordinator
    navigation.loadViewIfNeeded()
    navigation.interactivePopGestureRecognizer?.delegate = coordinator
    // Leave content-area gestures to the selected module's navigation stack.
    navigation.interactiveContentPopGestureRecognizer?.isEnabled = false
    coordinator.navigation = navigation
    return navigation
  }
  func updateUIViewController(_ navigation: UINavigationController, context: Context) {
    let coordinator = context.coordinator
    coordinator.owner = self
    coordinator.root.rootView = root
    coordinator.module?.rootView = module
    coordinator.synchronize()
  }

  @MainActor final class Coordinator: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    var owner: ModuleNavigationHost
    let root: UIHostingController<Root>
    var module: UIHostingController<Module>?
    weak var navigation: UINavigationController?
    private var transitioning = false

    init(_ owner: ModuleNavigationHost) {
      self.owner = owner
      root = UIHostingController(rootView: owner.root)
      super.init()
    }
    func synchronize() {
      guard let navigation, !transitioning, navigation.transitionCoordinator == nil else { return }
      if owner.isPresented, module == nil {
        let controller = UIHostingController(rootView: owner.module)
        module = controller
        navigation.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
      } else if !owner.isPresented, module != nil {
        navigation.popToRootViewController(animated: !UIAccessibility.isReduceMotionEnabled)
      }
    }
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
      transitioning = true
      navigationController.setNavigationBarHidden(true, animated: false)
    }
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
      transitioning = false
      navigationController.interactivePopGestureRecognizer?.isEnabled = navigationController.viewControllers.count > 1
      navigationController.interactiveContentPopGestureRecognizer?.isEnabled = false
      if viewController === root, let module, !navigationController.viewControllers.contains(where: { $0 === module }) {
        self.module = nil
        // Called only after a completed pop, never while an edge swipe is cancelled.
        if owner.isPresented { owner.isPresented = false }
      }
      DispatchQueue.main.async { [weak self] in self?.synchronize() }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let navigation, !transitioning, navigation.transitionCoordinator == nil,
            navigation.viewControllers.count == 2, navigation.topViewController === module,
            owner.isPresented, owner.canReturn(),
            let module, !hasPushedNavigation(module), !hasPresentedController(navigation) else { return false }
      return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
      guard gestureRecognizer === navigation?.interactivePopGestureRecognizer,
            other is UIPanGestureRecognizer, let view = other.view,
            let module, view.isDescendant(of: module.view), owner.canReturn() else { return false }
      return true
    }
    private func hasPresentedController(_ controller: UIViewController) -> Bool {
      if controller.presentedViewController != nil { return true }
      return controller.children.contains(where: hasPresentedController)
    }
    private func hasPushedNavigation(_ controller: UIViewController) -> Bool {
      // Item-based destinations are not necessarily present in a bound SwiftUI
      // path. Inspect the selected UIKit stack as a second guard against exiting
      // the module while its own push/pop transition is still in progress.
      if let navigation = controller as? UINavigationController {
        return navigation.viewControllers.count > 1 || navigation.transitionCoordinator != nil ||
          navigation.topViewController.map(hasPushedNavigation) == true
      }
      if let tabs = controller as? UITabBarController {
        return tabs.selectedViewController.map(hasPushedNavigation) == true
      }
      return controller.children.filter { $0.viewIfLoaded?.window != nil && $0.viewIfLoaded?.isHidden == false }
        .contains(where: hasPushedNavigation)
    }
  }
}
