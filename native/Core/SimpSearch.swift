import Foundation
import SwiftSoup

struct SimpSearchQuery: Equatable {
  var keywords: String
  var titlesOnly = false
  var order = "date"
}

struct ForumSearchNotice: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

enum SimpSearch {
  // XenForo's Advanced search button can POST to /search/search and render the
  // form there. Opening that address with GET instead executes an empty search.
  static let formURL = SimpSitePolicy.base.appendingPathComponent("search/")
  static let submitURL = SimpSitePolicy.base.appendingPathComponent("search/search")

  static func isFormURL(_ url: URL) -> Bool {
    SimpSitePolicy.sameOrigin(url) && ["/search", "/search/"].contains(url.path) && url.query == nil && url.fragment == nil
  }

  static func parseResult(_ source: String, url: URL, status: Int) throws -> ForumPage {
    guard url == submitURL || isFormURL(url) || SimpSitePolicy.searchResults(url) else { throw ReaderFailure.unsupported }
    if SimpSitePolicy.searchResults(url) { return try SimpForumParser().parse(source, url: url, status: status) }
    // Failed submissions return a site notice at the POST endpoint, not a form
    // suitable for another submission. Never retry the POST automatically.
    try validate(SwiftSoup.parse(source), url: url, status: status)
    throw ReaderFailure.unsupported
  }

  static func validate(_ doc: Document, url: URL, status: Int) throws {
    let title = (try doc.select("title").text()).lowercased()
    if status == 429 { throw ReaderFailure.rateLimit }
    let challenge = try !doc.select("#challenge-running,#challenge-form,.cf-turnstile").isEmpty()
    if title.contains("just a moment") || title.contains("attention required") || challenge { throw ReaderFailure.verification }
    let template = try doc.select("html").first()?.attr("data-template") ?? ""
    if status == 401 || template == "login" || ForumSite.simp.isLogin(url) { throw ReaderFailure.login }
    if status == 403 { throw ReaderFailure.forbidden }
    if status == 404, SimpSitePolicy.searchResults(url) {
      throw ForumSearchNotice(message: AppText.text("This search is no longer available. Search again."))
    }
    guard (200..<300).contains(status) || status == 400 else { throw ReaderFailure.network }
    let hasError = try !doc.select(".blockMessage--error").isEmpty()
    if template == "error" || hasError {
      if try !doc.select("form[action*=login]").isEmpty() { throw ReaderFailure.login }
      // Navigation/install/JavaScript notices also use block-row. Prefer the
      // actual error and never concatenate all of the page's generic blocks.
      for selector in [".blockMessage--error", ".p-body-pageContent .blockMessage", ".p-body-pageContent .block-body .block-row", ".blockMessage"] {
        for node in try doc.select(selector) {
          guard !node.hasAttr("hidden"), !node.parents().contains(where: { $0.tagName() == "noscript" || $0.hasAttr("hidden") }) else { continue }
          let notice = try node.text().trimmingCharacters(in: .whitespacesAndNewlines)
          if !notice.isEmpty { throw ForumSearchNotice(message: String(notice.prefix(600))) }
        }
      }
      throw ReaderFailure.unsupported
    }
    guard (200..<300).contains(status) else { throw ReaderFailure.network }
  }

  static func formBody(_ source: String, url: URL, status: Int, query: SimpSearchQuery) throws -> Data {
    guard isFormURL(url) else { throw ReaderFailure.unsupported }
    let doc = try SwiftSoup.parse(source)
    try validate(doc, url: url, status: status)
    let keywords = query.keywords.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keywords.isEmpty, keywords.utf8.count <= 1024, ["date", "relevance"].contains(query.order) else {
      throw ForumSearchNotice(message: AppText.text("Enter a shorter search term."))
    }
    let forms = try doc.select(".p-body-pageContent form").array() + doc.select("form").array()
    guard let form = try forms.first(where: { form in
      guard try form.attr("method").lowercased() == "post",
            let action = SimpSitePolicy.resolve(try form.attr("action"), from: url), action == submitURL else { return false }
      let fields = try form.select("input[name=keywords]:not([disabled])").array()
      guard fields.count == 1, let field = fields.first else { return false }
      return ["", "search", "text"].contains(try field.attr("type").lowercased())
    }) else { throw ReaderFailure.unsupported }
    let tokens = try form.select("input[type=hidden][name=_xfToken]:not([disabled])").array()
    let types = try form.select("input[type=hidden][name=search_type]:not([disabled])").array()
    guard tokens.count == 1, let token = try tokens.first?.attr("value"), !token.isEmpty, types.count <= 1 else {
      throw ReaderFailure.unsupported
    }
    let searchType = try types.first?.attr("value") ?? ""
    var fields = [("_xfToken", token), ("keywords", keywords), ("order", query.order), ("search_type", searchType)]
    if query.titlesOnly { fields.append(("c[title_only]", "1")) }
    return Data(fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&").utf8)
  }

  static func request(url: URL, body: Data? = nil, userAgent: String, cookies: [HTTPCookie]) throws -> URLRequest {
    guard !userAgent.isEmpty else { throw ReaderFailure.unsupported }
    if body != nil {
      guard url == submitURL else { throw ReaderFailure.unsupported }
    } else {
      guard isFormURL(url) || SimpSitePolicy.searchResults(url) else { throw ReaderFailure.unsupported }
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.httpShouldHandleCookies = false
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    if let body {
      request.httpMethod = "POST"
      request.httpBody = body
      request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
      request.setValue(SimpSitePolicy.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
      request.setValue(formURL.absoluteString, forHTTPHeaderField: "Referer")
    }
    let applicable = cookies.filter { SimpSitePolicy.matches($0, url: url) }.sorted { $0.path.count > $1.path.count }
    for (key, value) in HTTPCookie.requestHeaderFields(with: applicable) { request.setValue(value, forHTTPHeaderField: key) }
    return request
  }

  private static func encode(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed)!
  }
}
