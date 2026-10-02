import Foundation

/// Only PHPWind's attachment download action, never purchases or other job actions.
struct SouthAttachment: Equatable {
  let threadID: String
  let postID: String
  let attachmentID: String

  init?(url: URL) {
    guard SouthSitePolicy.sameOrigin(url), url.path == "/job.php",
          let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let query = parts.percentEncodedQuery else { return nil }
    var values: [String: String] = [:]
    if query.contains("=") {
      for item in parts.queryItems ?? [] {
        guard values[item.name] == nil, let value = item.value else { return nil }
        values[item.name] = value
      }
    } else {
      guard query.hasSuffix(".html") else { return nil }
      let tokens = query.dropLast(5).split(separator: "-", omittingEmptySubsequences: false)
      guard tokens.count == 8 else { return nil }
      for index in stride(from: 0, to: tokens.count, by: 2) {
        let key = String(tokens[index])
        guard values[key] == nil else { return nil }
        values[key] = String(tokens[index + 1])
      }
    }
    guard Set(values.keys) == Set(["action", "tid", "pid", "aid"]), values["action"] == "download",
          let tid = values["tid"], let pid = values["pid"], let aid = values["aid"],
          [tid, pid, aid].allSatisfy(SouthSitePolicy.validAuthorID) else { return nil }
    threadID = tid; postID = pid; attachmentID = aid
  }
  var key: String { "south-attachment:\(threadID):\(postID):\(attachmentID)" }
  var page: URL { URL(string: "read.php?tid=\(threadID)#\(postID)", relativeTo: SouthSitePolicy.base)!.absoluteURL }
  func accepts(_ target: URL) -> Bool {
    guard SouthSitePolicy.sameOrigin(target) else { return false }
    if let attachment = SouthAttachment(url: target) { return attachment == self }
    // The attachment handler can redirect to its uploaded file, but never to a
    // login, purchase, unrelated attachment action, or an external cookie sink.
    let components = target.path.split(separator: "/")
    return components.count > 1 && components.first == "attachment" &&
      !components.contains("..") && !components.contains(".") && !target.path.hasSuffix("/")
  }
}
