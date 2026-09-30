import SwiftUI

struct ExploreView: View {
  @EnvironmentObject private var app: AppState
  @State private var kind = "recommended"
  @State private var page = 1
  @State private var result = PageResult<ThreadSummary>()
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  @State private var hotCode = "all"
  @State private var hotTabs: [JSON] = []
  var body: some View {
    List {
      Section { Picker(tr("explore"), selection: $kind) { Text(tr("recommended")).tag("recommended"); Text(tr("concern")).tag("concern"); Text(tr("hot")).tag("hot") }.pickerStyle(.segmented) }
      if kind == "hot" {
        NavigationLink(tr("hotTopics"), value: Route.topics)
        if !hotTabs.isEmpty { Picker(tr("filter"), selection: $hotCode) { ForEach(Array(hotTabs.enumerated()), id: \.offset) { _, row in Text(first(row, ["tab_title", "tab_name"])).tag(string(row["tab_code"])) } } }
      }
      Section { ForEach(result.items) { ThreadCard(thread: $0) }; LoadState(loading: loading, error: error, empty: result.items.isEmpty) { request = UUID() } }
    }.navigationTitle(tr("explore"))
      .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink(value: Route.search("")) { Image(systemName: "magnifyingglass") } }; Pagination(page: page, more: result.hasMore, loading: loading, previous: { page -= 1; request = UUID() }, refresh: { request = UUID() }, next: { page += 1; request = UUID() }) }
      .onChange(of: kind) { _, _ in page = 1; result = PageResult(); request = UUID() }
      .onChange(of: hotCode) { _, _ in page = 1; request = UUID() }
      .task(id: request) { await load() }.refreshable { page = 1; await load() }
  }
  private func load() async {
    loading = true; error = nil; defer { loading = false }
    do {
      if kind == "hot" {
        let data = try await app.api.hotOverview(code: hotCode)
        if !Task.isCancelled { hotTabs = records(data["hot_thread_tab_info"]); result = PageResult(items: records(data["thread_info"]).filter { integer($0["is_ad"]) == 0 && $0["advertisement"] == nil }.map { ThreadSummary($0) }) }
      } else { let data = try await app.api.feed(kind, page: page); if !Task.isCancelled { result = data } }
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
}

struct SearchView: View {
  let forum: String
  @EnvironmentObject private var app: AppState
  @State private var query = ""
  @State private var submitted = ""
  @State private var kind = "threads"
  @State private var sort = 0
  @State private var page = 1
  @State private var threads = PageResult<ThreadSummary>()
  @State private var forums: [Forum] = []
  @State private var users: [UserProfile] = []
  @State private var suggestions: [String] = []
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  var body: some View {
    List {
      if forum.isEmpty { Picker(tr("search"), selection: $kind) { Text(tr("threads")).tag("threads"); Text(tr("searchForums")).tag("forums"); Text(tr("searchUsers")).tag("users") }.pickerStyle(.segmented) }
      if submitted.isEmpty {
        if !suggestions.isEmpty { Section(tr("search")) { ForEach(suggestions, id: \.self) { item in Button(item) { query = item; submit() } } } }
        Section(tr("searchHistory")) {
          ForEach(app.library.document["search"] as? [String] ?? [], id: \.self) { value in Button(value) { query = value; submit() } }
          Button(tr("clearSearchHistory"), role: .destructive) { app.updateLibrary { $0.document["search"] = [] } }
        }
      } else {
        if kind == "threads" { ForEach(threads.items) { ThreadCard(thread: $0) } }
        else if kind == "forums" { ForEach(forums, id: \.name) { ForumRow(forum: $0) } }
        else { ForEach(users) { user in NavigationLink(value: Route.user(user.id)) { HStack { Avatar(user: user); VStack(alignment: .leading) { Text(user.name).tiebaFont(.body); Text(user.intro).tiebaFont(.caption).foregroundStyle(.secondary).lineLimit(2) } } } } }
        LoadState(loading: loading, error: error, empty: threads.items.isEmpty && forums.isEmpty && users.isEmpty) { request = UUID() }
      }
    }.navigationTitle(forum.isEmpty ? tr("search") : forum)
      .searchable(text: $query, prompt: tr("searchHint")).onSubmit(of: .search, submit)
      .task(id: query) {
        if query.isEmpty { submitted = ""; suggestions = []; return }
        do { try await Task.sleep(nanoseconds: 350_000_000); let rows = try await app.api.suggestions(query, forum: kind == "forums"); if !Task.isCancelled { suggestions = rows } } catch {}
      }
      .task(id: request) { await load() }
      .onChange(of: kind) { _, _ in if !submitted.isEmpty { page = 1; request = UUID() } }
      .onChange(of: sort) { _, _ in page = 1; request = UUID() }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { if kind == "threads" { Menu { Picker(tr("sort"), selection: $sort) { Text(tr("relevance")).tag(0); Text(tr("latestPost")).tag(1) } } label: { Image(systemName: "line.3.horizontal.decrease") } } }
        Pagination(page: page, more: threads.hasMore && kind == "threads", loading: loading, previous: { page -= 1; request = UUID() }, refresh: { request = UUID() }, next: { page += 1; request = UUID() })
      }
  }
  private func submit() { submitted = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !submitted.isEmpty else { return }; app.updateLibrary { $0.search(submitted) }; page = 1; request = UUID() }
  private func load() async {
    guard !submitted.isEmpty else { return }; loading = true; error = nil; defer { loading = false }
    threads = PageResult(); forums = []; users = []
    do {
      if kind == "forums" { let rows = try await app.api.searchForums(submitted); if !Task.isCancelled { forums = rows } }
      else if kind == "users" { let rows = try await app.api.searchUsers(submitted); if !Task.isCancelled { users = rows } }
      else { let data = try await app.api.searchThreads(submitted, page: page, sort: sort, forum: forum); if !Task.isCancelled { threads = data } }
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
}

struct InboxView: View {
  @EnvironmentObject private var app: AppState
  @State private var kind = "replies"
  @State private var page = 1
  @State private var result = PageResult<JSON>()
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  var body: some View {
    List {
      if app.session == nil { Button(tr("signIn")) { app.login = true } }
      else {
        Picker(tr("notifications"), selection: $kind) { Text(tr("replyMe")).tag("replies"); Text(tr("mentionMe")).tag("mentions"); Text(tr("like")).tag("likes") }.pickerStyle(.segmented)
        ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
          let thread = first(item, ["thread_id", "tid"])
          let post = first(item, ["post_id", "pid", "reply_pid"])
          NavigationLink(value: Route.thread(thread, post, 1, false)) {
            VStack(alignment: .leading, spacing: 7) {
              Text(first(item, ["title", "thread_title"])).tiebaFont(.subheadline, weight: .semibold).lineLimit(2)
              Text(first(item, ["content", "reply_content", "abstract"])).tiebaFont(.subheadline).lineLimit(4)
              Text(UserProfile(raw: object(item["replyer"] ?? item["user"])).name).tiebaFont(.caption).foregroundStyle(.secondary)
            }
          }
        }
        LoadState(loading: loading, error: error, empty: result.items.isEmpty) { request = UUID() }
      }
    }.navigationTitle(tr("notifications"))
      .toolbar { Pagination(page: page, more: result.hasMore, loading: loading, previous: { page -= 1; request = UUID() }, refresh: { request = UUID() }, next: { page += 1; request = UUID() }) }
      .task(id: request) { await load() }.refreshable { page = 1; await load() }.onChange(of: kind) { _, _ in page = 1; request = UUID() }
  }
  private func load() async {
    guard app.session != nil else { return }; loading = true; error = nil; defer { loading = false }
    do { let data = try await app.api.notifications(kind, page: page); if !Task.isCancelled { result = data } } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
}

struct TopicsView: View {
  @EnvironmentObject private var app: AppState
  @State private var topics: [JSON] = []
  @State private var error: String?
  @State private var loading = false
  @State private var request = UUID()
  var body: some View {
    List {
      ForEach(Array(topics.enumerated()), id: \.offset) { index, row in
        let name = first(row, ["topic_name", "title", "name", "topic_desc"])
        NavigationLink(value: Route.topic(first(row, ["topic_id", "id"]), name)) { HStack { Text(String(index + 1)).appFont(.headline).foregroundStyle(.tint).frame(width: 28); VStack(alignment: .leading, spacing: 4) { Text(name).tiebaFont(.body); Text(first(row, ["abstract", "discuss_num", "hot_value"])).appFont(.caption).foregroundStyle(.secondary) } } }
      }
      LoadState(loading: loading, error: error, empty: topics.isEmpty) { request = UUID() }
    }.navigationTitle(tr("hotTopics")).task(id: request) { loading = true; defer { loading = false }; do { topics = try await app.api.hotTopics() } catch { self.error = error.localizedDescription } }
  }
}
struct TopicView: View {
  let id: String
  let name: String
  @EnvironmentObject private var app: AppState
  @State private var result = PageResult<ThreadSummary>()
  @State private var page = 1
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  var body: some View {
    List {
      let detail = object(result.raw["topic_info"])
      if !first(detail, ["description", "topic_desc"]).isEmpty { Text(first(detail, ["description", "topic_desc"])) }
      ForEach(result.items) { ThreadCard(thread: $0) }
      LoadState(loading: loading, error: error, empty: result.items.isEmpty) { request = UUID() }
    }.navigationTitle(name).navigationBarTitleDisplayMode(.inline)
      .toolbar { Pagination(page: page, more: result.hasMore, loading: loading, previous: { page -= 1; request = UUID() }, refresh: { request = UUID() }, next: { page += 1; request = UUID() }) }
      .task(id: request) { loading = true; error = nil; defer { loading = false }; do { result = try await app.api.topic(id, name: name, page: page) } catch { self.error = error.localizedDescription } }
  }
}
struct ForumInfoView: View {
  let id: String
  let name: String
  @EnvironmentObject private var app: AppState
  @State private var forum: Forum?
  @State private var rules: JSON = [:]
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  var body: some View {
    List {
      if let forum { Section(tr("forumInfo")) { Text(forum.intro); if let members = forum.members { LabeledContent(tr("members"), value: members.formatted()) }; LabeledContent(tr("threads"), value: forum.threads.formatted()) } }
      if !string(rules["preface"]).isEmpty { Section(tr("forumRules")) { Text(string(rules["preface"])) } }
      ForEach(Array(records(rules["rules"]).enumerated()), id: \.offset) { _, rule in DisclosureGroup(string(rule["title"])) { RichContent(parts: ContentPart.parse(rule["content"])) } }
      LoadState(loading: loading, error: error) { request = UUID() }
    }.navigationTitle(name).task(id: request) { loading = true; defer { loading = false }; do { forum = try await app.api.forumDetail(id); rules = try await app.api.forumRules(id) } catch { self.error = error.localizedDescription } }
  }
}
