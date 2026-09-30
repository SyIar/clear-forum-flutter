import SwiftUI

enum Route: Hashable {
  case forum(String), thread(String, String, Int, Bool), user(String), search(String), collection(String), settings, accounts, topics, topic(String, String), info(String, String), drafts, inbox
  static func link(_ url: URL) -> Route? {
    guard url.user == nil, url.password == nil, url.scheme == "tblite" || (url.scheme == "https" && ["tieba.baidu.com", "tiebac.baidu.com"].contains(url.host ?? "")) else { return nil }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ key: String) -> String { query.first { $0.name == key }?.value ?? "" }
    let parts = url.pathComponents.filter { $0 != "/" }
    func validID(_ id: String) -> Bool { id.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil }
    if url.scheme == "tblite" {
      switch url.host {
      case "thread": guard parts.count == 1, validID(parts[0]) else { return nil }; return .thread(parts[0], value("pid"), max(1, Int(value("pn")) ?? 1), false)
      case "forum": guard parts.count <= 1 else { return nil }; let name = parts.first ?? value("kw"); return name.isEmpty ? nil : .forum(name)
      case "user": let id = parts.first ?? value("uid"); return parts.count <= 1 && validID(id) ? .user(id) : nil
      case "notifications": return .inbox
      case "history": return .collection("history")
      case "favorite", "favorites": return .collection("favorites")
      case "search": return .search("")
      default: return nil
      }
    }
    let id = parts.count > 1 && parts[0] == "p" ? parts[1] : value("tid")
    if validID(id), parts.count == 2 { return .thread(id, value("pid"), max(1, Int(value("pn")) ?? 1), false) }
    let name = value("kw").isEmpty ? value("fname") : value("kw")
    if !name.isEmpty, url.path == "/f" { return .forum(name) }
    return nil
  }
}

struct AppRoot: View {
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @Environment(\.exitTieba) private var exitTieba
  @State private var deepLink: Route?
  @State private var validating = false
  var body: some View {
    Group {
      if app.ready {
        TabView {
          navigation { HomeView() }.tabItem { Label(tr("home"), systemImage: "house") }
          if !settings.flag("hideExplore") { navigation { ExploreView() }.tabItem { Label(tr("explore"), systemImage: "safari") } }
          navigation { InboxView() }.tabItem { Label(tr("notifications"), systemImage: "bell") }
          navigation { MeView() }.tabItem { Label(tr("me"), systemImage: "person.crop.circle") }
        }.id(app.accountEpoch)
      } else {
        ContentUnavailableView(tr("initializationFailed"), systemImage: "exclamationmark.lock", description: Text(app.error ?? ""))
          .overlay(alignment: .bottom) {
            HStack {
              Button(tr("backToForums"), action: exitTieba)
              Button(tr("retry")) { app.initialize() }
            }.padding()
          }
      }
    }
    .tint(settings.accent).preferredColorScheme(settings.scheme)
    .scrollContentBackground(settings.text("nativeBackground").isEmpty ? .visible : .hidden)
    .background {
      if let file = DraftFiles.restore(settings.text("nativeBackground")), let image = UIImage(contentsOfFile: file.path) {
        Image(uiImage: image).resizable().scaledToFill().blur(radius: settings.number("translucentBackgroundBlur")).overlay(Color(uiColor: .systemBackground).opacity(settings.number("nativeSurfaceOpacity") == 0 ? 0.9 : settings.number("nativeSurfaceOpacity"))).ignoresSafeArea()
      }
    }
    .appFont(.body, baseSize: 16)
    .overlay { if validating { ProgressView(tr("loading")).padding(24).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20)) } }
    .sheet(isPresented: $app.login) {
      BaiduBrowser(session: nil) { result in
        app.login = false
        switch result {
        case .failure(let error): app.error = error.localizedDescription
        case .success(let data):
          if let data { Task { @MainActor in
            validating = true; defer { validating = false }
            do { let session = try await app.api.login(bduss: string(data["bduss"]), stoken: string(data["stoken"]), cookie: string(data["cookie"])); try app.save(session) }
            catch { app.error = error.localizedDescription }
          } }
        }
      }.ignoresSafeArea()
    }
    .alert(tr("operationFailed"), isPresented: Binding(get: { app.ready && app.error != nil }, set: { if !$0 { app.error = nil } })) { Button(tr("done")) { app.error = nil } } message: { Text(app.error ?? "") }
    .sheet(item: Binding(get: { deepLink.map(RouteItem.init) }, set: { deepLink = $0?.route })) { item in
      NavigationStack {
        Destination(route: item.route)
          .navigationDestination(for: Route.self) { Destination(route: $0) }
          .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("close")) { deepLink = nil } } }
      }
    }
    .onOpenURL { url in if let target = Route.link(url) { deepLink = target } else { app.error = tr("invalidLink") } }
    .environment(\.openURL, OpenURLAction { url in
      if let route = Route.link(url) { deepLink = route; return .handled }
      return .systemAction
    })
  }
  private func navigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    NavigationStack {
      content()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Route.self) { Destination(route: $0) }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button(action: exitTieba) { Image(systemName: "chevron.left") }
              .accessibilityLabel(tr("backToForums"))
          }
        }
    }
  }
}
private struct RouteItem: Identifiable { let route: Route; var id: String { String(describing: route) } }

