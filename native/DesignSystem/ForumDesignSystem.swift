import SwiftUI
import ChunUI

// Keep the package boundary here: content typography and navigation remain
// owned by Forum Lite, while ChunUI supplies surfaces and design tokens.
@MainActor
public enum ForumDesignSystem {
  public static let spacing = CCSpacing.default
  public static let radius = CCRadius(card: 20)
  public static var primary: Color { Color.cc.primary }
  public static var secondaryText: Color { Color.cc.mutedForeground }
  public static var surface: Color { Color.cc.muted }
  private static var configured = false

  public static func configure(localize: (String) -> String) {
    guard !configured else { return }
    configured = true
    var colors = CCColors.default
    colors.primary = Color(uiColor: .systemBlue)
    colors.primaryForeground = .white
    colors.ring = colors.primary
    colors.background = Color(uiColor: .systemGroupedBackground)
    colors.foreground = Color(uiColor: .label)
    colors.card = Color(uiColor: .secondarySystemGroupedBackground)
    colors.cardForeground = colors.foreground
    colors.panel = Color(uiColor: .tertiarySystemGroupedBackground)
    colors.muted = Color(uiColor: .tertiarySystemFill)
    colors.mutedForeground = Color(uiColor: .secondaryLabel)
    colors.secondary = colors.muted
    colors.secondaryForeground = colors.foreground
    colors.accent = Color(uiColor: .quaternarySystemFill)
    colors.accentForeground = colors.foreground
    colors.border = Color(uiColor: .separator)
    colors.input = colors.muted
    colors.destructive = Color(uiColor: .systemRed)
    colors.success = Color(uiColor: .systemGreen)
    colors.warning = Color(uiColor: .systemOrange)
    colors.info = colors.primary
    colors.chart.color1 = colors.primary
    var strings = CCStrings()
    strings.cancel = localize("Cancel")
    strings.confirm = localize("OK")
    strings.done = localize("Done")
    strings.save = localize("Save")
    strings.retry = localize("Retry")
    strings.loading = localize("Loading…")
    strings.appName = "Forum Lite"
    ChunUI.configure(colors: colors, strings: strings)
  }
}

private struct ForumCardSurface: ViewModifier {
  var radius: CGFloat
  @Environment(\.colorSchemeContrast) private var contrast
  func body(content: Content) -> some View {
    CCAppleCard(radius: radius, shadowLevel: 1, border: contrast == .increased) { content }
  }
}

private struct ForumTagSurface: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, ForumDesignSystem.spacing.sm)
      .padding(.vertical, ForumDesignSystem.spacing.xs)
      .foregroundStyle(Color.cc.cardForeground)
      .background(Color.cc.muted, in: RoundedRectangle(cornerRadius: ForumDesignSystem.radius.md, style: .continuous))
  }
}

// Use the public ChunUI surface on a real SwiftUI Button. This preserves our
// Dynamic Type, accessibility semantics, disabled state and task ownership.
public struct ForumActionButtonStyle: ButtonStyle {
  public var prominent: Bool
  public init(prominent: Bool = true) { self.prominent = prominent }
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 44

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(.subheadline, design: .default, weight: .semibold))
      .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, ForumDesignSystem.spacing.base)
      .padding(.vertical, ForumDesignSystem.spacing.sm)
      .frame(minHeight: height)
      .foregroundStyle(prominent ? Color.cc.primaryForeground : Color.cc.foreground)
      .ccNeoChrome(prominent ? .primary : .secondary, height: height, disabled: !enabled)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

public extension View {
  func forumCardSurface(radius: CGFloat? = nil) -> some View {
    modifier(ForumCardSurface(radius: radius ?? ForumDesignSystem.radius.card))
  }
  func forumTagSurface() -> some View { modifier(ForumTagSurface()) }
  func forumModuleGlass() -> some View {
    ccGlassEffect(.roundedRectangle(28))
  }
}
