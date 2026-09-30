import SwiftUI
import UIKit

enum AppTypography {
  static let regular = "SourceHanSerifSC-Regular"
  static let bold = "SourceHanSerifSC-Bold"

  @MainActor static func uiFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
    let traits = UITraitCollection(preferredContentSizeCategory: .large)
    let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
    let base = UIFont(name: bold ? self.bold : regular, size: size)
      ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
  }

  @MainActor static func configureNavigation() {
    // Change text attributes only, preserving the system's glass appearances.
    UINavigationBar.appearance().titleTextAttributes = [.font: uiFont(.headline, bold: true)]
    UINavigationBar.appearance().largeTitleTextAttributes = [.font: uiFont(.largeTitle, bold: true)]
    let item = UIBarButtonItem.appearance()
    for state in [UIControl.State.normal, .highlighted, .disabled] {
      item.setTitleTextAttributes([.font: uiFont(.body)], for: state)
    }
    UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = uiFont(.body)
  }

  static func richText(_ run: TextRun) -> AttributedString {
    var value = AttributedString(run.text)
    value.font = Font.forum(.body, weight: run.bold ? .bold : .regular)
    var intents: InlinePresentationIntent = []
    if run.bold { intents.insert(.stronglyEmphasized) }
    if run.italic { intents.insert(.emphasized) }
    value.inlinePresentationIntent = intents
    if let url = run.url { value.link = url; value.foregroundColor = .blue }
    return value
  }
}

extension Font {
  static func forum(_ style: TextStyle, weight: Weight? = nil) -> Font {
    let size: CGFloat
    switch style {
    case .largeTitle: size = 34
    case .title: size = 28
    case .title2: size = 22
    case .title3: size = 20
    case .headline, .body: size = 17
    case .callout: size = 16
    case .subheadline: size = 15
    case .footnote: size = 13
    case .caption: size = 12
    case .caption2: size = 11
    @unknown default: size = 17
    }
    let emphasis = weight.map { $0 == .semibold || $0 == .bold || $0 == .heavy || $0 == .black }
      ?? (style == .headline)
    return .custom(emphasis ? AppTypography.bold : AppTypography.regular, size: size, relativeTo: style)
  }
}
