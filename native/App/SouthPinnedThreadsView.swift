import SwiftUI

struct SouthPinnedThreadsView: View {
  let entries: [ForumEntry]
  let select: (URL) -> Void
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List(entries) { entry in
        Button { select(entry.url) } label: {
          HStack(spacing: 10) {
            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.blue)
            Text(entry.title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
          }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
      }
      .navigationTitle("Pinned threads").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
}
