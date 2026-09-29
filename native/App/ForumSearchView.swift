import SwiftUI

struct ForumSearchView: View {
  let navigate: (URL) -> Void
  @EnvironmentObject private var session: ForumSession
  @EnvironmentObject private var library: LibraryStore
  @State private var keywords = ""
  @State private var titlesOnly = false
  @State private var order = "date"
  @State private var southMethod = "OR"
  @State private var southOrder = "postdate"
  @State private var southTime = "31536000"
  @State private var submitted = ""
  @State private var page: ForumPage?
  @State private var loading = false
  @State private var error: String?
  @State private var needsLogin = false
  @State private var operation: Task<Void, Never>?
  @State private var requestID = UUID()
  @State private var browser: ReaderPresentation?
  @FocusState private var editing: Bool

  var body: some View {
    List {
      Section {
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Keywords", text: $keywords)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.search).focused($editing).onSubmit { search() }
          if !keywords.isEmpty {
            Button { keywords = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
              .buttonStyle(.plain).accessibilityLabel("Clear keywords")
          }
        }
        if session.site == .simp {
          Toggle("Titles only", isOn: $titlesOnly)
          Picker("Order", selection: $order) {
            Text("Date").tag("date")
            Text("Relevance").tag("relevance")
          }.pickerStyle(.segmented)
        } else {
          Picker("Title match", selection: $southMethod) {
            Text("Any word").tag("OR")
            Text("All words").tag("AND")
          }
          Picker("Order", selection: $southOrder) {
            Text("Newest threads").tag("postdate")
            Text("Latest replies").tag("lastpost")
            Text("Most replies").tag("replies")
            Text("Most views").tag("hits")
          }
          Picker("Time", selection: $southTime) {
            Text("All time").tag("all")
            Text("Past day").tag("86400")
            Text("Past week").tag("604800")
            Text("Past month").tag("2592000")
            Text("Past year").tag("31536000")
          }
        }
        Button(action: search) {
          HStack { Spacer(); Text("Search").fontWeight(.semibold); Spacer() }
        }.disabled(loading || keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if loading {
        Section { HStack { Spacer(); ProgressView(); Spacer() } }
      }
      if let error {
        Section {
          Text(error).foregroundStyle(.secondary)
          Button(needsLogin ? "Sign in" : "Site browser") { openBrowser() }
        }
      }
      if let page {
        let entries = page.entries.filter { session.site != .south || !library.document.blocksAuthor($0.authorID) }
        Section(submitted.isEmpty ? "Results" : submitted) {
          if entries.isEmpty { Text("No results").foregroundStyle(.secondary) }
          ForEach(entries) { entry in
            ForumEntryCard(entry: entry, isForum: false, navigate: navigate)
              .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
          }
        }.disabled(loading)
        if page.pageCount > 1 {
          Section {
            HStack {
              Button { if let previous = page.previous { load(previous) } } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous results").disabled(loading || page.previous == nil)
              Spacer()
              Text("\(page.pageNumber) / \(page.pageCount)").monospacedDigit().foregroundStyle(.secondary)
              Spacer()
              Button { if let next = page.next { load(next) } } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next results").disabled(loading || page.next == nil)
            }.buttonStyle(.borderless)
          }
        }
      }
    }
    .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { openBrowser() } label: { Image(systemName: "safari") }.accessibilityLabel("Open forum search in Site browser")
      }
    }
    .onDisappear { cancel() }
    .fullScreenCover(item: $browser) { item in
      ReaderController(presentation: item, session: session) { captured in
        browser = nil
        session.endBrowsing()
        guard let captured, let address = captured["url"] as? String, let target = URL(string: address),
              session.site.accepts(target), let html = captured["html"] as? String else { return }
        if SimpSitePolicy.searchResults(target) || SouthSearch.parameters(target) != nil {
          do {
            page = try ForumParser().parse(html, url: target)
            submitted = SouthSearch.parameters(target)?["keyword"] ?? URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value ?? "Results"
            error = nil
          }
          catch { self.error = error.localizedDescription }
        } else {
          if let parsed = try? ForumParser().parse(html, url: target) { session.pages.store(parsed) }
          navigate(target)
        }
      }.ignoresSafeArea()
    }
  }

  private func search() {
    guard !loading, !keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    editing = false
    submitted = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
    page = nil
    if session.site == .simp {
      let query = SimpSearchQuery(keywords: keywords, titlesOnly: titlesOnly, order: order)
      perform { try await session.search(query) }
    } else {
      let query = SouthSearchQuery(keywords: keywords, method: southMethod, order: southOrder, time: southTime)
      perform { try await session.search(query) }
    }
  }
  private func load(_ url: URL) {
    guard !loading, session.site.accepts(url), SimpSitePolicy.searchResults(url) || SouthSearch.parameters(url) != nil else { return }
    perform { try await session.load(url) }
  }
  private func perform(_ action: @escaping @MainActor () async throws -> ForumPage) {
    cancel()
    let id = UUID()
    requestID = id
    loading = true
    error = nil
    needsLogin = false
    operation = Task { @MainActor in
      defer { if requestID == id { loading = false; operation = nil } }
      do {
        let result = try await action()
        guard !Task.isCancelled, requestID == id else { return }
        page = result
      } catch {
        guard !Task.isCancelled, requestID == id else { return }
        self.error = error.localizedDescription
        needsLogin = (error as? ReaderFailure) == .login
      }
    }
  }
  private func cancel() {
    requestID = UUID()
    operation?.cancel()
    operation = nil
    loading = false
  }
  private func openBrowser() {
    let url = needsLogin ? session.site.login : page?.url ?? session.site.search
    cancel()
    editing = false
    page = nil
    session.beginBrowsing()
    browser = .browser(url)
  }
}
