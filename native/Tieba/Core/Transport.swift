import Foundation
import CryptoKit
import SwiftProtobuf

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class TiebaTransport {
  let deviceID: String
  var sessionProvider: () -> Session?
  private let network: URLSession
  init(deviceID: String, sessionProvider: @escaping () -> Session?) {
    self.deviceID = deviceID.uppercased().hasSuffix("|0") ? deviceID.uppercased() : deviceID.uppercased() + "|0"
    self.sessionProvider = sessionProvider
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil; config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 60
    network = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
  }
  func requireSession() throws -> Session {
    guard let session = sessionProvider(), session.authenticated else { throw APIError(message: "Sign in to continue.", code: "login_required") }
    return session
  }
  static func sign(_ fields: [String: String]) -> String {
    let value = fields.filter { $0.key != "sign" }.map { "\($0.key)=\($0.value)" }.sorted().joined() + "tiebaclient!!!"
    return md5(Data(value.utf8)).uppercased()
  }
  static func md5(_ data: Data) -> String { Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  func headers(version: String = "12.52.1.0", session: Session?, web: Bool = false) -> [String: String] {
    var result = ["User-Agent": web ? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 tieba/\(version)" : "bdtb for Android \(version)",
                  "Accept": "*/*", "cuid": deviceID, "cuid_galaxy2": deviceID, "cuid_gid": "",
                  "Cookie": "ka=open;CUID=\(deviceID);"]
    if let session {
      if !session.userID.isEmpty { result["client_user_token"] = session.userID }
      if web { result["Cookie"] = session.cookie.isEmpty ? "BDUSS=\(session.bduss);STOKEN=\(session.stoken);" : session.cookie.replacingOccurrences(of: "[\r\n]", with: "", options: .regularExpression) }
    }
    return result
  }
  func common(version: String = "11.10.8.6", session: Session?) -> [String: String] {
    var fields = ["_client_type": "2", "_client_version": version, "_client_id": "wappc_\(deviceID.split(separator: "|").first ?? "")", "_os_version": "33", "model": "iPhone", "net_type": "1",
                  "timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)), "cuid": deviceID, "cuid_galaxy2": deviceID, "cuid_gid": "", "from": "tieba"]
    if let session { fields["BDUSS"] = session.bduss; fields["stoken"] = session.stoken }
    return fields
  }
  func request(_ url: URL, method: String, data: Data? = nil, headers: [String: String], type: String? = nil) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method; request.httpBody = data; request.httpShouldHandleCookies = false
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
    let (bytes, response): (Data, URLResponse)
    do { (bytes, response) = try await network.data(for: request) }
    catch is CancellationError { throw CancellationError() }
    catch { throw APIError(message: "Could not connect. Check your network and try again.", code: "network_error") }
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw APIError(message: "The server rejected the request.", code: String((response as? HTTPURLResponse)?.statusCode ?? 0))
    }
    guard !bytes.isEmpty, bytes.count <= 32 * 1024 * 1024 else { throw APIError(message: "The server returned an invalid response size.") }
    return bytes
  }
  func form(_ path: String, _ fields: JSON, authenticated: Bool = false, version: String = "11.10.8.6", session override: Session? = nil, omit: Set<String> = []) async throws -> JSON {
    if authenticated { _ = try requireSession() }
    let session = override ?? sessionProvider()
    var params = common(version: version, session: session)
    for (key, value) in fields where !(value is NSNull) { params[key] = string(value) }
    for key in omit { params.removeValue(forKey: key) }
    params["sign"] = Self.sign(params)
    let body = params.sorted { $0.key < $1.key }.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.joined(separator: "&")
    let bytes = try await request(URL(string: "https://tiebac.baidu.com" + path)!, method: "POST", data: Data(body.utf8), headers: headers(version: version, session: session), type: "application/x-www-form-urlencoded")
    return try decode(bytes, session: session)
  }
  func web(_ path: String, _ fields: JSON, authenticated: Bool = false) async throws -> JSON {
    if authenticated { _ = try requireSession() }
    let session = sessionProvider()
    var components = URLComponents(string: "https://tieba.baidu.com" + path)!
    components.queryItems = fields.map { URLQueryItem(name: $0.key, value: string($0.value)) }
    var values = headers(session: session, web: true)
    values["Referer"] = "https://tieba.baidu.com/mo/q/hybrid/search"
    let bytes = try await request(components.url!, method: "GET", headers: values)
    return try decode(bytes, session: session)
  }
  func proto(_ path: String, codec: String, fields: JSON, authenticated: Bool = false, outerToken: Bool = true, posting: Bool = false, legacy: Bool = false) async throws -> JSON {
    if authenticated { _ = try requireSession() }
    let session = sessionProvider()
    let json = try JSONSerialization.data(withJSONObject: ["data": fields])
    let encoded = try ProtoCodec.encode(codec, json: json)
    var params: [String: String] = [:]
    if outerToken, let session { params["stoken"] = session.stoken }
    let version = posting ? "12.35.1.0" : legacy ? "11.10.8.6" : "12.52.1.0"
    if posting || legacy { params.merge(common(version: version, session: session)) { _, next in next }; params["sign"] = Self.sign(params) }
    var values = headers(version: version, session: session)
    values["x_bd_data_type"] = "protobuf"
    let body = multipart(params, file: encoded, field: "data")
    let bytes = try await request(URL(string: "https://tiebac.baidu.com" + path)!, method: "POST", data: body.data, headers: values, type: body.type)
    if [UInt8(123), 91, 60].contains(bytes.first ?? 0) {
      _ = try decode(bytes, session: session)
      throw APIError(message: "The server returned an unexpected response format.", code: "invalid_response")
    }
    let result: JSON
    do { result = normalized(try ProtoCodec.decode(codec, bytes: bytes)) }
    catch { throw APIError(message: "This response is incompatible with the current protocol schema.", code: "protocol_error") }
    try Self.check(result, session: session)
    return object(result["data"])
  }
  func upload(_ path: String, fields: [String: String], bytes: Data, field: String = "chunk", version: String = "12.25.1.0") async throws -> JSON {
    let session = try requireSession()
    var params = common(version: version, session: session)
    params.merge(fields) { _, next in next }; params["sign"] = Self.sign(params)
    let body = multipart(params, file: bytes, field: field)
    let response = try await request(URL(string: "https://tiebac.baidu.com" + path)!, method: "POST", data: body.data, headers: headers(version: version, session: session), type: body.type)
    return try decode(response, session: session)
  }
  private func multipart(_ fields: [String: String], file: Data, field: String) -> (data: Data, type: String) {
    let boundary = "TiebaLite-" + UUID().uuidString
    var data = Data()
    for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
      data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
    }
    data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"file\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
    data.append(file); data.append(Data("\r\n--\(boundary)--\r\n".utf8))
    return (data, "multipart/form-data; boundary=\(boundary)")
  }
  private func decode(_ data: Data, session: Session?) throws -> JSON {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? JSON else { throw APIError(message: "The server returned a non-JSON response. Browser verification may be required.", code: "invalid_response") }
    let result = normalized(json)
    try Self.check(result, session: session)
    return result
  }
  static func check(_ json: JSON, session: Session?) throws {
    let nested = object(json["error"])
    let code = string(json["error_code"] ?? json["no"] ?? json["errno"] ?? nested["error_code"] ?? nested["errorno"] ?? nested["errno"] ?? nested["code"])
    guard !code.isEmpty, code != "0" else { return }
    let safeCode = code.count < 40 && code.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil ? code : "server_error"
    var message = first(json, ["error_msg", "errmsg"])
    if message.isEmpty { message = first(nested, ["error_msg", "user_msg", "errmsg", "usermsg"]) }
    if let session {
      for secret in [session.bduss, session.stoken, session.cookie, session.zid] where !secret.isEmpty { message = message.replacingOccurrences(of: secret, with: "[redacted]") }
    }
    message = message.replacingOccurrences(of: "(?i)(BDUSS|STOKEN|cookie)\\s*[:=]\\s*[^\\s;,]+", with: "[redacted]", options: .regularExpression)
    if message.isEmpty || message.count > 300 { message = "Tieba rejected this request (code \(safeCode))." }
    let candidate = safeURL(string(json["vcode_url"] ?? nested["vcode_url"]))
    let verification = candidate.flatMap { ($0.host == "baidu.com" || $0.host?.hasSuffix(".baidu.com") == true) ? $0 : nil }
    throw APIError(message: message, code: safeCode, verification: verification)
  }
}
