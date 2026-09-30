import SwiftUI
import Security

enum L {
  private static let values: JSON = {
    guard let url = TiebaResources.bundle.url(forResource: "app_zh", withExtension: "arb"), let data = try? Data(contentsOf: url) else { return [:] }
    return object(try? JSONSerialization.jsonObject(with: data))
  }()
  static func text(_ key: String) -> String { string(values[key]).isEmpty ? key : string(values[key]) }
}
func tr(_ key: String) -> String { L.text(key) }

enum SecureAccounts {
  private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.sylar.forumlite.tieba.accounts", kSecAttrAccount as String: "tieba_lite.accounts.v1"] }
  static func read() throws -> JSON {
    var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return ["version": 1, "installId": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "accounts": [], "activeId": NSNull()] }
    guard status == errSecSuccess, let data = item as? Data, let json = try? JSONSerialization.jsonObject(with: data) as? JSON,
          integer(json["version"]) == 1, json["installId"] is String, json["accounts"] is [JSON] else { throw APIError(message: "Secure account storage could not be read. Existing data was preserved.") }
    let sessions = records(json["accounts"]).map { Session(raw: object($0["session"])) }
    let active = string(json["activeId"])
    guard sessions.allSatisfy(\.authenticated), Set(sessions.map(\.userID)).count == sessions.count,
          active.isEmpty || sessions.contains(where: { $0.userID == active }) else { throw APIError(message: "Secure account metadata is inconsistent. Existing data was preserved.") }
    return json
  }
  static func write(_ document: JSON) throws {
    let data = try JSONSerialization.data(withJSONObject: document)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var query = query; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw APIError(message: "Could not save the account securely.") }
    } else if status != errSecSuccess { throw APIError(message: "Could not update secure account storage.") }
  }
}

@MainActor final class Preferences: ObservableObject {
  @Published var revision = 0
  private let defaults = UserDefaults.standard
  private let prefix = "flutter.tieba_lite.settings."
  private let initial: JSON = ["themeMode": "system", "fontScale": 1.0, "customPrimaryColor": 0xFF007AFF,
    "homePageShowHistoryForum": true, "showTopForumInNormalList": true, "imageDarkenWhenNightMode": true,
    "showBlockTip": true, "loadPictureWhenScroll": true, "defaultSortType": "reply", "signSlowMode": true,
    "postOrReplyWarning": true, "imageLoadType": "0", "picWatermarkType": "2", "collectThreadSeeLz": true,
    "restoreReading": true, "listItemsBackgroundIntermixed": true, "showShortcutInThread": true, "radius": 16]
  func value(_ key: String) -> Any? { defaults.object(forKey: prefix + key) ?? defaults.object(forKey: String(prefix.dropFirst(8)) + key) ?? initial[key] }
  func flag(_ key: String) -> Bool { boolean(value(key)) }
  func text(_ key: String) -> String { string(value(key)) }
  func number(_ key: String) -> Double { (value(key) as? NSNumber)?.doubleValue ?? 0 }
  func set(_ key: String, _ value: Any) { defaults.set(value, forKey: prefix + key); revision += 1 }
  func toggle(_ key: String) -> Binding<Bool> { Binding(get: { self.flag(key) }, set: { self.set(key, $0) }) }
  func stringBinding(_ key: String) -> Binding<String> { Binding(get: { self.text(key) }, set: { self.set(key, $0) }) }
  var scheme: ColorScheme? { text("themeMode") == "dark" ? .dark : text("themeMode") == "light" ? .light : nil }
  var accent: Color { let n = UInt32(max(0, number("customPrimaryColor"))); return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255) }
  var fontScale: Double { min(2, max(0.75, number("fontScale"))) }
}

