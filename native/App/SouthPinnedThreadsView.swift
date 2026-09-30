import SwiftUI

struct SouthPinnedThreadsCard: View {
  let entries: [ForumEntry]
  let busy: Bool
  let select: (URL) -> Void
  let showAll: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if entries.count > 2 {
          Button(action: showAll) { heading }
            .buttonStyle(.plain).disabled(busy)
            .accessibilityLabel("Show all \(entries.count) pinned threads")
        } else { heading }
      }.background(.blue.opacity(0.045))
      Divider()
      ForEach(entries.prefix(2)) { entry in
        if entry.id != entries.first?.id { Divider().padding(.horizontal, 14) }
        SouthPinnedThreadRow(entry: entry, lineLimit: 1, select: select)
          .padding(.horizontal, 14)
      }
    }
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .contain)
  }

  private var heading: some View {
    HStack(spacing: 8) {
      Image(systemName: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(.blue)
      Text("Pinned").font(.forum(.subheadline, weight: .semibold)).foregroundStyle(.primary)
      Text("\(entries.count)").font(.forum(.caption, weight: .medium)).monospacedDigit()
        .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3)
        .background(.primary.opacity(0.05), in: Capsule())
      Spacer(minLength: 8)
      if entries.count > 2 {
        Text("View all").font(.forum(.caption, weight: .medium)).foregroundStyle(.blue)
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.blue)
      }
    }.frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 14).contentShape(Rectangle())
  }
}

struct SouthPinnedThreadsView: View {
  let entries: [ForumEntry]
  let select: (URL) -> Void
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List(entries) { entry in
        SouthPinnedThreadRow(entry: entry, lineLimit: 2, select: select)
          .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
      }
      .navigationTitle("Pinned threads").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
}

private struct SouthPinnedThreadRow: View {
  let entry: ForumEntry
  let lineLimit: Int
  let select: (URL) -> Void

  var body: some View {
    Button { select(entry.url) } label: {
      HStack(spacing: 12) {
        Text(entry.title).font(.forum(.subheadline)).foregroundStyle(.primary).lineLimit(lineLimit)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
      }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(entry.title)
  }
}
