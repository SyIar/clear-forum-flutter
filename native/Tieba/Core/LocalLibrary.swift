import Foundation

struct LocalLibrary {
  var document: JSON
  static let prefix = "tieba_lite.local.v1."
  static func key(account: String?) -> String {
    let namespace = account.map { Data($0.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") } ?? "guest"
    return "flutter." + prefix + namespace
  }
  static func load(account: String?, defaults: UserDefaults = .standard) throws -> Self {
    let key = key(account: account)
    guard let stored = defaults.string(forKey: key) ?? defaults.string(forKey: String(key.dropFirst(8))) else {
      return Self(document: ["version": 1, "history": [], "pins": [], "search": [], "blocks": [], "drafts": [], "recentForums": [], "forumHistory": []])
    }
    guard let bytes = stored.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: bytes) as? JSON, integer(value["version"]) == 1,
          ["history", "pins", "search", "blocks", "drafts"].allSatisfy({ value[$0] is [Any] }),
          ["recentForums", "forumHistory"].allSatisfy({ value[$0] == nil || value[$0] is [Any] }) else { throw APIError(message: "Local data could not be read. It has been preserved.") }
    var migrated = value
    if migrated["forumHistory"] == nil { migrated["forumHistory"] = records(value["recentForums"]).map { ["forum": $0] } }
    migrated["recentForums"] = Array(records(value["recentForums"]).prefix(5))
    return Self(document: migrated)
  }
  func save(account: String?, defaults: UserDefaults = .standard) throws {
    let bytes = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    defaults.set(String(decoding: bytes, as: UTF8.self), forKey: Self.key(account: account))
  }
  func rows(_ key: String) -> [JSON] { records(document[key]) }
  var recentForums: [Forum] { rows("recentForums").map { Forum(raw: $0) } }
  var pins: [Forum] { rows("pins").map { Forum(raw: $0) } }
  mutating func visit(_ forum: Forum) {
    guard !forum.name.isEmpty else { return }
    var recent = rows("recentForums")
    if let index = recent.firstIndex(where: { Forum(raw: $0).name == forum.name }) { recent[index] = forum.stored }
    else { recent.insert(forum.stored, at: 0) }
    document["recentForums"] = Array(recent.prefix(5))
    var history = rows("forumHistory").filter { Forum(raw: object($0["forum"])).name != forum.name }
    history.insert(["forum": forum.stored, "visitedAt": ISO8601DateFormatter().string(from: Date())], at: 0)
    document["forumHistory"] = Array(history.prefix(1000))
  }
  mutating func remember(thread: String, title: String, forum: String, post: String, page: Int, onlyAuthor: Bool) {
    var history = rows("history").filter { string($0["threadId"]) != thread }
    history.insert(["threadId": thread, "title": title, "forumName": forum, "lastPostId": post, "page": page, "onlyAuthor": onlyAuthor, "visitedAt": ISO8601DateFormatter().string(from: Date())], at: 0)
    document["history"] = Array(history.prefix(1000))
  }
  mutating func togglePin(_ forum: Forum) {
    var values = rows("pins")
    if let index = values.firstIndex(where: { Forum(raw: $0).name == forum.name }) { values.remove(at: index) }
    else { values.insert(forum.stored, at: 0) }
    document["pins"] = values
  }
  mutating func search(_ query: String) {
    document["search"] = Array(([query] + (document["search"] as? [String] ?? []).filter { $0 != query }).prefix(100))
  }
  mutating func saveDraft(_ draft: JSON) {
    let key = string(draft["key"])
    document["drafts"] = [draft] + rows("drafts").filter { string($0["key"]) != key }
  }
  mutating func removeDraft(_ key: String) { document["drafts"] = rows("drafts").filter { string($0["key"]) != key } }
  mutating func addBlock(kind: String, value: String, label: String, allow: Bool = false) {
    var rules = rows("blocks").filter { !(string($0["kind"]) == kind && string($0["value"]) == value) }
    rules.append(["kind": kind, "value": value, "label": label, "allow": allow, "keywords": kind == "keyword" ? value.split(separator: " ").map(String.init) : []])
    document["blocks"] = rules
  }
  func blocked(user: UserProfile = UserProfile(), forum: String = "", thread: String = "", text: String = "", extraText: String = "") -> Bool {
    func matches(_ rule: JSON) -> Bool {
      let value = string(rule["value"])
      guard !value.isEmpty else { return false }
      switch string(rule["kind"]) {
      case "user": return value == user.id || value == user.username
      case "forum": return value == forum
      case "thread": return value == thread
      case "keyword":
        let words = rule["keywords"] as? [String] ?? [value]
        return !words.isEmpty && (words.allSatisfy { text.contains($0) } || words.allSatisfy { extraText.contains($0) })
      default: return false
      }
    }
    let matched = rows("blocks").filter(matches)
    return matched.contains { deny in !boolean(deny["allow"]) && !matched.contains { boolean($0["allow"]) && string($0["kind"]) == string(deny["kind"]) } }
  }
}
