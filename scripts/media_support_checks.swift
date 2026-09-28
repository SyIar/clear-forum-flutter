// Synthetic URLProtocol responses; no live providers or media are requested.
final class StubProtocol: URLProtocol {
  static var requests: [URLRequest] = []
  static var responder: ((URLRequest) -> (Int, [String: String], Data))!
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests.append(request)
    let (status, headers, data) = Self.responder(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

func checkResolve(signStatus: Int = 200, mime: String = "application/json",
                  json: String = #"{"success":true,"url":"https://media.example/clip.mp4?token=private-fixture"}"#,
                  pageStatus: Int = 200, oversized: Bool = false) -> Result<ResolvedMedia, MediaFailure> {
  StubProtocol.requests = []
  StubProtocol.responder = { request in
    if request.url!.path.hasPrefix("/d/") {
      return (pageStatus, ["Content-Type": "text/html", "Set-Cookie": "provider=fixture; Path=/; Secure"], Data("<html></html>".utf8))
    }
    return (signStatus, ["Content-Type": mime], oversized ? Data(repeating: 32, count: 70 * 1024) : Data(json.utf8))
  }
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [StubProtocol.self]
  let forumCookie = HTTPCookie(properties: [.name: "forum", .value: "private-session", .domain: ".simpcity.cr", .path: "/", .secure: "TRUE"])!
  var result: Result<ResolvedMedia, MediaFailure>?
  let diagnostics = MediaDiagnostics()
  let resolver = TurboResolver(id: "sample123", cookies: [forumCookie], configuration: configuration,
    event: { diagnostics.record($0, $1) }, completion: { result = $0 })
  resolver.start()
  let deadline = Date().addingTimeInterval(5)
  while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  precondition(result != nil, "Resolver did not complete")
  precondition(!diagnostics.report.contains("private-fixture"))
  precondition(!diagnostics.report.contains("sample123"))
  precondition(!diagnostics.report.contains("private-session"))
  precondition(!StubProtocol.requests.contains { ($0.value(forHTTPHeaderField: "Cookie") ?? "").contains("forum=") })
  return result!
}

for path in ["embed", "v", "d"] {
  precondition(MediaPolicy.turboID(URL(string: "https://turbo.cr/\(path)/sample_1-2/")!) == "sample_1-2")
}
for address in ["https://turbo.cr.evil.example/embed/sample", "https://turbo.cr:8443/embed/sample",
                "https://turbo.cr/embed/a/b", "https://turbo.cr/embed/a%2Fb", "http://turbo.cr/embed/sample",
                "https://turbo.cr//embed/sample", "https://turbo.cr/a/sample"] {
  precondition(MediaPolicy.turboID(URL(string: address)!) == nil)
}
switch checkResolve() {
case .success(let media):
  precondition(media.url.host == "media.example")
  precondition(media.cookies.isEmpty, "Provider cookies must not reach another domain")
case .failure: preconditionFailure("Expected a resolved media URL")
}
precondition(StubProtocol.requests.count == 2)
precondition(StubProtocol.requests[1].value(forHTTPHeaderField: "Referer") == "https://turbo.cr/d/sample123")
precondition(StubProtocol.requests[1].value(forHTTPHeaderField: "Cookie")?.contains("provider=fixture") == true)
for result in [
  checkResolve(signStatus: 403),
  checkResolve(mime: "text/html", json: "<html>Verification</html>"),
  checkResolve(json: #"{"success":false,"url":"https://media.example/file.mp4"}"#),
  checkResolve(json: #"{"success":true,"url":"http://media.example/file.mp4"}"#),
  checkResolve(json: #"{"success":true,"url":"https://user:secret@media.example/file.mp4"}"#),
  checkResolve(json: "invalid json"),
  checkResolve(oversized: true),
  checkResolve(pageStatus: 302),
] {
  if case .success = result { preconditionFailure("Invalid provider response was accepted") }
}
precondition(StubProtocol.requests.count == 1, "A redirect must not proceed to signing")

var cancelledCompletion = false
let cancelConfiguration = URLSessionConfiguration.ephemeral
cancelConfiguration.protocolClasses = [StubProtocol.self]
let cancelled = TurboResolver(id: "sample123", cookies: [], configuration: cancelConfiguration,
  event: { _, _ in }, completion: { _ in cancelledCompletion = true })
cancelled.start()
cancelled.cancel()
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
precondition(!cancelledCompletion, "Cancelled work must not update a later attempt")

let diagnostics = MediaDiagnostics()
let nested = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: [NSLocalizedDescriptionKey: "https://secret.example/account?token=private"])
diagnostics.error("avkit", NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: nested]))
diagnostics.error("custom", NSError(domain: "https://secret.example", code: 1))
precondition(diagnostics.report.contains("NSURLErrorDomain code=-1009"))
precondition(diagnostics.report.contains("AVFoundationErrorDomain code=-11800"))
precondition(!diagnostics.report.contains("secret.example"))
precondition(!diagnostics.report.contains("private"))
precondition(MediaDiagnostics.mime("text/html; secret=value") == "other/unknown")
for _ in 0..<60 { diagnostics.record("bounded", "event") }
precondition(diagnostics.report.components(separatedBy: "bounded: event").count == 41)
print("Media support checks passed: resolver, cookies, response limits, failures and diagnostic redaction")
