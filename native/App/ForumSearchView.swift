import ForumUI
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
    ScrollViewReader { proxy in
      content.onChange(of: page?.url) { _, value in
        if value != nil { proxy.scrollTo("search-results", anchor: .top) }
      }
    }
  }

  private var content: some View {
    List {
      Section {
        HStack {
          Image(forumSymbol: "magnifyingglass").foregroundStyle(.secondary)
          TextField(AppText.text("Keywords"), text: $keywords)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.search).focused($editing).onSubmit { search() }
          if !keywords.isEmpty {
            Button { keywords = "" } label: { Image(forumSymbol: "xmark.circle.fill").foregroundStyle(.secondary) }
              .buttonStyle(.plain).accessibilityLabel(AppText.text("Clear keywords"))
          }
        }
        if session.site == .simp {
          Toggle(AppText.text("Titles only"), isOn: $titlesOnly)
          Picker(AppText.text("Order"), selection: $order) {
            Text(AppText.text("Date")).tag("date")
            Text(AppText.text("Relevance")).tag("relevance")
          }.pickerStyle(.segmented)
        } else if session.site == .south {
          Picker(AppText.text("Title match"), selection: $southMethod) {
            Text(AppText.text("Any word")).tag("OR")
            Text(AppText.text("All words")).tag("AND")
          }
          Picker(AppText.text("Order"), selection: $southOrder) {
            Text(AppText.text("Newest threads")).tag("postdate")
            Text(AppText.text("Latest replies")).tag("lastpost")
            Text(AppText.text("Most replies")).tag("replies")
            Text(AppText.text("Most views")).tag("hits")
          }
          Picker(AppText.text("Time"), selection: $southTime) {
            Text(AppText.text("All time")).tag("all")
            Text(AppText.text("Past day")).tag("86400")
            Text(AppText.text("Past week")).tag("604800")
            Text(AppText.text("Past month")).tag("2592000")
            Text(AppText.text("Past year")).tag("31536000")
          }
        }
        Button(action: search) {
          HStack { Spacer(); Text(AppText.text("Search")).fontWeight(.semibold); Spacer() }
        }.disabled(loading || keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if loading {
        Section { HStack { Spacer(); ProgressView(); Spacer() } }
      }
      if let error {
        Section {
          Text(error).foregroundStyle(.secondary)
          Button(needsLogin ? AppText.text("Sign in") : AppText.text("Site browser")) { openBrowser() }
        }
      }
      if let page {
        let entries = page.entries.filter { session.site != .south || !library.document.blocksAuthor($0.authorID) }
        Section(submitted.isEmpty ? AppText.text("Results") : submitted) {
          if entries.isEmpty { Text(AppText.text("No results")).foregroundStyle(.secondary) }
          ForEach(entries) { entry in
            ForumEntryCard(entry: entry, isForum: false, navigate: navigate, formatBookhouseTitle: session.site == .bookhouse)
              .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
          }
        }.disabled(loading).id("search-results")
        if page.pageCount > 1 {
          Section {
            HStack {
              Button { if let previous = page.previous { load(previous) } } label: { Image(forumSymbol: "chevron.left") }
                .accessibilityLabel(AppText.text("Previous results")).disabled(loading || page.previous == nil)
              Spacer()
              // Bookhouse provides previous/next links, not a reliable total count.
              Text(session.site == .bookhouse ? AppText.format("Page %@", String(page.pageNumber)) : "\(page.pageNumber) / \(page.pageCount)")
                .monospacedDigit().foregroundStyle(.secondary)
              Spacer()
              Button { if let next = page.next { load(next) } } label: { Image(forumSymbol: "chevron.right") }
                .accessibilityLabel(AppText.text("Next results")).disabled(loading || page.next == nil)
            }.buttonStyle(.borderless)
          }
        }
      }
    }
    .navigationTitle(AppText.text("Search")).navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { openBrowser() } label: { Image(forumSymbol: "safari") }.accessibilityLabel(AppText.text("Open forum search in Site browser"))
      }
    }
    .onDisappear { cancel() }
    .fullScreenCover(item: $browser) { item in
      ReaderController(presentation: item, session: session) { captured in
        browser = nil
        session.endBrowsing()
        guard let captured, let address = captured["url"] as? String, let target = URL(string: address),
              session.site.accepts(target), let html = captured["html"] as? String else { return }
        if SimpSitePolicy.searchResults(target) || SouthSearch.parameters(target) != nil || BookhouseSitePolicy.route(target)?.kind == .search {
          do {
            page = try ForumParser().parse(html, url: target)
            submitted = BookhouseSitePolicy.route(target)?.parameters["keywords"] ?? SouthSearch.parameters(target)?["keyword"] ?? URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value ?? AppText.text("Results")
            error = nil
          }
          catch { self.error = AppText.error(error) }
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
    } else if session.site == .south {
      let query = SouthSearchQuery(keywords: keywords, method: southMethod, order: southOrder, time: southTime)
      perform { try await session.search(query) }
    } else if let url = BookhouseSitePolicy.search(keywords) {
      perform { try await session.load(url) }
    } else {
      error = AppText.text("Enter up to 100 characters for search.")
    }
  }
  private func load(_ url: URL) {
    guard !loading, session.site.accepts(url), SimpSitePolicy.searchResults(url) || SouthSearch.parameters(url) != nil || BookhouseSitePolicy.route(url)?.kind == .search else { return }
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
        self.error = AppText.error(error)
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
    let bookhouseSearch = session.site == .bookhouse ? BookhouseSitePolicy.search(submitted.isEmpty ? keywords : submitted) : nil
    let url = needsLogin ? session.site.login : page?.url ?? bookhouseSearch ?? session.site.search
    cancel()
    editing = false
    page = nil
    session.beginBrowsing()
    browser = .browser(url)
  }
}