struct Destination: View {
  let route: Route
  var body: some View {
    switch route {
    case .forum(let name): ForumView(name: name)
    case .thread(let id, let anchor, let page, let author): ThreadView(id: id, initialAnchor: anchor, initialPage: page, initialAuthor: author)
    case .user(let id): ProfileView(id: id)
    case .search(let name): SearchView(forum: name)
    case .collection(let kind): CollectionView(kind: kind)
    case .settings: SettingsView()
    case .accounts: AccountsView()
    case .topics: TopicsView()
    case .topic(let id, let name): TopicView(id: id, name: name)
    case .info(let id, let name): ForumInfoView(id: id, name: name)
    case .drafts: DraftsView()
    case .inbox: InboxView()
    }
  }
}

struct LoadState: View {
  let loading: Bool
  let error: String?
  var empty = false
  var retry: () -> Void
  var body: some View {
    if loading { ProgressView(tr("loading")).frame(maxWidth: .infinity).padding(30) }
    else if let error { ContentUnavailableView { Label(tr("networkError"), systemImage: "wifi.exclamationmark") } description: { Text(error) } actions: { Button(tr("retry"), action: retry).buttonStyle(.glass) } }
    else if empty { ContentUnavailableView(tr("emptyTitle"), systemImage: "tray", description: Text(tr("emptyBody"))) }
  }
}

struct Pagination: ToolbarContent {
  let page: Int
  let more: Bool
  let loading: Bool
  var previous: () -> Void
  var refresh: () -> Void
  var next: () -> Void
  var jump: (() -> Void)? = nil
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .bottomBar) {
      Button(tr("back"), systemImage: "chevron.left", action: previous).disabled(page <= 1 || loading)
      Button { jump?() } label: { Text("\(tr("page")) \(page)").appFont(.subheadline, weight: .semibold).monospacedDigit() }.disabled(jump == nil || loading)
      Button(tr("loadMore"), systemImage: "chevron.right", action: next).disabled(!more || loading)
    }
    ToolbarSpacer(.flexible, placement: .bottomBar)
    ToolbarItem(placement: .bottomBar) {
      Button(tr("refresh"), systemImage: "arrow.clockwise", action: refresh).disabled(loading)
    }
  }
}

