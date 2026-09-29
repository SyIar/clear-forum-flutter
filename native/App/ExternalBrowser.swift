import SafariServices
import SwiftUI

enum ExternalBrowser {
  static func make(_ url: URL) -> SFSafariViewController? {
    guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
          !(url.host ?? "").isEmpty, url.user == nil, url.password == nil else { return nil }
    let controller = SFSafariViewController(url: url)
    controller.dismissButtonStyle = .close
    // Keep Safari's own presentation and interactive dismissal transitions.
    return controller
  }
}

// Present Safari modally from UIKit, rather than embedding it as a child controller.
struct ExternalBrowserPresenter: UIViewControllerRepresentable {
  @Binding var url: URL?

  func makeUIViewController(context: Context) -> ExternalBrowserHost {
    ExternalBrowserHost()
  }
  func updateUIViewController(_ host: ExternalBrowserHost, context: Context) {
    host.onClose = { url = nil }
    host.requestedURL = url
    host.presentIfReady()
  }
}

final class ExternalBrowserHost: UIViewController, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  var requestedURL: URL?
  var onClose: (() -> Void)?
  private weak var browser: SFSafariViewController?

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    presentIfReady()
  }
  func presentIfReady() {
    guard viewIfLoaded?.window != nil, presentedViewController == nil, browser == nil,
          let url = requestedURL, let controller = ExternalBrowser.make(url) else { return }
    controller.delegate = self
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
