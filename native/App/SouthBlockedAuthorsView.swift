import SwiftUI

struct SouthBlockedAuthorsView: View {
  @ObservedObject var library: LibraryStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        if library.document.blockedAuthors.isEmpty {
          ContentUnavailableView("No blocked authors", systemImage: "person.crop.circle.badge.checkmark")
        }
        ForEach(library.document.blockedAuthors.keys.sorted(), id: \.self) { id in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(library.document.blockedAuthors[id] ?? "Member").font(.forum(.headline))
              Text("UID \(id)").font(.forum(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Unblock") { library.change { $0.unblockAuthor(id) } }.buttonStyle(.bordered)
          }
        }
      }.navigationTitle("Blocked authors").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        .alert("Reading library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
          Button("OK", role: .cancel) { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
  }
}
