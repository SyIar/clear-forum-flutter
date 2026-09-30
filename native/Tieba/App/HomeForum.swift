import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var loading = false
  @State private var error: String?
  @State private var checkIn = false
  @State private var open = false
  @State private var query = ""
  @State private var target: Route?
  var body: some View {
    List {
      if !app.library.pins.isEmpty { Section(tr("pinnedForums")) { forums(app.library.pins) } }
      if settings.flag("homePageShowHistoryForum") && !app.library.recentForums.isEmpty { Section(tr("recentForums")) { forums(app.library.recentForums) } }
      Section(tr("followedForums")) {
        if app.session == nil { Button(tr("signIn")) { app.login = true } }
        else { forums(app.followed.filter { forum in settings.flag("showTopForumInNormalList") || !app.library.pins.contains(where: { $0.name == forum.name }) }) }
        LoadState(loading: loading, error: error, empty: app.session != nil && app.followed.isEmpty) { Task { await load() } }
      }
    }.navigationTitle(tr("appTitle"))
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink(value: Route.search("")) { Image(systemName: "magnifyingglass") }
          Menu {
            Button(tr("openForum"), systemImage: "plus") { open = true }
            Button(tr(settings.flag("listSingle") ? "gridView" : "listView"), systemImage: "square.grid.2x2") { settings.set("listSingle", !settings.flag("listSingle")) }
            Button(tr("signAll"), systemImage: "checkmark.circle") { app.requireLogin { checkIn = true } }.disabled(app.signing)
          } label: { Image(systemName: "ellipsis") }
        }
      }.task { await load(); await automaticCheckIn() }.refreshable { await load() }
      .confirmationDialog(tr("signAllConfirm"), isPresented: $checkIn, titleVisibility: .visible) { Button(tr("confirm")) { Task { await app.signAll() } } }
      .alert(tr("openForum"), isPresented: $open) { TextField(tr("forumName"), text: $query); Button(tr("open")) { if let url = URL(string: query), let route = Route.link(url) { target = route } else if !query.trimmingCharacters(in: .whitespaces).isEmpty { target = .forum(query.trimmingCharacters(in: .whitespaces)) } }; Button(tr("cancel"), role: .cancel) {} }
      .navigationDestination(item: $target) { Destination(route: $0) }
  }
  @ViewBuilder private func forums(_ values: [Forum]) -> some View {
    let visible = values.filter { !app.library.blocked(forum: $0.name) }
    if settings.flag("listSingle") { ForEach(visible, id: \.name) { ForumRow(forum: $0) } }
    else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 14) { ForEach(visible, id: \.name) { forum in
      NavigationLink(value: Route.forum(forum.name)) {
        VStack(spacing: 7) {
          AsyncImage(url: safeURL(forum.avatar)) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: "bubble.left.and.bubble.right.fill").appFont(.title2) }.frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 14))
          Text(forum.name).tiebaFont(.subheadline).lineLimit(1)
          if forum.following { Text(tr(forum.signed ? "checkedIn" : "notCheckedIn")).appFont(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity).padding(.vertical, 7)
      }.buttonStyle(.plain).contextMenu { Button(tr("pin")) { app.updateLibrary { $0.togglePin(forum) } } }
    } } }
  }
  private func load() async { loading = true; error = nil; defer { loading = false }; do { try await app.refreshForums() } catch { self.error = error.localizedDescription } }
  private func automaticCheckIn() async {
    guard settings.flag("autoSign"), app.session != nil, settings.text("signDay") != DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none) else { return }
    let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
    if formatter.string(from: Date()) >= settings.text("autoSignTime") { await app.signAll() }
  }
}