@MainActor final class AppState: ObservableObject {
  @Published private(set) var document: JSON = [:]
  @Published private(set) var library = LocalLibrary(document: [:])
  @Published var followed: [Forum] = []
  @Published var error: String?
  @Published var ready = false
  @Published var login = false
  @Published var accountEpoch = UUID()
  @Published var signing = false
  let settings = Preferences()
  private(set) var api: TiebaAPI!
  var sessions: [Session] { records(document["accounts"]).map { Session(raw: object($0["session"])) } }
  var activeID: String? { let value = string(document["activeId"]); return value.isEmpty ? nil : value }
  var session: Session? { sessions.first { $0.userID == activeID } }
  init() { initialize() }
  func initialize() {
    do {
      let data = try SecureAccounts.read()
      let active = string(data["activeId"])
      let local = try LocalLibrary.load(account: active.isEmpty ? nil : active)
      try SecureAccounts.write(data)
      document = data; library = local; ready = true
      let transport = TiebaTransport(deviceID: string(data["installId"])) { [weak self] in self?.session }
      api = TiebaAPI(transport: transport)
    } catch { self.error = error.localizedDescription }
  }
  func activate(_ id: String?) throws {
    guard ready, id == nil || sessions.contains(where: { $0.userID == id }) else { throw APIError(message: "Account unavailable.") }
    let local = try LocalLibrary.load(account: id)
    var data = document; data["activeId"] = id as Any? ?? NSNull()
    try SecureAccounts.write(data)
    document = data; library = local; followed = []; accountEpoch = UUID()
    api = TiebaAPI(transport: TiebaTransport(deviceID: string(data["installId"])) { [weak self] in self?.session })
  }
  func save(_ session: Session) throws {
    guard ready, session.authenticated else { throw APIError(message: "Sign-in was not validated.") }
    let local = try LocalLibrary.load(account: session.userID)
    var data = document
    data["accounts"] = records(data["accounts"]).filter { Session(raw: object($0["session"])).userID != session.userID } + [["profile": session.user.stored, "session": session.raw]]
    data["activeId"] = session.userID
    try SecureAccounts.write(data)
    document = data; library = local; followed = []; accountEpoch = UUID()
    api = TiebaAPI(transport: TiebaTransport(deviceID: string(data["installId"])) { [weak self] in self?.session })
  }
  func removeAccount(_ id: String) throws {
    if id == activeID { try activate(nil) }
    var data = document; data["accounts"] = records(data["accounts"]).filter { Session(raw: object($0["session"])).userID != id }
    try SecureAccounts.write(data); document = data
  }
  func updateLibrary(_ action: (inout LocalLibrary) -> Void) {
    guard ready else { return }
    do { var next = library; action(&next); try next.save(account: activeID); library = next }
    catch { self.error = error.localizedDescription }
  }
  func refreshForums() async throws {
    guard session != nil else { followed = []; return }
    let epoch = accountEpoch; let result = try await api.followedForums()
    guard epoch == accountEpoch else { return }
    followed = result
  }
  func sign(_ forum: Forum) async throws {
    let epoch = accountEpoch
    try await api.sign(forum)
    guard epoch == accountEpoch else { return }
    if let index = followed.firstIndex(where: { $0.id == forum.id }) { followed[index].signed = true }
  }
  func signAll() async {
    guard !signing else { return }
    signing = true; defer { signing = false }
    let epoch = accountEpoch
    do {
      try await refreshForums()
      if settings.flag("oksignUseOfficialOksign") {
        let ids = try await api.batchSign(followed)
        guard epoch == accountEpoch else { return }
        for index in followed.indices where ids.contains(followed[index].id) { followed[index].signed = true }
      }
      for forum in followed where !forum.signed {
        guard epoch == accountEpoch else { return }
        try await sign(forum)
        if settings.flag("signSlowMode") { try await Task.sleep(nanoseconds: 1_000_000_000) }
      }
      settings.set("signDay", DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))
    } catch { self.error = error.localizedDescription }
  }
  func requireLogin(_ action: () -> Void) { if session == nil { login = true } else { action() } }
}
