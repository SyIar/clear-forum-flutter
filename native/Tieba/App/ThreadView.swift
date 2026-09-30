import SwiftUI

struct ReplyContext: Identifiable {
  let thread: String
  let forum: Forum
  var parent = ""
  var subpost = ""
  var replyUser = ""
  var restored: JSON? = nil
  var id: String { thread + ":" + parent + ":" + subpost }
}
private struct PostPosition: PreferenceKey {
  static let defaultValue: [String: CGFloat] = [:]
  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { _, next in next } }
}
struct ThreadView: View {
  let id: String
  let initialAnchor: String
  let initialPage: Int
  let initialAuthor: Bool
  var initialReverse = false
  var resumeHistory = true
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var result = PageResult<Post>()
  @State private var page = 1
  @State private var anchor = ""
  @State private var onlyAuthor = false
  @State private var reverse = false
  @State private var reader = false
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  @State private var initialized = false
  @State private var filtersReady = false
  @State private var reply: ReplyContext?
  @State private var jump = false
  @State private var jumpValue = ""
  @State private var saved = false
  @State private var removing = false
  @State private var visiblePost = ""
  @State private var historyTask: Task<Void, Never>?
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          Color.clear.frame(height: 0).id("top")
          if let thread = result.thread {
            Text(thread.title.isEmpty ? tr("noTitle") : thread.title).tiebaFont(.title3, weight: .bold).padding(.horizontal, 4)
            if let forum = result.forum { NavigationLink(forum.name, value: Route.forum(forum.name)).tiebaFont(.caption).padding(.horizontal, 4) }
            if settings.flag("showShortcutInThread") && !reader {
              HStack { Button(tr(onlyAuthor ? "allReplies" : "onlyAuthor")) { onlyAuthor.toggle() }; Button(tr(reverse ? "oldestFirst" : "newestFirst")) { reverse.toggle() } }.appFont(.caption).buttonStyle(.glass)
            }
          }
          ForEach(result.items) { post in
            PostCard(post: post, forum: result.forum ?? Forum(), reader: reader) { target in reply = target }
              .id(post.id).background(GeometryReader { geometry in Color.clear.preference(key: PostPosition.self, value: [post.id: geometry.frame(in: .named("posts")).maxY]) })
          }
          LoadState(loading: loading, error: error, empty: result.items.isEmpty) { request = UUID() }
        }.padding(.horizontal, 10).padding(.bottom, 12)
      }.coordinateSpace(name: "posts").background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(result.forum?.name ?? tr("threads")).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
          ToolbarItemGroup(placement: .topBarTrailing) {
            if !reader { Button(tr("reply"), systemImage: "square.and.pencil") { app.requireLogin { reply = ReplyContext(thread: id, forum: result.forum ?? Forum()) } }.disabled(result.forum == nil) }
            Menu {
              Toggle(tr("onlyAuthor"), isOn: $onlyAuthor)
              Toggle(tr("newestFirst"), isOn: $reverse)
              Toggle(tr("readerMode"), isOn: $reader)
              Button(tr(saved ? "unsavePost" : "savePost"), systemImage: saved ? "bookmark.slash" : "bookmark") { perform { try await app.api.bookmark(thread: id, post: visiblePost, remove: saved); saved.toggle() } }
              Button(tr("jumpPage"), systemImage: "number") { jumpValue = String(page); jump = true }
              Button(tr("backToTop"), systemImage: "arrow.up") { withAnimation { proxy.scrollTo("top") } }
              ShareLink(item: URL(string: "https://tieba.baidu.com/p/\(id)")!) { Label(tr("share"), systemImage: "square.and.arrow.up") }
              if result.thread?.author.id == app.activeID { Button(tr("deleteThread"), systemImage: "trash", role: .destructive) { removing = true } }
            } label: { Image(systemName: "ellipsis") }
          }
          Pagination(page: page, more: result.hasMore, loading: loading, previous: { change(page - 1) }, refresh: { request = UUID() }, next: { change(page + 1) }, jump: { jumpValue = String(page); jump = true })
        }
        .task(id: request) {
          if !initialized {
            initialized = true; page = initialPage; anchor = initialAnchor; onlyAuthor = initialAuthor; reverse = initialReverse; reader = settings.flag("readerMode")
            if resumeHistory, initialAnchor.isEmpty, settings.flag("restoreReading"), let record = app.library.rows("history").first(where: { string($0["threadId"]) == id }) {
              page = max(1, integer(record["page"])); anchor = string(record["lastPostId"]); onlyAuthor = boolean(record["onlyAuthor"])
            }
          }
          let target = anchor
          await load()
          guard !Task.isCancelled else { return }
          filtersReady = true
          proxy.scrollTo(result.items.contains { $0.id == target } ? target : "top", anchor: .top)
        }.refreshable { await load() }
        .onChange(of: onlyAuthor) { old, new in if filtersReady && old != new { change(1) } }
        .onChange(of: reverse) { _, _ in if filtersReady { change(1) } }
        .onPreferenceChange(PostPosition.self) { values in
          guard !loading, let post = values.filter({ $0.value > 0 }).min(by: { $0.value < $1.value })?.key else { return }
          visiblePost = post; historyTask?.cancel()
          historyTask = Task { @MainActor in try? await Task.sleep(nanoseconds: 450_000_000); guard !Task.isCancelled else { return }; remember(post) }
        }
        .onDisappear { historyTask?.cancel(); if !visiblePost.isEmpty { remember(visiblePost) } }
        .sheet(item: $reply) { context in ReplyEditor(context: context) { reply = nil; request = UUID() } }
        .alert(tr("jumpPage"), isPresented: $jump) { TextField(tr("page"), text: $jumpValue).keyboardType(.numberPad); Button(tr("open")) { if let value = Int(jumpValue), (1...1_000_000).contains(value) { change(value) } else { app.error = tr("invalidPage") } }; Button(tr("cancel"), role: .cancel) {} }
        .confirmationDialog(tr("deleteConfirm"), isPresented: $removing, titleVisibility: .visible) { Button(tr("deleteThread"), role: .destructive) { perform { try await app.api.removeOwnContent(forum: result.forum ?? Forum(), thread: id); request = UUID() } } }
    }
  }
  private func change(_ value: Int) { page = max(1, value); anchor = ""; request = UUID() }
  private func perform(_ body: @escaping () async throws -> Void) { app.requireLogin { Task { @MainActor in do { try await body() } catch { app.error = error.localizedDescription } } } }
  private func remember(_ post: String) { guard let thread = result.thread else { return }; app.updateLibrary { $0.remember(thread: id, title: thread.title, forum: result.forum?.name ?? "", post: post, page: page, onlyAuthor: onlyAuthor) } }
  private func load() async {
    let expected = request; loading = true; error = nil
    do {
      let data = try await app.api.thread(id, page: page, onlyAuthor: onlyAuthor, reverse: reverse, anchor: anchor)
      guard !Task.isCancelled, expected == request else { return }
      var seen = Set<String>(); result = data; result.items = data.items.filter { seen.insert($0.id).inserted }; page = data.page; saved = data.thread?.saved ?? false; anchor = ""
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    if expected == request { loading = false }
  }
}