struct ForumView: View {
  let name: String
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var feed = ForumFeed()
  @State private var loadGate = ForumFeedLoadGate()
  @State private var initialized = false
  @State private var appliedSort = 0
  @State private var isVisible = false
  @State private var scrollTarget: String?
  @State private var scrollPhase = ScrollPhase.idle
  @State private var edgeTrigger = ForumFeedEdgeTrigger()
  @State private var edges = ForumFeedScrollEdges()
  @State private var pending: PendingForumPage?
  @State private var visibleThread: String?
  @State private var digest = false
  @State private var sort = 0
  @State private var loading = false
  @State private var error: String?
  @State private var action = false
  @State private var signed = false
  @State private var request = ForumFeedRequest()
  private var busy: Bool { loading || pending != nil }
  private var visiblePinned: [ThreadSummary] {
    feed.pinned.filter { item in
      !(settings.flag("blockVideo") && item.video != nil) && !app.library.blocked(user: item.author, forum: name, thread: item.id, text: item.title, extraText: item.excerpt)
    }
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if let forum = feed.forum { forumHeader(forum).id("top") }
          if !visiblePinned.isEmpty {
            VStack(spacing: 0) {
              ForEach(Array(visiblePinned.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 38) }
                NavigationLink(value: Route.thread(item.id, "", 1, false)) {
                  HStack(spacing: 10) {
                    Image(systemName: "pin.fill").appFont(.caption).foregroundStyle(settings.accent)
                    Text(item.title).tiebaFont(.subheadline).foregroundStyle(Color(uiColor: .label)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").appFont(.caption2).foregroundStyle(Color(uiColor: .tertiaryLabel))
                  }.padding(12).contentShape(Rectangle())
                }.buttonStyle(.plain)
              }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
          }
          ForEach(feed.items) { ThreadCard(thread: $0, standalone: true).id($0.id) }
          LoadState(loading: busy, error: error, empty: !busy && feed.items.isEmpty && feed.pinned.isEmpty) { retry() }
        }.scrollTargetLayout().padding(12)
      }.background(Color(uiColor: .systemGroupedBackground))
        .defaultScrollAnchor(.top, for: .initialOffset)
        .scrollBounceBehavior(.always, axes: .vertical)
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { ids in
          guard isVisible else { return }
          if ids.contains("top"), let first = feed.pages.first { feed.showPage(first.number) }
          else if let item = feed.items.first(where: { ids.contains($0.id) }) {
            visibleThread = item.id; feed.showThread(item.id)
          }
        }
        .onScrollGeometryChange(for: ForumFeedScrollEdges.self) { ForumFeedScrollEdges($0) } action: { _, value in
          edges = value; loadAtEdge()
        }
        .onScrollPhaseChange { old, phase in
          scrollPhase = phase
          if phase == .tracking || (phase == .interacting && old != .tracking) { edgeTrigger.beginDrag() }
          if phase == .interacting { loadAtEdge() }
          if phase == .idle { applyPendingPage() }
        }
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              NavigationLink(value: Route.search(name)) { Label(tr("searchInForum"), systemImage: "magnifyingglass") }
              NavigationLink(value: Route.info(feed.forum?.id ?? "", name)) { Label(tr("forumInfo"), systemImage: "info.circle") }
              Picker(tr("sort"), selection: $sort) { Text(tr("latestReply")).tag(0); Text(tr("latestPost")).tag(1) }
              Toggle(tr("digest"), isOn: $digest)
              Button(tr("pin"), systemImage: "pin") { if let forum = feed.forum { app.updateLibrary { $0.togglePin(forum) } } }
              Button(tr("backToTop"), systemImage: "arrow.up") { withAnimation { proxy.scrollTo("top", anchor: .top) } }
            } label: { Image(systemName: "ellipsis") }
          }
          Pagination(page: feed.currentPage, more: feed.canGoForward, loading: busy,
                     previous: { go(to: feed.currentPage - 1) }, refresh: { refresh() }, next: { go(to: feed.currentPage + 1) })
        }
        .task(id: request.id) { initialize(); await load() }
        .onChange(of: sort) { _, value in
          guard value != appliedSort else { return }
          appliedSort = value; settings.set("forumSort." + name, String(value)); resetQuery()
        }
        .onChange(of: digest) { _, _ in resetQuery() }
        .onChange(of: scrollTarget) { _, target in
          guard let target else { return }
          // One explicit move after layout; never bind visibility back into scrolling.
          proxy.scrollTo(target, anchor: .top); scrollTarget = nil
        }
        .onAppear { initialize(); isVisible = true; applyPendingPage() }
        .onDisappear { isVisible = false; scrollPhase = .idle }
    }
  }
  private func forumHeader(_ forum: Forum) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        AsyncImage(url: safeURL(forum.avatar)) { image in image.resizable().scaledToFill() } placeholder: {
          Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(settings.accent)
        }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 4) {
          Text(forum.name.isEmpty ? name : forum.name).tiebaFont(.headline).foregroundStyle(Color(uiColor: .label))
          if !settings.flag("hideForumIntroAndStat") {
            Text([forum.members.map { "\(tr("members")) \($0.formatted())" }, "\(tr("threads")) \(forum.threads.formatted())"].compactMap { $0 }.joined(separator: " · "))
              .appFont(.caption).foregroundStyle(Color(uiColor: .secondaryLabel)).fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 0)
      }
      if !settings.flag("hideForumIntroAndStat") && !forum.intro.isEmpty {
        Text(forum.intro).tiebaFont(.subheadline).foregroundStyle(Color(uiColor: .secondaryLabel))
      }
      HStack {
        Button(tr(forum.following ? "unfollow" : "follow")) {
          perform { try await app.api.follow(forum, enabled: !forum.following); refresh() }
        }.buttonStyle(.glass).disabled(action)
        Spacer(minLength: 12)
        Button(tr((signed || forum.signed) ? "checkedIn" : "checkIn"), systemImage: (signed || forum.signed) ? "checkmark.circle.fill" : "checkmark.circle") {
          perform { try await app.sign(forum); signed = true; feed.markSigned() }
        }.buttonStyle(.glassProminent).disabled(signed || forum.signed || action)
      }.appFont(.subheadline)
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }
  private func perform(_ body: @escaping () async throws -> Void) { app.requireLogin { Task { @MainActor in action = true; defer { action = false }; do { try await body() } catch { app.error = error.localizedDescription } } } }
  private func initialize() {
    guard !initialized else { return }
    initialized = true
    appliedSort = Int(settings.text("forumSort." + name)) ?? (settings.text("defaultSortType") == "post" ? 1 : 0)
    sort = appliedSort
  }
  private func resetQuery() {
    pending = nil; feed = ForumFeed(); visibleThread = nil; error = nil
    request = ForumFeedRequest()
  }
  private func refresh() {
    pending = nil
    request = ForumFeedRequest(page: feed.currentPage, replacingAll: false, moveToPage: false)
  }
  private func retry() {
    request = ForumFeedRequest(page: request.page, replacingAll: request.replacingAll, moveToPage: request.moveToPage)
  }
  private func go(to number: Int) {
    guard !busy, number > 0 else { return }
    if feed.contains(number) {
      feed.showPage(number)
      scrollTarget = number == feed.pages.first?.number ? "top" : feed.firstThread(on: number)
    } else if number == feed.nextPage || number == feed.previousPage {
      request = ForumFeedRequest(page: number, replacingAll: false, moveToPage: true)
    }
  }
  private func loadAtEdge() {
    guard isVisible, !busy, error == nil, !feed.pages.isEmpty else { return }
    guard let edge = edgeTrigger.update(topPull: Double(edges.topPull), remaining: Double(edges.remaining),
      interacting: scrollPhase == .interacting || scrollPhase == .decelerating,
      previous: feed.previousPage != nil, next: feed.nextPage != nil) else { return }
    guard let number = edge == .previous ? feed.previousPage : feed.nextPage else { return }
    request = ForumFeedRequest(page: number, replacingAll: false, moveToPage: false)
  }
  private func load() async {
    let expected = request
    guard loadGate.needsLoad(expected) else { return }
    loading = true; error = nil
    defer { if request.id == expected.id { loading = false } }
    do {
      let response = try await app.api.forum(name, page: expected.page, sort: sort, digest: digest)
      guard !Task.isCancelled, request.id == expected.id else { return }
      pending = PendingForumPage(request: expected, response: response)
      loadGate.finish(expected)
      applyPendingPage()
    } catch {
      guard !Task.isCancelled, request.id == expected.id else { return }
      self.error = error.localizedDescription; loadGate.finish(expected)
    }
  }
  private func applyPendingPage() {
    guard isVisible, let pending, pending.request.id == request.id else { return }
    // Inserting above the viewport waits for the finger/momentum to stop.
    let prepend = pending.response.page < (feed.pages.first?.number ?? 1)
    if prepend && scrollPhase != .idle { return }
    let anchor = prepend ? visibleThread ?? feed.items.first?.id : nil
    guard feed.apply(pending.response, replacingAll: pending.request.replacingAll) else { self.pending = nil; return }
    if pending.request.moveToPage {
      feed.showPage(pending.response.page)
      scrollTarget = pending.request.replacingAll ? "top" : feed.firstThread(on: pending.response.page)
    } else if let anchor { scrollTarget = anchor }
    if let forum = feed.forum { signed = signed || forum.signed; app.updateLibrary { $0.visit(forum) } }
    self.pending = nil
  }
}

private struct PendingForumPage {
  let request: ForumFeedRequest
  let response: PageResult<ThreadSummary>
}

private struct ForumFeedScrollEdges: Equatable {
  var topPull = 0
  var remaining = Int.max
  init() {}
  init(_ geometry: ScrollGeometry) {
    let pull = -geometry.contentOffset.y - geometry.contentInsets.top
    topPull = pull >= 56 ? 56 : (pull > 0 ? 1 : 0)
    let bottom = max(-geometry.contentInsets.top, geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height)
    remaining = bottom - geometry.contentOffset.y <= 240 ? 0 : Int.max
  }
}
