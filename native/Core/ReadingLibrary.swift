import Foundation

struct SavedPage: Codable, Identifiable, Equatable {
  var id: String { url.absoluteString }
  var url: URL
  var title: String
}
struct LibraryDocument: Codable {
  var version = 1
  var bookmarks: [SavedPage] = []
  var recent: [SavedPage] = []
  static let key = "reading_library_v1"
  static func load(from defaults: UserDefaults) throws -> LibraryDocument {
    guard let raw = defaults.string(forKey: key) ?? defaults.string(forKey: "flutter." + key) else { return LibraryDocument() }
    guard let data = raw.data(using: .utf8), var document = try? JSONDecoder().decode(Self.self, from: data), document.version == 1 else { throw ReaderFailure.storage }
    func unique(_ entries: [SavedPage], key: (URL) -> String) -> [SavedPage] {
      var seen = Set<String>()
      return entries.filter { SitePolicy.readable($0.url) && seen.insert(key($0.url)).inserted }
    }
    document.bookmarks = unique(document.bookmarks) { $0.absoluteString }
    document.recent = Array(unique(document.recent, key: recentKey).prefix(10))
    return document
  }
  func save(to defaults: UserDefaults) throws {
    let data = try JSONEncoder().encode(self)
    defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.key)
  }
  static func recentKey(_ url: URL) -> String {
    let components = url.path.split(separator: "/")
    if components.count >= 2 && components[0] == "threads" { return "/threads/\(components[1])/" }
    return SitePolicy.withoutFragment(url).absoluteString
  }
  mutating func remember(_ page: SavedPage) {
    guard SitePolicy.readable(page.url) else { return }
    recent.removeAll { Self.recentKey($0.url) == Self.recentKey(page.url) }
    recent.insert(page, at: 0)
    recent = Array(recent.prefix(10))
  }
  mutating func toggle(_ page: SavedPage) {
    guard SitePolicy.readable(page.url) else { return }
    if bookmarks.contains(where: { $0.url == page.url }) { bookmarks.removeAll { $0.url == page.url } }
    else { bookmarks.append(page) }
  }
}
