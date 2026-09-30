import SwiftUI

struct ReaderQuickActions: View {
  let canJump: Bool
  let busy: Bool
  let top: () -> Void
  let bottom: () -> Void
  let refresh: () -> Void
  var body: some View {
      VStack(spacing: 0) {
        action(AppText.text("Top of page"), symbol: "arrow.up.to.line", disabled: !canJump || busy, perform: top)
        Divider().frame(width: 26)
        action(AppText.text("Bottom of page"), symbol: "arrow.down.to.line", disabled: !canJump || busy, perform: bottom)
        Divider().frame(width: 26)
        action(AppText.text("Refresh"), symbol: "arrow.clockwise", disabled: busy, perform: refresh)
      }.padding(4).glassEffect(.regular.interactive(), in: .capsule)
  }
  private func action(_ title: String, symbol: String, disabled: Bool, perform: @escaping () -> Void) -> some View {
    Button(action: perform) {
      Image(systemName: symbol).font(.system(size: 20, weight: .medium))
        .frame(width: 50, height: 50).contentShape(Circle())
    }.buttonStyle(.plain).foregroundStyle(.blue).disabled(disabled)
      .opacity(disabled ? 0.4 : 1)
      .accessibilityLabel(title)
  }
}