struct PostCard: View {
  @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
  let post: Post
  let forum: Forum
  var reader = false
  let reply: (ReplyContext) -> Void
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var liked: Bool?
  @State private var likes: Int?
  @State private var busy = false
  @State private var reveal = false
  @State private var nested = false
  @State private var removing = false
  @State private var actionURL: URL?
  private var blocked: Bool { app.library.blocked(user: post.author, thread: post.threadID, text: post.plainText) }
  var body: some View {
    if blocked && !reveal {
      if !settings.flag("hideBlockedContent") && settings.flag("showBlockTip") { Button(tr("contentHidden")) { reveal = true }.appFont(.caption).padding(12) }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 8) {
          NavigationLink(value: Route.user(post.author.id)) { Avatar(user: post.author) }
          VStack(alignment: .leading, spacing: 2) {
            NavigationLink(post.author.name.isEmpty ? tr("unknownUser") : post.author.name, value: Route.user(post.author.id)).tiebaFont(.subheadline, weight: .semibold).foregroundStyle(.primary)
            if settings.flag("showBothUsernameAndNickname") && !post.author.username.isEmpty && post.author.username != post.author.name { Text(post.author.username).tiebaFont(.caption2).foregroundStyle(.secondary) }
            if post.author.level > 0 { Text("Lv.\(post.author.level)").appFont(.caption2).foregroundStyle(.secondary) }
          }
          Spacer(minLength: 2)
          if post.floor > 0 { Text("#\(post.floor)").appFont(.caption, weight: .semibold).foregroundStyle(.tint) }
          Menu {
            Button(tr("copyText"), systemImage: "document.on.document") { UIPasteboard.general.string = post.plainText }
            Button(tr("savePost"), systemImage: "bookmark") { perform { try await app.api.bookmark(thread: post.threadID, post: post.id) } }
            Button(tr("blockUser"), systemImage: "person.slash") { app.updateLibrary { $0.addBlock(kind: "user", value: post.author.id, label: post.author.name) } }
            Button(tr("report"), systemImage: "flag") { perform { let result = try await app.api.report(post.id); if let url = safeURL(first(object(result["data"]).isEmpty ? result : object(result["data"]), ["url", "report_url", "jubao_url"])) { actionURL = url } else { throw APIError(message: tr("operationFailed")) } } }
            if app.activeID == post.author.id { Button(tr("deletePost"), systemImage: "trash", role: .destructive) { removing = true } }
          } label: { Image(systemName: "ellipsis").appFont(.subheadline).padding(5) }
        }
        RichContent(parts: post.content)
        if !reader && !settings.flag("hideReply") {
          let replies = post.replies.filter { !app.library.blocked(user: $0.author, text: $0.plainText) }
          if !replies.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(replies) { item in
                Button { nested = true } label: {
                  (Text((item.author.name.isEmpty ? tr("unknownUser") : item.author.name) + ": ").font(Font(MixedScriptFont.font(size: captionSize * settings.fontScale, bold: true))).foregroundColor(settings.accent)
                   + Text(item.plainText).foregroundColor(Color(uiColor: .label)))
                    .tiebaFont(.caption).lineLimit(3).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
              }
              if post.replyCount > replies.count {
                Button("\(tr("viewReplies")) \(post.replyCount)") { nested = true }
                  .appFont(.caption).buttonStyle(.plain).foregroundStyle(settings.accent)
              }
            }.padding(10).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
          } else if post.replyCount > 0 { Button("\(tr("viewReplies")) \(post.replyCount)") { nested = true }.appFont(.caption) }
        }
        HStack {
          if !reader {
            Button { perform { let undo = liked ?? post.liked; try await app.api.agree(thread: post.threadID, post: post.id, forum: forum.id, undo: undo); liked = !undo; likes = max(0, (likes ?? post.likes) + (undo ? -1 : 1)) } } label: { Label((likes ?? post.likes).formatted(), systemImage: (liked ?? post.liked) ? "hand.thumbsup.fill" : "hand.thumbsup").foregroundStyle((liked ?? post.liked) ? settings.accent : Color(uiColor: .secondaryLabel)) }.disabled(busy)
            Button(tr("reply"), systemImage: "arrowshape.turn.up.left") { app.requireLogin { reply(ReplyContext(thread: post.threadID, forum: forum, parent: post.parentID.isEmpty ? post.id : post.parentID, subpost: post.parentID.isEmpty ? "" : post.id, replyUser: post.author.id)) } }
          }
          Spacer()
          if let date = post.time { Text(date, style: .relative).appFont(.caption2).foregroundStyle(.secondary) }
        }.appFont(.caption).buttonStyle(.plain).foregroundStyle(Color(uiColor: .secondaryLabel)).padding(.top, 2)
      }.padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: max(8, settings.number("radius"))))
        .sheet(isPresented: $nested) { NavigationStack { FloorView(thread: post.threadID, post: post.id, forum: forum).toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("close")) { nested = false } } } } }
        .sheet(item: Binding(get: { actionURL.map(URLItem.init) }, set: { actionURL = $0?.url })) { item in BaiduBrowser(session: app.session, url: item.url) { result in actionURL = nil; if case .failure(let error) = result { app.error = error.localizedDescription } }.ignoresSafeArea() }
        .confirmationDialog(tr("deleteConfirm"), isPresented: $removing, titleVisibility: .visible) { Button(tr("deletePost"), role: .destructive) { perform { try await app.api.removeOwnContent(forum: forum, thread: post.threadID, post: post.id, nested: !post.parentID.isEmpty) } } }
    }
  }
  private func perform(_ body: @escaping () async throws -> Void) { app.requireLogin { Task { @MainActor in busy = true; defer { busy = false }; do { try await body() } catch { app.error = error.localizedDescription } } } }
}

struct FloorView: View {
  let thread: String
  let post: String
  let forum: Forum
  @EnvironmentObject private var app: AppState
  @State private var result = PageResult<Post>()
  @State private var page = 1
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  @State private var reply: ReplyContext?
  var body: some View {
    ScrollView { LazyVStack(spacing: 10) { ForEach(result.items) { PostCard(post: $0, forum: forum) { reply = $0 } }; LoadState(loading: loading, error: error, empty: result.items.isEmpty) { request = UUID() } }.padding(10) }
      .background(Color(uiColor: .systemGroupedBackground)).navigationTitle(tr("floorReplies"))
      .toolbar { Pagination(page: page, more: result.hasMore, loading: loading, previous: { page -= 1; request = UUID() }, refresh: { request = UUID() }, next: { page += 1; request = UUID() }) }
      .task(id: request) { loading = true; error = nil; defer { loading = false }; do { result = try await app.api.floor(threadID: thread, postID: post, forumID: forum.id, page: page) } catch { self.error = error.localizedDescription } }
      .sheet(item: $reply) { ReplyEditor(context: $0) { reply = nil; request = UUID() } }
  }
}
