import SwiftUI
import UIKit
import CoreText

enum AppTypography {
  @MainActor static func uiFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
    let traits = UITraitCollection(preferredContentSizeCategory: .large)
    let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
    let base = MixedScriptFont.font(size: size, bold: bold) as UIFont
    return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
  }

  @MainActor static func configureNavigation() {
    // Keep the system glass appearances; only text attributes change.
    UINavigationBar.appearance().titleTextAttributes = [.font: uiFont(.headline, bold: true)]
    UINavigationBar.appearance().largeTitleTextAttributes = [.font: uiFont(.largeTitle, bold: true)]
    for state in [UIControl.State.normal, .highlighted, .disabled] {
      UIBarButtonItem.appearance().setTitleTextAttributes([.font: uiFont(.body)], for: state)
    }
    for state in [UIControl.State.normal, .selected, .disabled] {
      UITabBarItem.appearance().setTitleTextAttributes([.font: uiFont(.caption2)], for: state)
      UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont(.subheadline, bold: state == .selected)], for: state)
    }
    UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = uiFont(.body)
  }

  static func size(_ style: Font.TextStyle) -> CGFloat {
    switch style {
    case .largeTitle: return 34
    case .title: return 28
    case .title2: return 22
    case .title3: return 20
    case .headline, .body: return 17
    case .callout: return 16
    case .subheadline: return 15
    case .footnote: return 13
    case .caption: return 12
    case .caption2: return 11
    @unknown default: return 17
    }
  }
}

private struct TiebaFont: ViewModifier {
  @EnvironmentObject private var settings: Preferences
  @ScaledMetric private var size: CGFloat
  private let bold: Bool
  init(_ style: Font.TextStyle, weight: Font.Weight?, baseSize: CGFloat?) {
    _size = ScaledMetric(wrappedValue: baseSize ?? AppTypography.size(style), relativeTo: style)
    bold = weight.map { $0 == .semibold || $0 == .bold || $0 == .heavy || $0 == .black } ?? (style == .headline)
  }
  func body(content: Content) -> some View {
    content.font(Font(MixedScriptFont.font(size: size * settings.fontScale, bold: bold)))
  }
}

extension View {
  func tiebaFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, baseSize: CGFloat? = nil) -> some View {
    modifier(TiebaFont(style, weight: weight, baseSize: baseSize))
  }
}
