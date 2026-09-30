import SwiftUI

struct InfoButton: View {
  let title: String
  let message: String
  @State private var showingInfo = false

  var body: some View {
    Button { showingInfo = true } label: {
      Image(systemName: "info.circle").font(.body)
        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }.buttonStyle(.borderless)
      .accessibilityLabel(AppText.format("%@ information", String(describing: title)))
      .popover(isPresented: $showingInfo) {
        ViewThatFits(in: .vertical) {
          information
          ScrollView { information }
        }.frame(idealWidth: 280, maxWidth: 320, maxHeight: 400)
          .presentationCompactAdaptation(.popover)
      }
  }
  private var information: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.forum(.headline))
      Text(message).font(.forum(.subheadline)).foregroundStyle(.secondary)
    }.textCase(nil).padding(20).fixedSize(horizontal: false, vertical: true)
  }
}
