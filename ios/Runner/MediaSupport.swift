import Foundation

enum MediaPolicy {
  static func posterPage(_ url: URL) -> Bool {
    guard allowed(url), url.query == nil, url.fragment == nil else { return false }
    if turboID(url) != nil { return true }
    return ["cyberdrop.cr", "www.cyberdrop.cr"].contains(url.host?.lowercased() ?? "") &&
      url.path.range(of: #"^/e/[A-Za-z0-9_-]{1,128}/?$"#, options: .regularExpression) != nil
  }
  static func allowed(_ url: URL) -> Bool {
    url.scheme == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) && url.absoluteString.utf8.count <= 8192
  }
  static func sameOrigin(_ url: URL, _ other: URL) -> Bool {
    allowed(url) && allowed(other) && url.host?.lowercased() == other.host?.lowercased()
  }
  static func cookieMatches(_ cookie: HTTPCookie, _ url: URL) -> Bool {
    guard allowed(url), let host = url.host?.lowercased(), cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
    let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let matchesDomain = host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix("." + domain))
    let path = url.path.isEmpty ? "/" : url.path
    let matchesPath = path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
    return matchesDomain && matchesPath
  }
  static func turboID(_ url: URL) -> String? {
    guard allowed(url), ["turbo.cr", "www.turbo.cr"].contains(url.host?.lowercased() ?? "") else { return nil }
    let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
    guard (parts.count == 3 || (parts.count == 4 && parts[3].isEmpty)),
          parts[0].isEmpty, ["embed", "v", "d"].contains(String(parts[1])) else { return nil }
    let id = String(parts[2])
    guard !id.isEmpty, id.utf8.count <= 128,
          id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
    return id
  }
  static func signedURL(_ data: Data) throws -> URL {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          json["success"] as? Bool == true, let value = json["url"] as? String,
          let url = URL(string: value), allowed(url) else {
      throw MediaFailure(reason: "The provider did not return a valid stream.")
    }
    return url
  }
}

// Only controlled labels, numeric codes, and allowlisted metadata enter reports.
final class MediaDiagnostics {
  private let started = ProcessInfo.processInfo.systemUptime
  private var events: [String] = []
  func record(_ stage: String, _ detail: String) {
    let elapsed = Int(ProcessInfo.processInfo.systemUptime - started)
    events.append("\(elapsed)s \(stage): \(detail)")
    if events.count > 40 { events.removeFirst(events.count - 40) }
  }
  static func domain(_ value: String) -> String {
    ["NSURLErrorDomain", "AVFoundationErrorDomain", "NSOSStatusErrorDomain",
     "NSCocoaErrorDomain", "WKErrorDomain", "CoreMediaErrorDomain",
     "CoreMediaErrorDomainHTTP", "HTTP"].contains(value) ? value : "OtherDomain"
  }
  func error(_ stage: String, _ error: NSError?) {
    guard let error = error else { record(stage, "No underlying error provided"); return }
    var current: NSError? = error
    for _ in 0..<3 {
      guard let item = current else { break }
      record(stage, "\(Self.domain(item.domain)) code=\(item.code)")
      current = item.userInfo[NSUnderlyingErrorKey] as? NSError
    }
  }
  static func mime(_ value: String?) -> String {
    let known = ["text/html", "application/json", "application/octet-stream", "video/mp4",
                 "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "text/plain"]
    return known.contains(value?.lowercased() ?? "") ? value!.lowercased() : "other/unknown"
  }
  var report: String {
    "Playback diagnostics\n" + events.joined(separator: "\n") +
      "\n\nNo URLs, cookies, account details, or page content are included."
  }
}

struct MediaFailure: Error {
  let reason: String
  var underlying: NSError? = nil
}

struct ResolvedMedia {
  let url: URL
  let cookies: [HTTPCookie]
}

// Two bounded GETs in a private, in-memory session. No player/ad scripts run here.
final class TurboResolver: NSObject, URLSessionDataDelegate {
  private let pageURL: URL
  private let signURL: URL
  private var cookies: [HTTPCookie]
  private let configuration: URLSessionConfiguration
  private let event: (String, String) -> Void
  private let completion: (Result<ResolvedMedia, MediaFailure>) -> Void
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var data = Data()
  private var bytes = 0
  private var signing = false
  private var finished = false
  private var failure: MediaFailure?
  private var responseReceived = false
  private var stage: String { signing ? "sign" : "provider-page" }

