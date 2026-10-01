import SwiftUI
import UIKit
import ChunUI

public struct ForumDialogAction {
  let title: String
  let role: ButtonRole?
  let action: () -> Void
  public init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void = {}) {
    self.title = title; self.role = role; self.action = action
  }
}

@MainActor public enum ForumDialogs {
  public static func notice(title: String, message: String, close: String) {
    AppHelper.shared.showBottomAlert(title: title, message: message,
      actions: [CCAlertAction(title: close, role: .secondary)])
  }
}

public struct ForumPresentationHost: UIViewRepresentable {
  public init() {}
  public func makeUIView(context: Context) -> UIView { AlertAnchor() }
  public func updateUIView(_ uiView: UIView, context: Context) {}
  private final class AlertAnchor: UIView {
    override func didMoveToWindow() {
      super.didMoveToWindow()
      if let scene = window?.windowScene { CCAlertWindow.shared.attach(to: scene) }
    }
  }
}

private struct ForumAlertModifier: ViewModifier {
  let title: String
  @Binding var presented: Bool
  let confirmation: Bool
  let actions: () -> [ForumDialogAction]
  let message: () -> String
  func body(content: Content) -> some View {
    content.onChange(of: presented, initial: true) { _, show in
      guard show else { return }
      let text = message()
      var choices = actions()
      if confirmation && !choices.contains(where: { $0.role == .cancel }) {
        choices.append(ForumDialogAction(CCStrings.current.cancel, role: .cancel))
      }
      let mapped = choices.map { choice in
        // Upstream's default alert uses an adaptive foreground accent but fixed
        // white button text. Outline actions remain readable in dark mode.
        CCAlertAction(title: choice.title,
          role: choice.role == .destructive ? .destructive : .secondary,
          handler: choice.action)
      }
      // CCAlertCenter owns dismissal (including backdrop taps). Consume the
      // source trigger once so dismissing its card can never leave a stale flag.
      presented = false
      AppHelper.shared.showBottomAlert(title: title, message: text.isEmpty ? nil : text, actions: mapped)
    }
  }
}

public extension View {
  func forumAlert(_ title: String, isPresented: Binding<Bool>,
                 actions: @escaping () -> [ForumDialogAction],
                 message: @escaping () -> String = { "" }) -> some View {
    modifier(ForumAlertModifier(title: title, presented: isPresented, confirmation: false, actions: actions, message: message))
  }
  func forumConfirmation(_ title: String, isPresented: Binding<Bool>,
                         actions: @escaping () -> [ForumDialogAction]) -> some View {
    modifier(ForumAlertModifier(title: title, presented: isPresented, confirmation: true, actions: actions, message: { "" }))
  }
  func forumPrompt(_ title: String, isPresented: Binding<Bool>, text: Binding<String>,
                   placeholder: String, numeric: Bool = false, submit: String,
                   action: @escaping () -> Void) -> some View {
    forumSheet(isPresented: isPresented) {
      NavigationStack {
        Form {
          TextField(placeholder, text: text).keyboardType(numeric ? .numberPad : .default)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          Button(submit) { action(); isPresented.wrappedValue = false }
            .buttonStyle(ForumActionButtonStyle())
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(CCStrings.current.cancel) { isPresented.wrappedValue = false }
          } }
      }
    }
  }
}

// A binding-backed facade over ChunUI's native sheet. The existing sheet content
// supplies its own data environment explicitly; it never switches forum sessions.
public extension View {
  func forumSheet<Sheet: View>(isPresented: Binding<Bool>, half: Bool = true,
                             onDismiss: (() -> Void)? = nil,
                             @ViewBuilder content: @escaping () -> Sheet) -> some View {
    modifier(ForumSheetModifier(presented: isPresented, half: half, onDismiss: onDismiss, sheet: content))
  }
  func forumSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>,
                 onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
    forumSheet(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
               onDismiss: onDismiss) {
      if let value = item.wrappedValue { content(value) }
    }
  }
}

public struct ForumDismissAction {
  let close: (() -> Void)?
  public func callAsFunction() { close?() }
  public var available: Bool { close != nil }
}
private struct ForumDismissKey: EnvironmentKey {
  static let defaultValue = ForumDismissAction(close: nil)
}
public extension EnvironmentValues {
  var forumDismiss: ForumDismissAction {
    get { self[ForumDismissKey.self] }
    set { self[ForumDismissKey.self] = newValue }
  }
}

private struct ForumSheetModifier<Sheet: View>: ViewModifier {
  @Binding var presented: Bool
  let half: Bool
  let onDismiss: (() -> Void)?
  let sheet: () -> Sheet
  @StateObject private var owner = ForumSheetOwner()
  func body(content: Content) -> some View {
    content.onChange(of: presented, initial: true) { _, show in
      if show {
        guard !owner.active else { return }
        owner.active = true
        let close = ForumDismissAction { presented = false; owner.dismiss() }
        var config = half ? CCSheetConfig.half : .sheet
        config.cornerRadius = 34
        config.frostedGlass = true
        config.haptic = !UIAccessibility.isReduceMotionEnabled
        AppHelper.shared.presentSheet(config, onDismiss: {
          guard owner.active else { return }
          owner.active = false; owner.host = nil; presented = false; onDismiss?()
        }, onPresent: { host in
          owner.host = host
          if !presented { owner.dismiss() }
        }) {
          sheet().scrollContentBackground(.hidden).environment(\.forumDismiss, close)
        }
      } else { owner.dismiss() }
    }.background {
      ForumSheetLifetime(owner: owner, removed: { presented = false }).frame(width: 0, height: 0)
    }
  }
}

// A full-height/landscape sheet may make its presenter disappear without
// removing it. Only actual removal should cancel a queued presentation.
private struct ForumSheetLifetime: UIViewRepresentable {
  let owner: ForumSheetOwner
  let removed: () -> Void
  final class Coordinator {
    let owner: ForumSheetOwner
    var removed: () -> Void
    init(owner: ForumSheetOwner, removed: @escaping () -> Void) { self.owner = owner; self.removed = removed }
  }
  func makeCoordinator() -> Coordinator { Coordinator(owner: owner, removed: removed) }
  func makeUIView(context: Context) -> UIView { UIView() }
  func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.removed = removed }
  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    DispatchQueue.main.async { coordinator.removed(); coordinator.owner.dismiss() }
  }
}

@MainActor private final class ForumSheetOwner: ObservableObject {
  var active = false
  weak var host: UIViewController?
  func dismiss() {
    guard let host, !host.isBeingDismissed else { return }
    host.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
  }
}
