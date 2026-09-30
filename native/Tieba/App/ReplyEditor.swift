import SwiftUI
import PhotosUI
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum DraftFiles {
  static var folder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TiebaDrafts") }
  static func restore(_ path: String) -> URL? {
    let name = URL(fileURLWithPath: path).lastPathComponent
    guard name.range(of: "^[a-f0-9]{64}\\.(jpg|jpeg|png|gif|webp|heic|heif)$", options: .regularExpression) != nil else { return nil }
    let file = folder.appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: file.path) ? file : nil
  }
  static func retain(_ data: Data) throws -> URL {
    guard data.count <= 20 * 1024 * 1024, UIImage(data: data) != nil, let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else { throw APIError(message: tr("imageUnsupported")) }
    let ext = UTType(type as String)?.preferredFilenameExtension?.lowercased() ?? ""
    guard ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].contains(ext) else { throw APIError(message: tr("imageUnsupported")) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "." + ext
    let file = folder.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: file.path) { try data.write(to: file, options: .atomic) }
    return file
  }
  static func upload(_ file: URL) throws -> (Data, Int, Int) {
    let data = try Data(contentsOf: file)
    guard let image = UIImage(data: data) else { throw APIError(message: tr("imageUnsupported")) }
    var output = image
    if data.count > 5 * 1024 * 1024 {
      let factor = min(1, 1920 / max(image.size.width, image.size.height))
      let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      output = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    let bytes = data.count > 5 * 1024 * 1024 ? output.jpegData(compressionQuality: 0.9) ?? data : data
    return (bytes, output.cgImage?.width ?? Int(output.size.width), output.cgImage?.height ?? Int(output.size.height))
  }
  static func sentKey(account: String?, draft: String) -> String { "tieba.native.sentDraft." + (account ?? "guest") + "." + draft }
  static func wasSent(account: String?, draft: String) -> Bool { UserDefaults.standard.bool(forKey: sentKey(account: account, draft: draft)) }
}

