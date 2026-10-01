import ForumUI
import SwiftUI
import PhotosUI

struct MeView: View {
  @EnvironmentObject private var app: AppState
  @State private var service = false
  var body: some View {
    List {
      Section {
        if let session = app.session { NavigationLink(value: Route.user(session.userID)) { HStack { Avatar(user: session.user, size: 52); VStack(alignment: .leading) { Text(session.user.name).tiebaFont(.headline); Text(session.user.intro).tiebaFont(.caption).foregroundStyle(.secondary) } } } }
        else { Button(tr("signIn")) { app.login = true } }
      }
      Section {
        NavigationLink(value: Route.accounts) { Label(tr("accounts"), forumSymbol: "person.2") }
        NavigationLink(value: Route.collection("favorites")) { Label(tr("favorites"), forumSymbol: "bookmark") }
        NavigationLink(value: Route.collection("history")) { Label(tr("history"), forumSymbol: "clock") }
        NavigationLink(value: Route.drafts) { Label(tr("drafts"), forumSymbol: "doc") }
        if let session = app.session { NavigationLink(tr("myPosts"), value: Route.collection("posts:" + session.userID)); NavigationLink(tr("myForums"), value: Route.collection("forums:" + session.userID)) }
      }
      Section {
        NavigationLink(value: Route.settings) { Label(tr("settings"), forumSymbol: "gearshape") }.accessibilityIdentifier("settings.open")
        Button(tr("serviceCenter"), forumSymbol: "questionmark.circle") { app.requireLogin { service = true } }
      }
    }.navigationTitle(tr("me")).sheet(isPresented: $service) { BaiduBrowser(session: app.session, url: URL(string: "https://tieba.baidu.com/mo/q/hybrid-main-service/uegServiceCenter")!) { result in service = false; if case .failure(let error) = result { app.error = error.localizedDescription } }.ignoresSafeArea() }
  }
}
struct AccountsView: View {
  @EnvironmentObject private var app: AppState
  @State private var remove: String?
  var body: some View {
    List {
      ForEach(app.sessions, id: \.userID) { session in
        Button { do { try app.activate(session.userID) } catch { app.error = error.localizedDescription } } label: {
          HStack { Avatar(user: session.user); Text(session.user.name); Spacer(); if app.activeID == session.userID { Image(forumSymbol: "checkmark") } }
        }.swipeActions { Button(tr("removeAccount"), role: .destructive) { remove = session.userID } }
      }
      Button(tr("addAccount"), forumSymbol: "person.badge.plus") { app.login = true }
      if app.session != nil { Button(tr("signOut"), role: .destructive) { do { try app.activate(nil) } catch { app.error = error.localizedDescription } } }
    }.navigationTitle(tr("accounts"))
      .forumConfirmation(tr("removeAccountBody"), isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), actions: { [
          ForumDialogAction(tr("removeAccount"), role: .destructive) { [accountID = remove] in if let accountID { do { try app.removeAccount(accountID) } catch { app.error = error.localizedDescription } }; remove = nil }
        ] })
  }
}

