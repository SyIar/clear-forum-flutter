import Foundation
import SwiftSoup

// PHPWind post structure verified against user-supplied South HTML.
struct SouthForumParser {
  private let unwanted = "script,style,object,embed,input,textarea,select,svg,noscript,.adsbygoogle,.advertisement,.ad-container,.adContainer,.ad-block,.sponsor,[data-ad],[data-ad-slot],[hidden]"
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
    if bodies.isEmpty, hasLoginForm, first(doc, "#ajaxtable,.thread-list,#threadlist") == nil { throw ReaderFailure.login }
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
        posts.append(ForumPost(id: id, author: identity.name.isEmpty ? "Member" : identity.name, date: date,
                              number: floor.map { "#\($0)" } ?? "", blocks: blocks, authorID: identity.id, avatar: identity.avatar))
      }
      guard !posts.isEmpty else { throw ReaderFailure.unsupported }
    }

    var entries: [ForumEntry] = []
    var seenEntries = Set<String>()
    if !thread {
      let root = first(doc, "#ajaxtable,#threadlist,.thread-list,#main") ?? doc
      // Title selectors take precedence over last-reply and per-row page links.
      let preferred = links(root, "h3 a[href],.subject a[href],a.subject[href],a[id^=a_ajax_],.thread-title a[href]")
      for anchor in preferred + links(root) {
        guard let link = target(anchor, page: url), SouthSitePolicy.isThread(link), !text(anchor).isEmpty,
              anchor.parents().allSatisfy({ !$0.hasClass("pages") && $0.id() != "breadCrumb" }),
              let row = anchor.parents().first(where: { $0.tagName() == "tr" || $0.hasClass("thread-row") || $0.tagName() == "article" }),
              seenEntries.insert(SouthSitePolicy.threadKey(link) ?? link.absoluteString).inserted else { continue }
        let author = text(first(row, ".author,.username,a[href*=u.php],a[href*=uid]"))
        let pinned = row.hasClass("sticky") || row.hasClass("pinned") || first(row, "img[src*=headtopic],img[src*=top1],img[src*=top2],img[src*=top3],[data-sticky=true]") != nil
        entries.append(ForumEntry(title: text(anchor), url: link, subtitle: author, pinned: pinned,
                                  thumbnail: thumbnail(first(row, ".thread-thumbnail,.thumbnail,[data-cover]"), page: url),
                                  tags: tags(row, page: url)))
      }
      if entries.isEmpty, SouthSitePolicy.route(url)?.path == "/index.php" {
        for anchor in links(root, "h2 a[href],h3 a[href],.forum-name a[href],a.forum-name[href]") {
          guard let link = target(anchor, page: url), SouthSitePolicy.route(link)?.path == "/thread.php", !text(anchor).isEmpty,
                seenEntries.insert(SouthSitePolicy.pageCacheKey(link)).inserted else { continue }
          entries.append(ForumEntry(title: text(anchor), url: link))
        }
      }
      // Unknown markup must not look like a successfully loaded empty forum.
      if entries.isEmpty, first(doc, "[data-empty-forum=true],.thread-list-empty") == nil { throw ReaderFailure.unsupported }
    }

    let navigation = links(doc, ".pages a[href],.pagination a[href],.page-nav a[href],a[rel=next],a[rel=prev],a[rel=last],link[rel=next],link[rel=prev],link[rel=last]")
    let pageLinks = navigation.compactMap { target($0, page: url) }.filter { SouthSitePolicy.pageRoot($0) == SouthSitePolicy.pageRoot(url) }
    let number = SouthSitePolicy.pageNumber(url)
    let declaredTotals = links(doc, ".pages [data-total-pages],.pagination [data-total-pages],.pages input[name=page],.pages input[name=jump_page]")
      .compactMap { Int(attr($0, "data-total-pages")) ?? Int(attr($0, "max")) }.filter { (1...99_999).contains($0) }
    let knownCount = (pageLinks.map(SouthSitePolicy.pageNumber) + declaredTotals + [number]).max() ?? number
    let last = pageLinks.max { SouthSitePolicy.pageNumber($0) < SouthSitePolicy.pageNumber($1) }
    let next = pageLinks.first { SouthSitePolicy.pageNumber($0) == number + 1 } ?? (knownCount > number ? SouthSitePolicy.pageURL(url, number: number + 1) : nil)
    let previous = pageLinks.first { SouthSitePolicy.pageNumber($0) == number - 1 } ?? (number > 1 ? SouthSitePolicy.pageURL(url, number: number - 1) : nil)
    // A missing pager is not proof that this is the last page.
    let explicitLast = navigation.contains { attr($0, "rel").split(separator: " ").contains("last") && target($0, page: url).map(SouthSitePolicy.pageNumber) == number }
    let maximumIsKnown = thread && next == nil && (declaredTotals.contains(number) || explicitLast)
    let maximum = maximumIsKnown ? posts.compactMap { Int($0.number.dropFirst()) }.max() : nil
    let heading = first(doc, thread ? "#subject_tpc,h1.thread-title,h1" : "h1,.forum-title,#thread-title")
    let fallbackTitle = breadcrumbs.last?.title ?? pageTitle.components(separatedBy: " - ").first ?? "Forum"
    let title = text(heading).isEmpty ? fallbackTitle : text(heading)
    let kind: PageKind = thread ? .posts : (SouthSitePolicy.route(url)?.path == "/index.php" ? .forums : .threads)
    return ForumPage(url: url, title: title.isEmpty ? "Forum" : title, kind: kind, entries: entries, posts: posts,
                     previous: previous, next: next, pageNumber: number, loggedIn: loggedIn,
                     lastPage: last, maximumPostNumber: maximum, breadcrumbs: breadcrumbs,
                     tags: tags(heading, page: url), totalPages: knownCount)
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
  private func postAuthor(_ container: Element, page: URL) -> (name: String, id: String?, avatar: URL?) {
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
    let avatar = profiles.lazy.compactMap { profile -> URL? in
      guard id == nil || profileID(profile, page: page) == id else { return nil }
      return thumbnail(first(profile, "img"), page: page)
    }.first ?? thumbnail(first(root, "img.avatar,.avatar img"), page: page)
    return (name, id, avatar)
  }
  private func profileID(_ anchor: Element, page: URL) -> String? {
    guard let url = SouthSitePolicy.resolve(attr(anchor, "href"), from: page), SouthSitePolicy.sameOrigin(url), url.path == "/u.php" else { return nil }
    if let uid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "uid" })?.value {
      return match(uid, #"^([0-9]+)$"#)
    }
    return match(url.query ?? "", #"(?:^|-)uid-([0-9]+)(?:-|\.html$)"#)
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
