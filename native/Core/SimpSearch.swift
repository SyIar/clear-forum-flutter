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
  static let formURL = ForumSite.simp.search

  static func validate(_ doc: Document, url: URL, status: Int) throws {
    let title = (try doc.select("title").text()).lowercased()
    if status == 429 { throw ReaderFailure.rateLimit }
    let challenge = try !doc.select("#challenge-running,#challenge-form,.cf-turnstile").isEmpty()
    if title.contains("just a moment") || title.contains("attention required") || challenge { throw ReaderFailure.verification }
    let template = try doc.select("html").first()?.attr("data-template") ?? ""
    if status == 401 || template == "login" || ForumSite.simp.isLogin(url) { throw ReaderFailure.login }
    if status == 403 { throw ReaderFailure.forbidden }
    if status == 404, SimpSitePolicy.searchResults(url) {
      throw ForumSearchNotice(message: "This search is no longer available. Search again.")
    }
    guard (200..<300).contains(status) || status == 400 else { throw ReaderFailure.network }
    let hasError = try !doc.select(".blockMessage--error").isEmpty()
    if template == "error" || hasError {
      if try !doc.select("form[action*=login]").isEmpty() { throw ReaderFailure.login }
      let notice = try doc.select(".blockMessage,.block-body .block-row").text()
      guard !notice.isEmpty else { throw ReaderFailure.unsupported }
      throw ForumSearchNotice(message: String(notice.prefix(600)))
    }
    guard (200..<300).contains(status) else { throw ReaderFailure.network }
  }

  static func formBody(_ source: String, url: URL, status: Int, query: SimpSearchQuery) throws -> Data {
    guard url == formURL else { throw ReaderFailure.unsupported }
    let doc = try SwiftSoup.parse(source)
    try validate(doc, url: url, status: status)
    let keywords = query.keywords.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keywords.isEmpty, keywords.utf8.count <= 1024, ["date", "relevance"].contains(query.order) else {
      throw ForumSearchNotice(message: "Enter a shorter search term.")
    }
    guard let form = try doc.select("form").first(where: {
      (try? $0.select("input[type=search][name=keywords]").isEmpty()) == false
    }), (try form.attr("method")).lowercased() == "post",
      let action = SimpSitePolicy.resolve(try form.attr("action"), from: url), action == formURL,
      let token = try form.select("input[type=hidden][name=_xfToken]").first()?.attr("value"), !token.isEmpty else {
      throw ReaderFailure.unsupported
    }
    let searchType = try form.select("input[type=hidden][name=search_type]").first()?.attr("value") ?? ""
    var fields = [("_xfToken", token), ("keywords", keywords), ("order", query.order), ("search_type", searchType)]
    if query.titlesOnly { fields.append(("c[title_only]", "1")) }
    return Data(fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&").utf8)
  }

  static func request(url: URL, body: Data? = nil, userAgent: String, cookies: [HTTPCookie]) throws -> URLRequest {
    guard !userAgent.isEmpty, url == formURL || SimpSitePolicy.searchResults(url), body == nil || url == formURL else {
      throw ReaderFailure.unsupported
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
