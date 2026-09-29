import Foundation
import SwiftSoup

struct SouthSearchQuery {
  var keywords: String
  var method = "OR"
  var order = "postdate"
  var time = "31536000"
}

enum SouthSearch {
  static let formURL = ForumSite.south.search

  static func isFormURL(_ url: URL) -> Bool {
    SouthSitePolicy.sameOrigin(url) && url.path == "/search.php" && (url.query == nil || url.query == "")
  }

  static func parameters(_ url: URL) -> [String: String]? {
    guard SouthSitePolicy.sameOrigin(url), url.path == "/search.php", url.absoluteString.utf8.count <= 8192,
          let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let query = parts.percentEncodedQuery else { return nil }
    var values: [String: String] = [:]
    if !query.contains("=") {
      guard let captures = captures(query, #"^step-2-keyword-(.*)-sid-([1-9][0-9]{0,17})-seekfid-(all|[1-9][0-9]{0,17})-page-([1-9][0-9]{0,4})\.html$"#),
            let keyword = captures[0].removingPercentEncoding else { return nil }
      values = ["step": "2", "keyword": keyword, "sid": captures[1], "seekfid": captures[2], "page": captures[3]]
    } else {
      for item in parts.queryItems ?? [] {
        guard let value = item.value, values.updateValue(value, forKey: item.name) == nil else { return nil }
      }
    }
    guard Set(values.keys).isSubset(of: ["step", "keyword", "sid", "seekfid", "page"]), values["step"] == "2",
          let keyword = values["keyword"], keyword.utf8.count <= 1024,
          let sid = values["sid"], numeric(sid), let forum = values["seekfid"], forum == "all" || numeric(forum),
          let page = Int(values["page"] ?? "1"), (1...99_999).contains(page) else { return nil }
    values["page"] = String(page)
    return values
  }

  static func pageURL(_ url: URL, number: Int) -> URL? {
    guard var values = parameters(url), (1...99_999).contains(number) else { return nil }
    values["page"] = String(number)
    var parts = URLComponents(url: formURL, resolvingAgainstBaseURL: false)!
    parts.queryItems = ["step", "keyword", "sid", "seekfid", "page"].map { URLQueryItem(name: $0, value: values[$0]) }
    return parts.url
  }

  static func formBody(_ source: String, url: URL, status: Int, query: SouthSearchQuery) throws -> Data {
    guard isFormURL(url) else { throw ReaderFailure.unsupported }
    let doc = try SwiftSoup.parse(source)
    try validate(doc, status: status)
    guard let form = try doc.select("form[name=sF]").first(),
          (try form.attr("method")).lowercased() == "post",
          let action = SouthSitePolicy.resolve(try form.attr("action"), from: url), isFormURL(action),
          try form.select("input[name=step][value=2]").first() != nil,
          try form.select("input[name=keyword]").first() != nil else { throw ReaderFailure.unsupported }
    let keywords = query.keywords.trimmingCharacters(in: .whitespacesAndNewlines)
    guard keywords.utf8.count >= 2 else { throw ForumSearchNotice(message: "Enter a longer search term.") }
    guard keywords.utf8.count <= 1024 else { throw ForumSearchNotice(message: "Enter a shorter search term.") }
    let required = [("method", query.method), ("sch_area", "0"), ("asc", "DESC")]
    for (name, value) in required {
      guard try form.select("input[name=\(name)]").contains(where: { try $0.attr("value") == value && !$0.hasAttr("disabled") }) else {
        throw ReaderFailure.unsupported
      }
    }
    for (name, value) in [("f_fid", "all"), ("sch_time", query.time), ("orderway", query.order)] {
      guard try form.select("select[name=\(name)] option").contains(where: { try $0.attr("value") == value && !$0.hasAttr("disabled") }) else {
        throw ReaderFailure.unsupported
      }
    }
    var fields: [(String, String)] = []
    for field in try form.select("input[type=hidden][name]:not([disabled])") {
      fields.append((try field.attr("name"), try field.attr("value")))
    }
    let selected = [("keyword", keywords), ("method", query.method), ("sch_area", "0"), ("pwuser", ""),
                    ("f_fid", "all"), ("sch_time", query.time), ("orderway", query.order), ("asc", "DESC")]
    let names = Set(selected.map { $0.0 })
    fields.removeAll { names.contains($0.0) }
    fields += selected
    return Data(fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&").utf8)
  }

  static func request(url: URL, body: Data? = nil, userAgent: String, cookies: [HTTPCookie]) throws -> URLRequest {
    guard !userAgent.isEmpty, isFormURL(url) || parameters(url) != nil, body == nil || isFormURL(url) else { throw ReaderFailure.unsupported }
    var request = URLRequest(url: SitePolicy.withoutFragment(url), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.httpShouldHandleCookies = false
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue(formURL.absoluteString, forHTTPHeaderField: "Referer")
    if let body {
      request.httpMethod = "POST"
      request.httpBody = body
      request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
      request.setValue("https://south-plus.net", forHTTPHeaderField: "Origin")
    }
    let applicable = cookies.filter { SouthSitePolicy.matches($0, url: url) }.sorted { $0.path.count > $1.path.count }
    for (key, value) in HTTPCookie.requestHeaderFields(with: applicable) { request.setValue(value, forHTTPHeaderField: key) }
    return request
  }

  static func parse(_ source: String, url: URL, status: Int = 200) throws -> ForumPage {
    guard isFormURL(url) || parameters(url) != nil else { throw ReaderFailure.unsupported }
    let doc = try SwiftSoup.parse(source)
    try validate(doc, status: status)
    guard try doc.select("form[name=sF]").isEmpty() else { throw ReaderFailure.unsupported }
    let tables = try doc.select("#main .t table").array()
    guard let table = tables.first(where: { (try? $0.select("tr.tr2 td").array().count) == 7 }) else {
      let message = try doc.select("#main .t").text()
      if !message.isEmpty { throw ForumSearchNotice(message: String(message.prefix(600))) }
      throw ReaderFailure.unsupported
    }
    var entries: [ForumEntry] = []
    var seen = Set<String>()
    let rows = try table.select("tr.tr3")
    for row in rows {
      guard let anchor = try row.select("th a[href]").first(),
            let target = threadURL(try anchor.attr("href"), from: url), seen.insert(target.absoluteString).inserted else { continue }
      let cells = try row.select("td").array()
      let author = cells.count > 2 ? try cells[2].select("a[href*=u.php]").first() : nil
      let authorName = try author?.text() ?? ""
      let authorID = author.flatMap { captures((try? $0.attr("href")) ?? "", #"^u\.php\?action-show-uid-([1-9][0-9]{0,17})\.html$"#)?.first }
      let forum = cells.count > 1 ? try cells[1].text() : ""
      let authorDate = cells.count > 2 ? try cells[2].text() : authorName
      entries.append(ForumEntry(title: try anchor.text(), url: target,
                                subtitle: [forum, authorDate].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "),
                                authorID: authorID, authorName: authorName.isEmpty ? nil : authorName))
    }
    if !rows.isEmpty(), entries.isEmpty { throw ReaderFailure.unsupported }
    let navigation = try doc.select(".pages a[href]").array().compactMap {
      SouthSitePolicy.resolve(try? $0.attr("href"), from: url)
    }.filter { parameters($0) != nil }
    let number = Int(parameters(url)?["page"] ?? "") ?? Int((try? doc.select(".pages li b").first()?.text()) ?? "") ?? 1
    let canonical = pageURL(url, number: number) ?? navigation.compactMap { pageURL($0, number: number) }.first ?? url
    let root = pageURL(canonical, number: 1)
    let paging = navigation.filter { pageURL($0, number: 1) == root }
    let last = paging.max { (Int(parameters($0)?["page"] ?? "") ?? 1) < (Int(parameters($1)?["page"] ?? "") ?? 1) }
    let declared = captures((try? doc.select(".pagesone").first()?.text()) ?? "", #"Pages:\s*[0-9]+/([0-9]+)"#)?.first.flatMap(Int.init) ?? 1
    let count = min(99_999, max(number, max(declared, Int(last.flatMap { parameters($0)?["page"] } ?? "") ?? 1)))
    return ForumPage(url: canonical, title: "Search results", kind: .threads, entries: entries, posts: [],
                     previous: number > 1 ? pageURL(canonical, number: number - 1) : nil,
                     next: number < count ? pageURL(canonical, number: number + 1) : nil, pageNumber: number,
                     lastPage: last, totalPages: count)
  }

  static func threadURL(_ value: String, from page: URL) -> URL? {
    guard let url = SouthSitePolicy.resolve(value, from: page), SouthSitePolicy.sameOrigin(url), url.path == "/read.php" else { return nil }
    if SouthSitePolicy.isThread(url) { return url }
    let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
    guard let tid = captures(raw, #"^tid-([1-9][0-9]{0,17})-keyword-.*\.html$"#)?.first else { return nil }
    return URL(string: "read.php?tid=\(tid)", relativeTo: SouthSitePolicy.base)?.absoluteURL
  }

  private static func validate(_ doc: Document, status: Int) throws {
    if status == 429 { throw ReaderFailure.rateLimit }
    if status == 401 { throw ReaderFailure.login }
    let title = try doc.select("title").text().lowercased()
    let challenge = try !doc.select("#challenge-running,#challenge-form,.cf-turnstile").isEmpty()
    if challenge || title.contains("just a moment") || title.contains("attention required") { throw ReaderFailure.verification }
    if status == 403 { throw ReaderFailure.forbidden }
    guard (200..<300).contains(status) else { throw ReaderFailure.network }
    if try !doc.select("form[action*=login] input[type=password],form input[name=pwpwd]").isEmpty() { throw ReaderFailure.login }
  }
  private static func numeric(_ value: String) -> Bool { value.range(of: #"^[1-9][0-9]{0,17}$"#, options: .regularExpression) != nil }
  private static func encode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))!
  }
  private static func captures(_ value: String, _ pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern), let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
    return (1..<result.numberOfRanges).compactMap { Range(result.range(at: $0), in: value).map { String(value[$0]) } }
  }
}
