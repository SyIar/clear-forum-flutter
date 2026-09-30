import SwiftUI

struct ReaderQuickActions: View {
  let canJump: Bool
  let busy: Bool
  let top: () -> Void
  let bottom: () -> Void
  let refresh: () -> Void
  var body: some View {
    GlassEffectContainer(spacing: 12) {
      VStack(spacing: 10) {
        action(AppText.text("Top of page"), symbol: "arrow.up.to.line", disabled: !canJump || busy, perform: top)
        action(AppText.text("Bottom of page"), symbol: "arrow.down.to.line", disabled: !canJump || busy, perform: bottom)
        action(AppText.text("Refresh"), symbol: "arrow.clockwise", disabled: busy, perform: refresh)
      }
    }
  }
  private func action(_ title: String, symbol: String, disabled: Bool, perform: @escaping () -> Void) -> some View {
    Button(action: perform) {
      Image(systemName: symbol).font(.system(size: 20, weight: .medium))
        .frame(width: 50, height: 50).contentShape(Circle())
    }.buttonStyle(.plain).foregroundStyle(.blue).disabled(disabled)
      .opacity(disabled ? 0.4 : 1)
      .glassEffect(.regular.interactive(), in: .circle)
      .accessibilityLabel(title)
  }
}
