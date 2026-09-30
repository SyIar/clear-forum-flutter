import Foundation
import SwiftSoup

// PHPWind post structure verified against user-supplied South HTML.
struct SouthForumParser {
  private let unwanted = "script,style,object,embed,textarea,select,svg,noscript,.adsbygoogle,.advertisement,.ad-container,.adContainer,.ad-block,.sponsor,[data-ad],[data-ad-slot],[hidden]"
  private func text(_ node: Element?) -> String { (try? node?.text()) ?? "" }
  private func first(_ root: Element, _ selector: String) -> Element? { try? root.select(selector).first() }
  private func attr(_ node: Element?, _ name: String) -> String { (try? node?.attr(name)) ?? "" }
  private func links(_ root: Element, _ selector: String = "a[href]") -> [Element] { (try? root.select(selector).array()) ?? [] }
  private func target(_ node: Element?, page: URL) -> URL? { SouthSitePolicy.resolve(attr(node, "href"), from: page, internalOnly: true) }

  func parse(_ source: String, url: URL, status: Int = 200) throws -> ForumPage {
    guard SouthSitePolicy.readable(url) else { throw ReaderFailure.unsupported }
    if status == 429 { throw ReaderFailure.rateLimit }
    if status == 401 { throw ReaderFailure.login }
    let doc = try SwiftSoup.parse(source)
    let pageTitle = text(first(doc, "title"))
    let lowerTitle = pageTitle.lowercased()
    if first(doc, "#challenge-running,#challenge-form,.cf-turnstile") != nil || lowerTitle.contains("just a moment") || lowerTitle.contains("attention required") { throw ReaderFailure.verification }
    if status == 403 { throw ReaderFailure.forbidden }
    guard (200..<300).contains(status) else { throw ReaderFailure.network }
    let bodies = postBodies(doc)
    let hasLoginForm = first(doc, "form[action*=login] input[type=password],form input[name=pwpwd]") != nil
    let logout = links(doc).contains { link in
      guard let candidate = SouthSitePolicy.resolve(attr(link, "href"), from: url), SouthSitePolicy.sameOrigin(candidate) else { return false }
      return candidate.path == "/login.php" && (candidate.query?.contains("quit") == true || candidate.query?.contains("logout") == true)
    }
    let loggedIn: Bool? = logout ? true : hasLoginForm ? false : nil
    if bodies.isEmpty, hasLoginForm, first(doc, "#ajaxtable,.thread-list,#threadlist,#u-contentmain .u-table") == nil { throw ReaderFailure.login }
    if first(doc, ".error-message,[data-access-denied],#permission-denied") != nil { throw ReaderFailure.forbidden }
    try doc.select(unwanted).remove()

    var breadcrumbs: [ForumEntry] = []
    if let trail = first(doc, "#breadCrumb,#bread-crumb,.breadcrumb,.breadcrumbs,#breadcrumbs") {
      var seen = Set<String>()
      for anchor in links(trail) {
        if let link = target(anchor, page: url), !text(anchor).isEmpty, seen.insert(SouthSitePolicy.pageCacheKey(link)).inserted {
          breadcrumbs.append(ForumEntry(title: text(anchor), url: link))
        }
      }
    }
    let thread = SouthSitePolicy.isThread(url)
    let topicAuthorID = SouthSitePolicy.topicAuthorID(url)
    var posts: [ForumPost] = []
    if thread {
      var seen = Set<String>()
      for body in bodies {
        let container = body.parents().first { $0.hasClass("js-post") } ?? body.parents().first { parent in
          parent.tagName() == "tr" || parent.tagName() == "article" || parent.hasClass("post") || parent.hasClass("read_t")
        } ?? body.parent() ?? body
        let id = body.id().isEmpty ? "post-\(posts.count)" : body.id().replacingOccurrences(of: "read_", with: "post_")
        guard seen.insert(id).inserted else { continue }
        let identity = postAuthor(container, page: url)
        let date = postDate(container)
        let floor = floorNumber(container, body: body)
        let blocks = try SouthBodyParser().parseBody(body, page: url)
        guard !blocks.isEmpty else { continue }
        posts.append(ForumPost(id: id, author: identity.name.isEmpty ? AppText.text("Member") : identity.name, date: date,
                              number: floor.map { "#\($0)" } ?? "", blocks: blocks, authorID: identity.id, avatar: identity.avatar, avatarOriginal: identity.original,
                              authorFilterURL: authorFilter(container, page: url, authorID: identity.id)))
      }
      guard !posts.isEmpty else { throw ReaderFailure.unsupported }
    }

    var entries: [ForumEntry] = []
    var seenEntries = Set<String>()
    if !thread {
      if topicAuthorID != nil, first(doc, "#u-contentmain .u-table") == nil { throw ReaderFailure.unsupported }
      let root = topicAuthorID != nil ? first(doc, "#u-contentmain")! : (first(doc, "#ajaxtable,#threadlist,.thread-list,#main") ?? doc)
      // Title selectors take precedence over last-reply and per-row page links.
      let preferred = links(root, "h3 a[href],.subject a[href],a.subject[href],a[id^=a_ajax_],.thread-title a[href]")
      for anchor in preferred + links(root) {
        guard let link = target(anchor, page: url), SouthSitePolicy.isThread(link), !text(anchor).isEmpty,
              anchor.parents().allSatisfy({ !$0.hasClass("pages") && $0.id() != "breadCrumb" }),
              let row = anchor.parents().first(where: { $0.tagName() == "tr" || $0.hasClass("thread-row") || $0.tagName() == "article" }),
              seenEntries.insert(SouthSitePolicy.threadKey(link) ?? link.absoluteString).inserted else { continue }
        let authorLinks = links(row, ".author a[href],a.author[href],.username[href],a[href*=u.php]").filter { profileID($0, page: url) != nil }
        let authorID = topicAuthorID ?? authorLinks.first.flatMap { profileID($0, page: url) }
        let authorLink = authorLinks.first { profileID($0, page: url) == authorID && !text($0).isEmpty }
        let author = topicAuthorID != nil ? text(first(doc, "#u-top .u-h1")) : text(authorLink ?? first(row, ".author,.username"))
        let subtitle = topicAuthorID != nil ? [text(first(row, "a.gray")), text(first(row, "span.f9"))].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ") : author
        let pinned = row.hasClass("sticky") || row.hasClass("pinned") || first(row, "img[src*=headtopic],img[src*=top1],img[src*=top2],img[src*=top3],[data-sticky=true]") != nil
        entries.append(ForumEntry(title: text(anchor), url: link, subtitle: subtitle, pinned: pinned,
                                  thumbnail: thumbnail(first(row, ".thread-thumbnail,.thumbnail,[data-cover]"), page: url),
                                  tags: tags(row, page: url), authorID: authorID, authorName: author.isEmpty ? nil : author,
                                  postedAt: entryDate(row, author: authorLink, authorTopics: topicAuthorID != nil),
                                  totalPostCount: entryPostCount(row)))
      }
      if entries.isEmpty, SouthSitePolicy.route(url)?.path == "/index.php" {
        for anchor in links(root, "h2 a[href],h3 a[href],.forum-name a[href],a.forum-name[href]") {
          guard let link = target(anchor, page: url), SouthSitePolicy.route(link)?.path == "/thread.php", !text(anchor).isEmpty,
                seenEntries.insert(SouthSitePolicy.pageCacheKey(link)).inserted else { continue }
          entries.append(ForumEntry(title: text(anchor), url: link))
        }
      }
      // Unknown markup must not look like a successfully loaded empty forum.
      if entries.isEmpty, topicAuthorID == nil, first(doc, "[data-empty-forum=true],.thread-list-empty") == nil { throw ReaderFailure.unsupported }
    }

    let navigation = links(doc, ".pages a[href],.pagination a[href],.page-nav a[href],a[rel=next],a[rel=prev],a[rel=last],link[rel=next],link[rel=prev],link[rel=last]").filter(isPageNavigation)
    let pageLinks = navigation.compactMap { target($0, page: url) }.filter { SouthSitePolicy.pageRoot($0) == SouthSitePolicy.pageRoot(url) }
    let number = SouthSitePolicy.pageNumber(url)
    let declaredTotals = paginationTotals(doc, currentPage: number)
    let knownCount = (pageLinks.map(SouthSitePolicy.pageNumber) + declaredTotals + [number]).max() ?? number
    let last = pageLinks.first { SouthSitePolicy.pageNumber($0) == knownCount } ??
      (knownCount > number || declaredTotals.contains(knownCount) ? SouthSitePolicy.pageURL(url, number: knownCount) : nil)
    let next = pageLinks.first { SouthSitePolicy.pageNumber($0) == number + 1 } ?? (knownCount > number ? SouthSitePolicy.pageURL(url, number: number + 1) : nil)
    let previous = pageLinks.first { SouthSitePolicy.pageNumber($0) == number - 1 } ?? (number > 1 ? SouthSitePolicy.pageURL(url, number: number - 1) : nil)
    // A missing pager is not proof that this is the last page.
    let explicitLast = navigation.contains { node in
      guard attr(node, "rel").split(separator: " ").contains("last"), let link = target(node, page: url) else { return false }
      return SouthSitePolicy.pageRoot(link) == SouthSitePolicy.pageRoot(url) && SouthSitePolicy.pageNumber(link) == number
    }
    // An author's final reply is not the thread's latest floor.
    let maximumIsKnown = thread && SouthSitePolicy.authorID(url) == nil && next == nil && (declaredTotals.contains(number) || explicitLast)
    let maximum = maximumIsKnown ? posts.compactMap { Int($0.number.dropFirst()) }.max() : nil
    let heading = first(doc, thread ? "#subject_tpc,h1.thread-title,h1" : "h1,.forum-title,#thread-title")
    let fallbackTitle = breadcrumbs.last?.title ?? pageTitle.components(separatedBy: " - ").first ?? AppText.text("Forum")
    let authorName = text(first(doc, "#u-top .u-h1"))
    let title = topicAuthorID != nil ? (authorName.isEmpty ? AppText.text("Author threads") : AppText.format("%@ - Threads", String(describing: authorName))) : (text(heading).isEmpty ? fallbackTitle : text(heading))
    let kind: PageKind = thread ? .posts : (SouthSitePolicy.route(url)?.path == "/index.php" ? .forums : .threads)
    return ForumPage(url: url, title: title.isEmpty ? AppText.text("Forum") : title, kind: kind, entries: entries, posts: posts,
                     previous: previous, next: next, pageNumber: number, loggedIn: loggedIn,
                     lastPage: last, maximumPostNumber: maximum, breadcrumbs: breadcrumbs,
                     tags: tags(heading, page: url), totalPages: knownCount, poll: SouthPollParser.parse(doc, page: url))
  }

