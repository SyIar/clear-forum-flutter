import ForumUI
import SwiftUI

struct BookhouseOfflineSearchView: View {
  @ObservedObject var library: LibraryStore
  let select: (BookhouseOfflineMatch) -> Void
  @ObservedObject private var offline = BookhouseOfflineStore.shared
  @State private var query = ""
  @State private var result = BookhouseOfflineSearch.Result()
  @State private var searching = false
  @State private var error: String?
  private var keyword: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  var body: some View {
    List {
      if keyword.isEmpty {
        Text(AppText.text("Search the cached text of all followed books. Chapters you read are cached automatically."))
          .appFont(.subheadline).foregroundStyle(.secondary)
      } else if searching {
        HStack { ProgressView(); Text(AppText.text("Searching cached chapters")) }.appFont(.subheadline)
      } else if let error {
        Text(error).appFont(.subheadline).foregroundStyle(.secondary)
      } else {
        if result.matches.isEmpty { Text(AppText.text("No matches in cached chapters")).appFont(.subheadline).foregroundStyle(.secondary) }
        if result.truncated {
          Text(AppText.format("Showing the first %@ matches. Narrow your keywords for more precise results.", String(result.matches.count)))
            .appFont(.caption).foregroundStyle(.secondary)
        }
        if result.unreadablePages > 0 {
          Text(AppText.text("Some cached chapters are no longer available. Reopen those chapters to cache them again."))
            .appFont(.caption).foregroundStyle(.secondary)
        }
        ForEach(result.matches) { match in
          Button { select(match) } label: {
            VStack(alignment: .leading, spacing: 8) {
              HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(match.bookTitle).forumFont(.headline).lineLimit(1)
                Text(match.author).forumFont(.caption).foregroundStyle(.secondary).lineLimit(1)
              }
              Text(match.publicationTitle).forumFont(.caption).foregroundStyle(.secondary).lineLimit(2)
              highlighted(match).forumFont(.body).lineLimit(4)
            }.foregroundStyle(.primary).padding(.vertical, 4)
          }.buttonStyle(.plain)
        }
      }
    }.navigationTitle(AppText.text("Cached text search")).navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: AppText.text("Search cached text"))
      .textInputAutocapitalization(.never).autocorrectionDisabled()
      .task(id: keyword) {
        result = .init(); error = nil
        guard !keyword.isEmpty else { searching = false; return }
        searching = true
        do {
          try await Task.sleep(for: .milliseconds(300))
          let found = try await offline.search(keyword, books: library.document.readingBooks)
          try Task.checkCancellation()
          result = found; searching = false
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = AppText.error(error); searching = false } }
      }
  }
  private func highlighted(_ match: BookhouseOfflineMatch) -> Text {
    guard let range = match.snippet.range(of: match.query, options: BookhouseOfflineSearch.options) else { return Text(match.snippet) }
    return Text(String(match.snippet[..<range.lowerBound])) + Text(String(match.snippet[range])).bold().foregroundColor(.blue) + Text(String(match.snippet[range.upperBound...]))
  }
}