struct ReplyEditor: View {
  let context: ReplyContext
  let sent: () -> Void
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var attachments: [URL] = []
  @State private var picked: [PhotosPickerItem] = []
  @State private var busy = false
  @State private var importing = false
  @State private var initialized = false
  @State private var account: String?
  @State private var original = false
  @State private var progress = 0
  @State private var confirmation = false
  @State private var leaving = false
  @State private var completed = false
  @State private var emoticons = false
  @State private var failure: String?
  private var key: String { string(context.restored?["key"]).isEmpty ? context.id : string(context.restored?["key"]) }
  var body: some View {
    NavigationStack {
      Form {
        Section(context.forum.name) { TextEditor(text: $text).frame(minHeight: 180).tiebaFont(.body) }
        if !attachments.isEmpty {
          Section {
            ScrollView(.horizontal) { HStack { ForEach(attachments, id: \.self) { file in
              VStack { if let image = UIImage(contentsOfFile: file.path) { Image(uiImage: image).resizable().scaledToFill().frame(width: 80, height: 80).clipped() }; Button(tr("removeImage"), role: .destructive) { attachments.removeAll { $0 == file } }.tiebaFont(.caption) }
            } } }
          }
        }
        Section {
          PhotosPicker(selection: $picked, maxSelectionCount: max(1, 9 - attachments.count), matching: .images) { Label(tr("attachImages"), systemImage: "photo.on.rectangle") }.disabled(attachments.count >= 9 || busy || importing)
          Button(tr("emoticons"), systemImage: "face.smiling") { emoticons = true }
          Toggle(tr("originalImage"), isOn: $original)
        }
        if busy { HStack { ProgressView(); Text("\(tr("sendingImages")) \(progress)/\(attachments.count)") } }
      }.navigationTitle(tr("reply")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(tr("cancel")) { if text.isEmpty && attachments.isEmpty { dismiss() } else { leaving = true } }.disabled(busy) }
          ToolbarItem(placement: .confirmationAction) { Button(tr("send")) { if settings.flag("postOrReplyWarning") { confirmation = true } else { Task { await send() } } }.disabled(busy || importing || completed || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)) }
        }
        .interactiveDismissDisabled(!text.isEmpty || !attachments.isEmpty || busy)
        .confirmationDialog(tr("replyWarning"), isPresented: $confirmation, titleVisibility: .visible) { Button(tr("send")) { Task { await send() } } }
        .confirmationDialog(tr("leaveDraftTitle"), isPresented: $leaving, titleVisibility: .visible) {
          Button(tr("saveDraft")) { save(); dismiss() }
          Button(tr("discard"), role: .destructive) { if account == app.activeID { app.updateLibrary { $0.removeDraft(key) } }; dismiss() }
        }
        .task {
          guard !initialized else { return }; initialized = true; account = app.activeID; original = settings.flag("originalImages")
          if !DraftFiles.wasSent(account: account, draft: key), let draft = context.restored ?? app.library.rows("drafts").first(where: { string($0["key"]) == key }) {
            text = string(draft["content"]); attachments = (draft["imagePaths"] as? [String] ?? []).compactMap(DraftFiles.restore)
          }
        }
        .onChange(of: picked) { _, selection in Task { @MainActor in
          importing = true; defer { importing = false; picked = [] }
          do { for item in selection { if attachments.count >= 9 { break }; if let data = try await item.loadTransferable(type: Data.self) { let file = try DraftFiles.retain(data); if !attachments.contains(file) { attachments.append(file) } } } }
          catch { failure = error.localizedDescription }
        } }
        .sheet(isPresented: $emoticons) {
          NavigationStack {
            ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 14) {
              ForEach(Emoticons.catalog.keys.sorted { (Int($0.dropFirst(14)) ?? 0) < (Int($1.dropFirst(14)) ?? 0) }, id: \.self) { id in
                Button { text += "#(\(Emoticons.catalog[id] ?? ""))" } label: {
                  VStack { if let image = Emoticons.image(id) { Image(uiImage: image).resizable().scaledToFit() } else { AsyncImage(url: URL(string: "https://tieba.baidu.com/tb/editor/images/client/\(id).png")) { $0.resizable().scaledToFit() } placeholder: { ProgressView() } } }.frame(width: 32, height: 32)
                }.accessibilityLabel(Emoticons.catalog[id] ?? id)
              }
            }.padding() }.navigationTitle(tr("emoticons")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("done")) { emoticons = false } } }
          }.presentationDetents([.medium, .large])
        }
    }.alert(tr("operationFailed"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button(tr("done")) { failure = nil } } message: { Text(failure ?? "") }
  }
  private func save() {
    guard !completed, account == app.activeID else { return }
    UserDefaults.standard.set(false, forKey: DraftFiles.sentKey(account: account, draft: key))
    app.updateLibrary { $0.saveDraft(["key": key, "threadId": context.thread, "forumName": context.forum.name, "content": text, "imagePaths": attachments.map(\.path), "parentPostId": context.parent, "targetSubPostId": context.subpost, "replyUserId": context.replyUser, "updatedAt": ISO8601DateFormatter().string(from: Date())]) }
  }
  private func send() async {
    guard !busy, !completed else { return }
    busy = true; defer { busy = false }
    do {
      guard account != nil, account == app.activeID else { throw APIError(message: tr("selectAccount")) }
      save()
      var content = text
      for (index, file) in attachments.enumerated() {
        guard account == app.activeID else { throw APIError(message: tr("selectAccount")) }
        progress = index + 1
        let (data, width, height) = try DraftFiles.upload(file)
        let image = try await app.api.uploadImage(data, width: width, height: height, forum: context.forum.name, watermark: Int(settings.text("picWatermarkType")) ?? 2, original: original)
        content += "#(pic,\(string(image["pictureId"])),\(width),\(height))"
      }
      if !settings.text("littleTail").isEmpty { content += "\n" + settings.text("littleTail") }
      guard account == app.activeID else { throw APIError(message: tr("selectAccount")) }
      _ = try await app.api.reply(content: content, forum: context.forum, thread: context.thread, parent: context.parent, subpost: context.subpost, replyUser: context.replyUser)
      completed = true
      UserDefaults.standard.set(true, forKey: DraftFiles.sentKey(account: account, draft: key))
      if account == app.activeID { app.updateLibrary { $0.removeDraft(key) } }
      sent()
    } catch { failure = error.localizedDescription }
  }
}

struct DraftsView: View {
  @EnvironmentObject private var app: AppState
  @State private var selection: ReplyContext?
  @State private var opening = false
  private var drafts: [JSON] { app.library.rows("drafts").filter { !DraftFiles.wasSent(account: app.activeID, draft: string($0["key"])) } }
  var body: some View {
    List {
      ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
        Button { Task { @MainActor in
          opening = true; defer { opening = false }
          do { let result = try await app.api.forum(string(draft["forumName"])); selection = ReplyContext(thread: string(draft["threadId"]), forum: result.forum ?? Forum(), parent: string(draft["parentPostId"]), subpost: string(draft["targetSubPostId"]), replyUser: string(draft["replyUserId"]), restored: draft) }
          catch { app.error = error.localizedDescription }
        } } label: { VStack(alignment: .leading, spacing: 6) { Text(string(draft["forumName"])).tiebaFont(.caption).foregroundStyle(.secondary); Text(string(draft["content"])).lineLimit(3) } }.disabled(opening)
          .swipeActions { Button(tr("discard"), role: .destructive) { app.updateLibrary { $0.removeDraft(string(draft["key"])) } } }
      }
      if drafts.isEmpty { ContentUnavailableView(tr("emptyDrafts"), systemImage: "doc") }
    }.navigationTitle(tr("drafts")).sheet(item: $selection) { ReplyEditor(context: $0) { selection = nil } }
  }
}