  init(id: String, cookies: [HTTPCookie], configuration: URLSessionConfiguration = .ephemeral,
       event: @escaping (String, String) -> Void,
       completion: @escaping (Result<ResolvedMedia, MediaFailure>) -> Void) {
    pageURL = URL(string: "https://turbo.cr/d/\(id)")!
    var components = URLComponents(string: "https://turbo.cr/api/sign")!
    components.queryItems = [URLQueryItem(name: "v", value: id)]
    signURL = components.url!
    self.cookies = cookies
    self.configuration = configuration
    self.event = event
    self.completion = completion
  }
  func start() {
    configuration.urlCache = nil
    configuration.urlCredentialStorage = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 25
    cookies = cookies.filter { MediaPolicy.cookieMatches($0, pageURL) || MediaPolicy.cookieMatches($0, signURL) }
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    request(pageURL)
  }
  func cancel() {
    guard !finished else { return }
    finished = true
    task?.cancel()
    session?.invalidateAndCancel()
    session = nil
  }
  private func request(_ url: URL) {
    data = Data()
    bytes = 0
    failure = nil
    responseReceived = false
    event(stage, "GET started")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.httpShouldHandleCookies = false
    let applicable = cookies.filter { MediaPolicy.cookieMatches($0, url) }
    for (name, value) in HTTPCookie.requestHeaderFields(with: applicable) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    request.setValue(signing ? "application/json" : "text/html", forHTTPHeaderField: "Accept")
    request.setValue(signing ? pageURL.absoluteString : "https://simpcity.cr/", forHTTPHeaderField: "Referer")
    task = session?.dataTask(with: request)
    task?.resume()
  }
  private func finish(_ result: Result<ResolvedMedia, MediaFailure>) {
    guard !finished else { return }
    finished = true
    session?.finishTasksAndInvalidate()
    session = nil
    completion(result)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    // Do not forward provider session data to redirects or verification hosts.
    event(stage, "Redirect blocked HTTP \(response.statusCode)")
    failure = MediaFailure(reason: "The provider redirected this request. Open Web player if verification is required.")
    completionHandler(nil)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard !finished else { completionHandler(.cancel); return }
    responseReceived = true
    guard let http = response as? HTTPURLResponse else {
      failure = MediaFailure(reason: "The provider returned an invalid response.")
      completionHandler(.cancel); return
    }
    event(stage, "HTTP \(http.statusCode), MIME \(MediaDiagnostics.mime(http.mimeType))")
    if let responseURL = http.url, MediaPolicy.sameOrigin(responseURL, pageURL) {
      var headers: [String: String] = [:]
      for (name, value) in http.allHeaderFields { headers[String(describing: name)] = String(describing: value) }
      for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: responseURL) {
        cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
        if MediaPolicy.cookieMatches(cookie, pageURL) || MediaPolicy.cookieMatches(cookie, signURL) { cookies.append(cookie) }
      }
    }
    let limit = signing ? 64 * 1024 : 2 * 1024 * 1024
    if failure == nil && !(200..<300).contains(http.statusCode) {
      failure = MediaFailure(reason: "The provider returned HTTP \(http.statusCode). Open Web player if verification is required.")
    }
    if response.expectedContentLength > Int64(limit) {
      failure = MediaFailure(reason: "The provider response exceeded the size limit.")
    }
    if signing && http.mimeType?.lowercased() != "application/json" {
      failure = failure ?? MediaFailure(reason: "The provider returned a page instead of JSON. Open Web player to check access.")
    }
    completionHandler(failure == nil ? .allow : .cancel)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    guard !finished else { return }
    bytes += chunk.count
    guard bytes <= (signing ? 64 * 1024 : 2 * 1024 * 1024) else {
      failure = MediaFailure(reason: "The provider response exceeded the size limit.")
      dataTask.cancel(); return
    }
    if signing { data.append(chunk) }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard !finished else { return }
    if let failure = failure { finish(.failure(failure)); return }
    if let error = error { finish(.failure(MediaFailure(reason: "The provider request failed. Please refresh to try again.", underlying: error as NSError))); return }
    guard responseReceived else { finish(.failure(MediaFailure(reason: "No provider response was received."))); return }
    if !signing {
      signing = true
      request(signURL)
      return
    }
    do {
      let url = try MediaPolicy.signedURL(data)
      let applicable = cookies.filter { MediaPolicy.cookieMatches($0, url) }
      event(stage, "Validated HTTPS stream")
      finish(.success(ResolvedMedia(url: url, cookies: applicable)))
    } catch {
      finish(.failure(MediaFailure(reason: "The provider did not return valid stream JSON.")))
    }
  }
}