struct Avatar: View {
  let user: UserProfile
  var size: CGFloat = 32
  var body: some View {
    AsyncImage(url: safeURL(user.avatar)) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
      .frame(width: size, height: size).clipShape(Circle())
  }
}
struct ForumRow: View {
  let forum: Forum
  @EnvironmentObject private var app: AppState
  var body: some View {
    NavigationLink(value: Route.forum(forum.name)) {
      HStack(spacing: 12) {
        AsyncImage(url: safeURL(forum.avatar)) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.blue) }.frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 3) {
          Text(forum.name).foregroundStyle(.primary)
          HStack(spacing: 8) {
            if let members = forum.members { Text("\(tr("members")) \(members.formatted())") }
            if forum.level > 0 { Text("Lv.\(forum.level)") }
            if forum.following { Text(tr(forum.signed ? "checkedIn" : "notCheckedIn")) }
          }.appFont(.caption).foregroundStyle(.secondary)
        }
      }.padding(.vertical, 3)
    }.contextMenu {
      Button(tr(app.library.pins.contains { $0.name == forum.name } ? "unpin" : "pin"), systemImage: "pin") { app.updateLibrary { $0.togglePin(forum) } }
      Button(tr("hide"), systemImage: "eye.slash") { app.updateLibrary { $0.addBlock(kind: "forum", value: forum.name, label: forum.name) } }
    }
  }
}
struct ThreadCard: View {
  let thread: ThreadSummary
  var standalone = false
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var revealed = false
  private var blocked: Bool { app.library.blocked(user: thread.author, forum: thread.forum.name, thread: thread.id, text: thread.title, extraText: thread.excerpt) }
  var body: some View {
    if !(settings.flag("blockVideo") && thread.video != nil) {
      if blocked && !revealed {
        if !settings.flag("hideBlockedContent") && settings.flag("showBlockTip") { Button(tr("contentHidden")) { revealed = true }.appFont(.caption).foregroundStyle(.secondary) }
      } else {
        NavigationLink(value: Route.thread(thread.id, thread.anchor, 1, false)) {
          VStack(alignment: .leading, spacing: settings.flag("compactCards") ? 5 : 8) {
            if !thread.title.isEmpty { Text(thread.title).tiebaFont(.body, weight: .semibold, baseSize: 16).lineLimit(3) }
            if !thread.pinned {
              if !thread.excerpt.isEmpty { Text(thread.excerpt).tiebaFont(.subheadline).lineLimit(settings.flag("compactCards") ? 2 : 3).foregroundStyle(.secondary) }
              if !settings.flag("hideMedia") && !thread.images.isEmpty {
                HStack(spacing: 6) {
                  ForEach(Array(thread.images.prefix(3)), id: \.self) { url in
                    RemotePicture(url: url, thumbnail: nil, preview: true).frame(maxWidth: .infinity).frame(height: 88).allowsHitTesting(false)
                  }
                }
              }
              HStack(spacing: 6) {
                Text(thread.author.name.isEmpty ? tr("unknownUser") : thread.author.name).tiebaFont(.caption).lineLimit(1)
                if !thread.forum.name.isEmpty { Text("\u{00B7} " + thread.forum.name).tiebaFont(.caption).lineLimit(1) }
                Spacer(minLength: 0)
                Image(systemName: "bubble.right"); Text(thread.replies.formatted())
              }.appFont(.caption).foregroundStyle(.secondary)
            }
          }.foregroundStyle(Color(uiColor: .label)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4).padding(standalone ? 12 : 0)
            .background(standalone ? Color(uiColor: .secondarySystemGroupedBackground) : .clear, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).contextMenu {
          NavigationLink(value: Route.user(thread.author.id)) { Label(tr("viewProfile"), systemImage: "person") }
          Button(tr("hide"), systemImage: "eye.slash") { app.updateLibrary { $0.addBlock(kind: "thread", value: thread.id, label: thread.title) } }
          ShareLink(item: URL(string: "https://tieba.baidu.com/p/\(thread.id)")!) { Label(tr("share"), systemImage: "square.and.arrow.up") }
        }
      }
    }
  }
}
