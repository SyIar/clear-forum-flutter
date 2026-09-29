import Foundation

extension ForumPage {
  // The server returns full HTML. Keep unchanged reader blocks alive when a
  // purchase replaces its gate with content, including blocks after the gate.
  func preservingPurchaseContent(from previous: ForumPage) -> ForumPage {
    guard kind == .posts, previous.kind == .posts,
          SitePolicy.pageCacheKey(url) == SitePolicy.pageCacheKey(previous.url) else { return self }
    var result = self
    let existing = Dictionary(previous.posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for index in result.posts.indices {
      guard let post = existing[result.posts[index].id] else { continue }
      result.posts[index] = result.posts[index].preservingBodyIdentity(from: post)
    }
    return result
  }
}

extension ForumPost {
  func preservingBodyIdentity(from previous: ForumPost) -> ForumPost {
    guard id == previous.id else { return self }
    var result = self
    result.blocks = BodyBlock.reusingUnchanged(blocks, from: previous.blocks)
    return result
  }
}

private extension BodyBlock {
  func sameShell(as other: BodyBlock) -> Bool {
    kind == other.kind && runs == other.runs && label == other.label && url == other.url &&
      poster == other.poster && original == other.original && aspectRatio == other.aspectRatio &&
      direct == other.direct && purchase == other.purchase
  }
  func sameContent(as other: BodyBlock) -> Bool {
    sameShell(as: other) && children.count == other.children.count &&
      zip(children, other.children).allSatisfy { $0.sameContent(as: $1) }
  }
  static func reusingUnchanged(_ fresh: [BodyBlock], from old: [BodyBlock]) -> [BodyBlock] {
    var result = fresh
    var start = 0
    while start < min(fresh.count, old.count), fresh[start].sameContent(as: old[start]) {
      result[start] = old[start]
      start += 1
    }
    var freshEnd = fresh.count
    var oldEnd = old.count
    while freshEnd > start, oldEnd > start, fresh[freshEnd - 1].sameContent(as: old[oldEnd - 1]) {
      freshEnd -= 1; oldEnd -= 1
      result[freshEnd] = old[oldEnd]
    }
    // Preserve a surrounding quote/spoiler when only its nested body changed.
    if freshEnd - start == 1, oldEnd - start == 1, fresh[start].sameShell(as: old[start]) {
      result[start] = old[start]
      result[start].children = reusingUnchanged(fresh[start].children, from: old[start].children)
    }
    return result
  }
}
