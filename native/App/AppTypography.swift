import SwiftUI
import UIKit
import CoreText

enum AppTypography {
  @MainActor static func uiFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
    let font = UIFont.preferredFont(forTextStyle: style)
    guard bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
    return UIFont(descriptor: descriptor, size: 0)
  }

  @MainActor static func contentUIFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
    let traits = UITraitCollection(preferredContentSizeCategory: .large)
    let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
    let base = MixedScriptFont.font(size: size, bold: bold) as UIFont
    return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
  }

  static func richText(_ run: TextRun, size: CGFloat) -> AttributedString {
    var value = AttributedString(run.text)
    value.font = Font(MixedScriptFont.font(size: size, bold: run.bold))
    var intents: InlinePresentationIntent = []
    if run.bold { intents.insert(.stronglyEmphasized) }
    if run.italic { intents.insert(.emphasized) }
    value.inlinePresentationIntent = intents
    if let url = run.url { value.link = url; value.foregroundColor = .blue }
    return value
  }
}

extension AppTypography {
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

private struct ForumFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let bold: Bool
  init(_ style: Font.TextStyle, weight: Font.Weight?) {
    _size = ScaledMetric(wrappedValue: AppTypography.size(style), relativeTo: style)
    bold = weight.map { $0 == .semibold || $0 == .bold || $0 == .heavy || $0 == .black } ?? (style == .headline)
  }
  func body(content: Content) -> some View {
    content.font(Font(MixedScriptFont.font(size: size, bold: bold)))
  }
}

extension View {
  func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
    font(weight.map { Font.system(style).weight($0) } ?? .system(style))
  }

  func forumFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
    modifier(ForumFont(style, weight: weight))
  }
}