struct CollectionView: View {
  let kind: String
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var result = PageResult<ThreadSummary>()
  @State private var forums: [Forum] = []
  @State private var page = 1
  @State private var loading = false
  @State private var more = false
  @State private var error: String?
  @State private var request = UUID()
  @State private var historyTab = "threads"
  @State private var clear = false
  private var type: String { String(kind.split(separator: ":").first ?? "") }
  private var id: String { String(kind.split(separator: ":").last ?? "") }
  var body: some View {
    List {
      if type == "history" {
        Picker(tr("history"), selection: $historyTab) { Text(tr("threads")).tag("threads"); Text(tr("myForums")).tag("forums") }.pickerStyle(.segmented)
        if historyTab == "threads" {
          ForEach(Array(app.library.rows("history").enumerated()), id: \.offset) { _, row in
            NavigationLink(value: Route.thread(string(row["threadId"]), string(row["lastPostId"]), max(1, integer(row["page"])), boolean(row["onlyAuthor"]))) { VStack(alignment: .leading, spacing: 6) { Text(string(row["title"])).tiebaFont(.body).lineLimit(2); Text(string(row["forumName"])).tiebaFont(.caption).foregroundStyle(.secondary) } }
              .swipeActions {
                Button(tr("clear"), role: .destructive) {
                  app.updateLibrary { $0.document["history"] = $0.rows("history").filter { string($0["threadId"]) != string(row["threadId"]) } }
                }
              }
          }
        } else {
          ForEach(Array(app.library.rows("forumHistory").enumerated()), id: \.offset) { _, row in
            let forum = Forum(raw: object(row["forum"]))
            ForumRow(forum: forum).swipeActions { Button(tr("clear"), role: .destructive) { app.updateLibrary { library in library.document["forumHistory"] = library.rows("forumHistory").filter { Forum(raw: object($0["forum"])).name != forum.name }; library.document["recentForums"] = library.rows("recentForums").filter { Forum(raw: $0).name != forum.name } } } }
          }
        }
      } else if type == "forums" { ForEach(forums, id: \.name) { ForumRow(forum: $0) } }
      else { ForEach(result.items) { thread in
        if type == "favorites" { NavigationLink { ThreadView(id: thread.id, initialAnchor: thread.anchor, initialPage: 1, initialAuthor: settings.flag("collectThreadSeeLz"), initialReverse: settings.flag("collectThreadDescSort"), resumeHistory: false) } label: { VStack(alignment: .leading, spacing: 6) { Text(thread.title).tiebaFont(.body); Text(thread.excerpt).tiebaFont(.caption).lineLimit(2).foregroundStyle(.secondary) } } }
        else { ThreadCard(thread: thread) }
      } }
      if type != "history" { LoadState(loading: loading, error: error, empty: result.items.isEmpty && forums.isEmpty) { request = UUID() } }
    }.navigationTitle(tr(type == "history" ? "history" : type == "favorites" ? "favorites" : type == "forums" ? "myForums" : type == "replies" ? "userReplies" : "userPosts"))
      .toolbar {
        if type == "history" { ToolbarItem(placement: .topBarTrailing) { Button(tr("clear"), forumSymbol: "trash") { clear = true } } }
        else { Pagination(page: page, more: more, loading: loading, previous: { page -= 1; request = UUID() }, refresh: { request = UUID() }, next: { page += 1; request = UUID() }) }
      }.task(id: request) { await load() }.refreshable { await load() }
      .forumConfirmation(tr("clearConfirm"), isPresented: $clear, actions: { [
          ForumDialogAction(tr("clear"), role: .destructive) { app.updateLibrary { $0.document[historyTab == "threads" ? "history" : "forumHistory"] = []; if historyTab == "forums" { $0.document["recentForums"] = [] } } }
        ] })
  }
  private func load() async {
    guard type != "history" else { return }; loading = true; error = nil; defer { loading = false }
    do {
      if type == "forums" { let data = try await app.api.userForums(id, page: page); forums = data.items; more = data.hasMore }
      else { result = try await type == "favorites" ? app.api.favorites(page: page) : app.api.userPosts(id, page: page, replies: type == "replies"); more = result.hasMore }
    } catch { self.error = error.localizedDescription }
  }
}

struct ProfileView: View {
  let id: String
  @EnvironmentObject private var app: AppState
  @State private var profile: UserProfile?
  @State private var loading = false
  @State private var error: String?
  @State private var request = UUID()
  @State private var editing = false
  var body: some View {
    List {
      if let user = profile {
        Section {
          HStack { Avatar(user: user, size: 66); VStack(alignment: .leading, spacing: 5) { Text(user.name).tiebaFont(.title3, weight: .bold); Text(user.intro).tiebaFont(.subheadline).foregroundStyle(.secondary) } }.padding(.vertical, 8)
          HStack { Text("\(tr("followers")) \(user.followers.formatted())"); Spacer(); Text("\(tr("following")) \(user.follows.formatted())"); Spacer(); Text("\(tr("posts")) \(user.posts.formatted())") }.appFont(.caption)
          if app.activeID == user.id { Button(tr("editProfile")) { editing = true } }
          else { Button(tr(user.following ? "unfollow" : "follow")) { app.requireLogin { Task { @MainActor in do { try await app.api.follow(user, enabled: !user.following); request = UUID() } catch { app.error = error.localizedDescription } } } } }
        }
        Section { NavigationLink(tr("userPosts"), value: Route.collection("posts:" + id)); NavigationLink(tr("userReplies"), value: Route.collection("replies:" + id)); NavigationLink(tr("myForums"), value: Route.collection("forums:" + id)) }
        Section { Button(tr("blockUser"), role: .destructive) { app.updateLibrary { $0.addBlock(kind: "user", value: id, label: user.name) } } }
      }
      LoadState(loading: loading, error: error) { request = UUID() }
    }.navigationTitle(tr("profile")).task(id: request) { loading = true; defer { loading = false }; do { profile = try await app.api.profile(id) } catch { self.error = error.localizedDescription } }
      .sheet(isPresented: $editing) { if let profile { ProfileEditor(profile: profile) { editing = false; request = UUID() } } }
  }
}

