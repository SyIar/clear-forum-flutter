import Foundation

// A depth-first work list. A failed item remains at the head until retried or skipped.
struct GofileBatchPlan {
  struct Item: Identifiable {
    let id = UUID()
    let entry: GofileEntry
    let path: [String]
    var page = 1
  }
  private(set) var pending: [Item] = []
  private var files = Set<String>()
  private var folders = Set<String>()
  private var folderPages = Set<String>()
  private var paths = Set<String>()
  private(set) var discovered = 0
  var next: Item? { pending.last }
  init(listing: GofileListing) throws {
    folders.insert(listing.id)
    try append(listing.entries, parent: [])
  }
  mutating func advance() { _ = pending.popLast() }
  mutating func expand(_ listing: GofileListing) throws {
    guard let item = next, item.entry.folder else { return }
    let key = "\(listing.id):\(listing.page)"
    guard !folderPages.contains(key) else { advance(); return }
    // Detect aliases and cycles, while allowing subsequent pages of the same folder.
    if listing.page == 1 && listing.id != item.entry.id && folders.contains(listing.id) { advance(); return }
    guard item.path.count <= 32, discovered + listing.entries.count <= 10000 else {
      throw GofileBatchError.limit
    }
    advance(); folders.insert(listing.id); folderPages.insert(key)
    if listing.page < listing.pages {
      var following = item; following.page = listing.page + 1; pending.append(following)
    }
    try append(listing.entries, parent: item.path)
  }
  private mutating func append(_ entries: [GofileEntry], parent: [String]) throws {
    guard discovered + entries.count <= 10000 else { throw GofileBatchError.limit }
    var items: [Item] = []
    for entry in entries {
      if entry.folder {
        guard folders.insert(entry.id).inserted else { continue }
      } else {
        guard files.insert(entry.id).inserted else { continue }
      }
      discovered += 1
      let name = GofilePolicy.filename(entry.name)
      let ext = (name as NSString).pathExtension
      let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
      var candidate = name
      var suffix = 1
      while !paths.insert((parent + [candidate]).joined(separator: "/").lowercased()).inserted {
        suffix += 1
        candidate = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
      }
      items.append(Item(entry: entry, path: parent + [candidate]))
    }
    pending.append(contentsOf: items.reversed())
  }
}

enum GofileBatchError: Error, LocalizedError {
  case limit
  var errorDescription: String? { AppText.text("This batch reached 10,000 items or 32 folder levels. Download the remaining folders separately.") }
}
