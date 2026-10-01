import ForumUI
import SwiftUI

struct SouthBlockedAuthorsView: View {
  @ObservedObject var library: LibraryStore
  @Environment(\.dismiss) private var nativeDismiss
  @Environment(\.forumDismiss) private var forumDismiss
  private func dismiss() { if forumDismiss.available { forumDismiss() } else { nativeDismiss() } }
  var body: some View {
    NavigationStack {
      List {
        if library.document.blockedAuthors.isEmpty {
          ForumUnavailableView(AppText.text("No blocked authors"), forumSymbol: "person.crop.circle.badge.checkmark")
        }
        ForEach(library.document.blockedAuthors.keys.sorted(), id: \.self) { id in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(library.document.blockedAuthors[id] ?? AppText.text("Member")).forumFont(.headline)
              Text(AppText.format("UID %@", String(describing: id))).appFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(AppText.text("Unblock")) { library.change { $0.unblockAuthor(id) } }.buttonStyle(.bordered)
          }
        }
      }.navigationTitle(AppText.text("Blocked authors")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppText.text("Close")) { dismiss() } } }
        .forumAlert(AppText.text("Reading library"), isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } }), actions: { [
          ForumDialogAction(AppText.text("OK"), role: .cancel) { library.error = nil }
        ] }, message: { library.error ?? "" })
    }
  }
}
