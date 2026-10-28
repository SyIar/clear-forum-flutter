import SwiftUI
import UIKit

// These helpers only adapt existing action models to the system presenters.
public struct ForumDialogAction {
  let title: String
  let role: ButtonRole?
  let action: () -> Void
  public init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void = {}) {
    self.title = title; self.role = role; self.action = action
  }
}

@MainActor public enum ForumDialogs {
  public static func notice(from presenter: UIViewController, title: String, message: String, close: String) {
    guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { return }
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: close, style: .default))
    presenter.present(alert, animated: true)
  }
}

public extension View {
  func forumAlert(_ title: String, isPresented: Binding<Bool>,
                 actions: @escaping () -> [ForumDialogAction],
                 message: @escaping () -> String = { "" }) -> some View {
    let choices = actions()
    return alert(title, isPresented: isPresented) {
      ForEach(choices.indices, id: \.self) { index in
        let choice = choices[index]
        Button(choice.title, role: choice.role, action: choice.action)
      }
    } message: { Text(message()) }
  }

  func forumConfirmation(_ title: String, isPresented: Binding<Bool>,
                         actions: @escaping () -> [ForumDialogAction]) -> some View {
    let choices = actions()
    return confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
      ForEach(choices.indices, id: \.self) { index in
        let choice = choices[index]
        Button(choice.title, role: choice.role, action: choice.action)
      }
    }
  }

  func forumPrompt(_ title: String, isPresented: Binding<Bool>, text: Binding<String>,
                   placeholder: String, numeric: Bool = false, submit: String, cancel: String,
                   action: @escaping () -> Void) -> some View {
    alert(title, isPresented: isPresented) {
      TextField(placeholder, text: text)
        .keyboardType(numeric ? .numberPad : .default)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
      Button(cancel, role: .cancel) {}
      Button(submit, action: action)
    }
  }
}