  // Do not borrow a last-reply timestamp for the thread's creation time.
  private func entryDate(_ row: Element, author: Element?, authorTopics: Bool) -> String? {
    let authorCell = author?.parents().first { $0.tagName() == "td" || $0.tagName() == "th" }
    let candidates = authorTopics ? links(row, "span.f9,time") :
      links(row, "[data-posted-at],.posted-at,.creation-date") +
      (authorCell.map { links($0, "time,.f10,.post-date,.post-time") } ?? [])
    for node in candidates {
      for value in [attr(node, "data-posted-at"), attr(node, "datetime"), text(node), attr(node, "title")] {
        if let date = match(value, #"(?:^|\s)([0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:[ T][0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?(?:Z|[+-][0-9]{2}:[0-9]{2})?)?)(?:$|\s)"#) { return date }
      }
    }
    return nil
  }
  private func entryPostCount(_ row: Element) -> Int? {
    func number(_ value: String) -> Int? {
      guard match(value, #"^([0-9]{1,9})$"#) != nil else { return nil }
      return Int(value)
    }
    for node in [row] + links(row, "[data-post-count],.post-count") {
      if let count = number(attr(node, "data-post-count")), count > 0 { return count }
      if node.hasClass("post-count"), let count = number(text(node)), count > 0 { return count }
    }
    for node in [row] + links(row, "[data-reply-count],.reply-count") {
      if let count = number(attr(node, "data-reply-count")) { return count + 1 }
      if node.hasClass("reply-count"), let count = number(text(node)) { return count + 1 }
    }
    for cell in row.children().array() where cell.tagName() == "td" || cell.tagName() == "th" {
      guard first(cell, "h3,.subject,.thread-title,a[href*=read.php],a[href*=u.php]") == nil else { continue }
      // Compatibility for a compact replies/views cell. A bare number, page link or view
      // count alone cannot establish the number of posts.
      if cell.hasClass("f10"), first(cell, "span.s3,span.s8") != nil,
         let value = match(text(cell), #"^\s*([0-9]{1,9})\s*/\s*[0-9]{1,12}\s*$"#), let replies = number(value) { return replies + 1 }
      if let value = match(text(cell), #"(?i)^\s*([0-9]{1,9})\s*(?:replies|\u56de\u590d)(?:\s|$)"#), let replies = number(value) { return replies + 1 }
    }
    return nil
  }
  private func isPageNavigation(_ node: Element) -> Bool {
    !node.parents().contains {
      $0.hasClass("js-post") || $0.hasClass("tpc_content") || $0.hasAttr("data-post-body") ||
      $0.tagName() == "blockquote" || $0.hasClass("blockquote")
    }
  }
  private func paginationTotals(_ root: Element, currentPage: Int) -> [Int] {
    let pager = ".pages,.pagination,.page-nav"
    let roots = links(root, pager).filter(isPageNavigation)
    let declared = roots + roots.flatMap { links($0, "[data-total-pages],input[name=page],input[name=jump_page]") }
    var totals = declared.compactMap { Int(attr($0, "data-total-pages")) ?? Int(attr($0, "max")) }
      .filter { (currentPage...99_999).contains($0) }
    // The same PHPWind pagesone label is already used by South search pages.
    // Read only its explicit current/total pair, never an arbitrary page body
    // number or an event handler. Invalid/stale current-page labels are ignored.
    for node in links(root, ".pagesone").filter(isPageNavigation) {
      let label = text(node)
      guard let declaredCurrent = match(label, #"(?i)^\s*Pages:\s*([0-9]{1,5})/[0-9]{1,5}(?:\s+Go)?\s*$"#).flatMap(Int.init),
            declaredCurrent == currentPage,
            let total = match(label, #"(?i)^\s*Pages:\s*[0-9]{1,5}/([0-9]{1,5})(?:\s+Go)?\s*$"#).flatMap(Int.init),
            (currentPage...99_999).contains(total) else { continue }
      totals.append(total)
    }
    return totals
  }

  private func match(_ value: String, _ pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          let range = Range(result.range(at: 1), in: value) else { return nil }
    return String(value[range])
  }
  private func postBodies(_ root: Element) -> [Element] {
    func identified(_ node: Element) -> Bool { match(node.id(), #"^read_(tpc|[0-9]+)$"#) != nil }
    let identifiedBodies = links(root, "[id^=read_]").filter { node in
      identified(node) && (node.hasClass("tpc_content") || node.parents().contains { $0.hasClass("tpc_content") || $0.hasClass("js-post") }) &&
        !node.parents().contains(where: identified)
    }
    if !identifiedBodies.isEmpty { return identifiedBodies }
    // Compatibility for explicit body markers and older, unidentified post markup.
    return links(root, ".tpc_content:not([id]),[data-post-body]").filter { node in
      !node.parents().contains { $0.hasClass("tpc_content") || $0.hasAttr("data-post-body") }
    }
  }
  private func postAuthor(_ container: Element, page: URL) -> (name: String, id: String?, avatar: URL?, original: URL?) {
    let root = first(container, "th.r_two,td.r_two,.post-author,.author-info") ?? container
    let profiles = links(root, "a[href*=u.php]").filter { profileID($0, page: page) != nil }
    // The first profile link wraps the avatar and has no text. Prefer the name link.
    let nameLink = profiles.first { !text($0).isEmpty && first($0, "strong,b") != nil } ?? profiles.first {
      !text($0).isEmpty && !$0.parents().contains { $0.hasClass("user-info") }
    }
    let explicitName = links(root, ".author,.user-name,.username,.readName").first { !text($0).isEmpty }
    let metadata = first(container, ".tiptop [data-uid][data-name]")
    let name = [text(nameLink), text(explicitName), attr(metadata, "data-name")].first { !$0.isEmpty } ?? ""
    let id = (nameLink ?? profiles.first).flatMap { profileID($0, page: page) } ?? match(attr(metadata, "data-uid"), #"^([0-9]+)$"#)
    let avatarNode = profiles.lazy.compactMap { profile -> Element? in
      guard id == nil || profileID(profile, page: page) == id else { return nil }
      guard let node = first(profile, "img"), thumbnail(node, page: page) != nil else { return nil }
      return node
    }.first ?? first(root, "img.avatar,.avatar img")
    let avatar = thumbnail(avatarNode, page: page)
    let original = avatar.flatMap { preview in avatarNode.map { OriginalImageSource.resolve($0, page: page, preview: preview, link: nil) } }
    return (name, id, avatar, original)
  }
  private func profileID(_ anchor: Element, page: URL) -> String? {
    guard let url = SouthSitePolicy.resolve(attr(anchor, "href"), from: page), SouthSitePolicy.sameOrigin(url), url.path == "/u.php" else { return nil }
    if let uid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "uid" })?.value {
      return match(uid, #"^([0-9]+)$"#)
    }
    return match(url.query ?? "", #"(?:^|-)uid-([0-9]+)(?:-|\.html$)"#)
  }
  private func authorFilter(_ container: Element, page: URL, authorID: String?) -> URL? {
    for anchor in links(container, ".tiptop a[href]") {
      // Quotes and body markup cannot supply a post-header action.
      guard !anchor.parents().contains(where: { $0.hasClass("tpc_content") || $0.hasAttr("data-post-body") || $0.tagName() == "blockquote" }),
            let link = target(anchor, page: page), let uid = SouthSitePolicy.authorID(link),
            SouthSitePolicy.threadKey(link) == SouthSitePolicy.threadKey(page),
            authorID == nil || uid == authorID else { continue }
      return SouthSitePolicy.pageURL(link, number: 1)
    }
    return nil
  }
  private func postDate(_ container: Element) -> String {
    let candidates = links(container, "time,.tiptop span[title],.tiptop span.gray,.post-date,.post-time")
    for node in candidates {
      for value in [attr(node, "datetime"), text(node), attr(node, "title")] {
        if let date = match(value, #"([0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:[ T][0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)?)"#) { return date }
      }
    }
    return text(first(container, "time,.tiptop span.gray,.post-date,.post-time"))
  }
  private func floorNumber(_ container: Element, body: Element) -> Int? {
    if let number = Int(attr(container, "data-floor")), number >= 0 { return number }
    for node in links(container, ".tiptop a,.floor,.post-number,[data-floor]") {
      if let value = match(text(node), #"(?i)^B([0-9]+)F$"#), let floor = Int(value) { return floor }
      if let value = match(text(node), #"^\s*#?([0-9]+)\s*(?:\u697c|$)"#), let floor = Int(value) { return floor }
    }
    return body.id() == "read_tpc" ? 0 : nil
  }
  private func tags(_ root: Element?, page: URL) -> [ForumTag] {
    guard let root else { return [] }
    var seen = Set<String>()
    return links(root, ".thread-tag[href],.thread-tag a[href],.topic-type a[href],a[href*='type-'],a[href*='type=']").compactMap { node in
      guard let url = target(node, page: page), SouthSitePolicy.route(url)?.parameters["type"] != nil,
            !text(node).isEmpty, seen.insert(url.absoluteString).inserted else { return nil }
      return ForumTag(title: text(node), url: url)
    }
  }
  private func thumbnail(_ root: Element?, page: URL) -> URL? {
    guard let root else { return nil }
    let node = root.tagName() == "img" ? root : first(root, "img")
    for name in ["data-cover", "data-src", "src"] {
      if let result = SouthSitePolicy.resolve(attr(node ?? root, name), from: page) { return result }
    }
    return nil
  }
  static func poster(_ source: String, page: URL) -> URL? { SouthBodyParser.poster(source, page: page) }
}
