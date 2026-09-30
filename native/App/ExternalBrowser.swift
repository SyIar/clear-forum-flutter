import SafariServices
import SwiftUI

@MainActor
enum ExternalBrowser {
  static func make(_ requested: URL, useFileBrowser: Bool = true, onClose: (() -> Void)? = nil) -> UIViewController? {
    let url = SimpSitePolicy.browserRedirectDestination(requested) ?? requested
    guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
          !(url.host ?? "").isEmpty, url.user == nil, url.password == nil else { return nil }
    if useFileBrowser, let target = GofilePolicy.pageURL(url) {
      let controller = UIHostingController(rootView: GofileModalRoot(url: target, close: {}))
      controller.rootView = GofileModalRoot(url: target) { [weak controller] in controller?.dismiss(animated: true, completion: onClose) }
      return controller
    }
    if useFileBrowser, HostedFilePolicy.provider(url) != nil {
      let controller = UIHostingController(rootView: HostedModalRoot(url: url, close: {}))
      controller.rootView = HostedModalRoot(url: url) { [weak controller] in controller?.dismiss(animated: true, completion: onClose) }
      return controller
    }
    let controller = SFSafariViewController(url: url)
    controller.dismissButtonStyle = .close
    // Keep Safari's own presentation and interactive dismissal transitions.
    return controller
  }
}

// Present Safari modally from UIKit, rather than embedding it as a child controller.
struct ExternalBrowserPresenter: UIViewControllerRepresentable {
  @Binding var url: URL?
  var useFileBrowser = true

  func makeUIViewController(context: Context) -> ExternalBrowserHost {
    ExternalBrowserHost()
  }
  func updateUIViewController(_ host: ExternalBrowserHost, context: Context) {
    host.onClose = { url = nil }
    host.requestedURL = url
    host.useFileBrowser = useFileBrowser
    host.presentIfReady()
  }
}

final class ExternalBrowserHost: UIViewController, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  var requestedURL: URL?
  var useFileBrowser = true
  var onClose: (() -> Void)?
  private weak var browser: UIViewController?

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    presentIfReady()
  }
  func presentIfReady() {
    guard viewIfLoaded?.window != nil, presentedViewController == nil, browser == nil,
          let url = requestedURL, let controller = ExternalBrowser.make(url, useFileBrowser: useFileBrowser, onClose: { [weak self] in
            self?.requestedURL = nil; self?.browser = nil; self?.onClose?()
          }) else { return }
    (controller as? SFSafariViewController)?.delegate = self
    browser = controller
    present(controller, animated: true)
    controller.presentationController?.delegate = self
  }
  func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    requestedURL = nil
    onClose?()
    controller.dismiss(animated: true) { [weak self] in self?.browser = nil }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    requestedURL = nil
    browser = nil
    onClose?()
  }
}