struct ProfileEditor: View {
  let profile: UserProfile
  let saved: () -> Void
  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var intro = ""
  @State private var sex = 0
  @State private var item: PhotosPickerItem?
  @State private var avatar: UIImage?
  @State private var crop: UIImage?
  @State private var busy = false
  @State private var error: String?
  @State private var uncertain = false
  @State private var initialized = false
  var body: some View {
    NavigationStack {
      Form {
        Section { HStack { Spacer(); if let avatar { Image(uiImage: avatar).resizable().scaledToFill().frame(width: 90, height: 90).clipShape(Circle()) } else { Avatar(user: profile, size: 90) }; Spacer() }; PhotosPicker(selection: $item, matching: .images) { Label(tr("changeAvatar"), forumSymbol: "person.crop.circle") } }
        Section { TextField(tr("nickname"), text: $name); TextField(tr("intro"), text: $intro, axis: .vertical).lineLimit(3...8); Picker(tr("profileSex"), selection: $sex) { Text(tr("profileSexUnset")).tag(0); Text(tr("profileSexMale")).tag(1); Text(tr("profileSexFemale")).tag(2) } }
        if let error { Text(error).foregroundStyle(.red) }
        if uncertain { Button(tr("refresh")) { saved() } }
        if busy { ProgressView(tr("sending")) }
      }.disabled(busy).navigationTitle(tr("editProfile"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("cancel")) { dismiss() }.disabled(busy) }; ToolbarItem(placement: .confirmationAction) { Button(tr("save")) { Task { await save() } }.disabled(busy || uncertain || name.trimmingCharacters(in: .whitespaces).isEmpty) } }
        .task { guard !initialized else { return }; initialized = true; name = profile.name; intro = profile.intro; sex = integer(profile.raw["sex"]) }
        .onChange(of: item) { _, item in Task { if let bytes = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: bytes) { crop = image } } }
        .sheet(isPresented: Binding(get: { crop != nil }, set: { if !$0 { crop = nil } })) { if let crop { AvatarCrop(image: crop) { avatar = $0; self.crop = nil } } }
    }.interactiveDismissDisabled(busy)
  }
  private func save() async {
    guard app.activeID == profile.id else { error = tr("selectAccount"); return }; busy = true; defer { busy = false }
    var committed = false
    do {
      var fields: JSON = [:]
      if name != profile.name { fields["nick_name"] = name.trimmingCharacters(in: .whitespacesAndNewlines) }
      if intro != profile.intro { fields["intro"] = intro }
      if sex != integer(profile.raw["sex"]) && sex > 0 { fields["sex"] = sex }
      if !fields.isEmpty { try await app.api.updateProfile(fields); committed = true }
      if let avatar, let bytes = avatar.jpegData(compressionQuality: 0.9) { guard app.activeID == profile.id else { throw APIError(message: tr("selectAccount")) }; try await app.api.uploadPortrait(bytes); committed = true }
      saved()
    } catch { self.error = tr(committed ? "profilePartialSave" : "profileSaveUncertain") + "\n" + error.localizedDescription; uncertain = true }
  }
}
struct AvatarCrop: View {
  let image: UIImage
  let completion: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var scale: CGFloat = 1
  @State private var offset = CGSize.zero
  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text(tr("cropHint")).appFont(.subheadline).foregroundStyle(.secondary)
        Image(uiImage: image).resizable().scaledToFill().frame(width: 280, height: 280).scaleEffect(scale).offset(offset).frame(width: 280, height: 280).clipped().overlay(Rectangle().stroke(.blue, lineWidth: 2))
          .gesture(DragGesture().onChanged { value in offset = constrained(value.translation) })
        Slider(value: $scale, in: 1...3).padding(.horizontal, 30).onChange(of: scale) { _, _ in offset = constrained(offset) }
      }.navigationTitle(tr("cropAvatar")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("cancel")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(tr("done")) { completion(cropped()) } } }
    }
  }
  private func constrained(_ proposed: CGSize) -> CGSize {
    let factor = max(280 / image.size.width, 280 / image.size.height) * scale
    let x = max(0, (image.size.width * factor - 280) / 2), y = max(0, (image.size.height * factor - 280) / 2)
    return CGSize(width: min(x, max(-x, proposed.width)), height: min(y, max(-y, proposed.height)))
  }
  private func cropped() -> UIImage {
    let factor = max(512 / image.size.width, 512 / image.size.height) * scale
    let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in image.draw(in: CGRect(x: (512 - size.width) / 2 + offset.width * 512 / 280, y: (512 - size.height) / 2 + offset.height * 512 / 280, width: size.width, height: size.height)) }
  }
}
