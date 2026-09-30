import SwiftUI
import UIKit
import CoreText

enum AppTypography {
  @MainActor static func uiFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
    let font = UIFont.preferredFont(forTextStyle: style)
    guard bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
    return UIFont(descriptor: descriptor, size: 0)
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
  private let contentFont: Bool
  private let weight: Font.Weight
  init(_ style: Font.TextStyle, weight: Font.Weight?, baseSize: CGFloat?, contentFont: Bool) {
    _size = ScaledMetric(wrappedValue: baseSize ?? AppTypography.size(style), relativeTo: style)
    bold = weight.map { $0 == .semibold || $0 == .bold || $0 == .heavy || $0 == .black } ?? (style == .headline)
    self.weight = weight ?? (style == .headline ? .semibold : .regular)
    self.contentFont = contentFont
  }
  func body(content: Content) -> some View {
    content.font(contentFont ? Font(MixedScriptFont.font(size: size * settings.fontScale, bold: bold)) :
      .system(size: size * settings.fontScale, weight: weight))
  }
}

extension View {
  func tiebaFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, baseSize: CGFloat? = nil) -> some View {
    modifier(TiebaFont(style, weight: weight, baseSize: baseSize, contentFont: true))
  }
  func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, baseSize: CGFloat? = nil) -> some View {
    modifier(TiebaFont(style, weight: weight, baseSize: baseSize, contentFont: false))
  }
}
