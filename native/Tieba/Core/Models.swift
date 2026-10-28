import Foundation

typealias JSON = [String: Any]
func object(_ value: Any?) -> JSON { value as? JSON ?? [:] }
func records(_ value: Any?) -> [JSON] {
  if let array = value as? [Any] { return array.compactMap { $0 as? JSON } }
  if let map = value as? JSON { return map.values.compactMap { $0 as? JSON } }
  return []
}
func string(_ value: Any?) -> String {
  guard let value, !(value is NSNull) else { return "" }
  if let value = value as? String { return value }
  return String(describing: value)
}
func integer(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? Int(string(value)) ?? 0 }
func boolean(_ value: Any?) -> Bool { value as? Bool == true || string(value) == "1" }
func first(_ json: JSON, _ keys: [String]) -> String {
  keys.lazy.map { string(json[$0]) }.first { !$0.isEmpty } ?? ""
}
func https(_ value: String) -> String {
  if value.hasPrefix("//") { return "https:" + value }
  if value.hasPrefix("http://") { return "https://" + value.dropFirst(7) }
  return value
}
func safeURL(_ value: String) -> URL? {
  guard let url = URL(string: https(value)), url.scheme == "https", !(url.host ?? "").isEmpty, url.user == nil, url.password == nil else { return nil }
  return url
}
func stripHTML(_ value: String) -> String {
  var output = value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
  for (from, to) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] { output = output.replacingOccurrences(of: from, with: to) }
  return output
}
func normalized(_ json: JSON) -> JSON {
  var output: JSON = [:]
  for (key, value) in json {
    let converted: Any
    if let map = value as? JSON { converted = normalized(map) }
    else if let list = value as? [Any] { converted = list.map { ($0 as? JSON).map(normalized) ?? $0 } }
    else { converted = value }
    output[key] = converted
    output[key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression).lowercased()] = converted
  }
  return output
}

struct APIError: Error, LocalizedError {
  let message: String
  var code = ""
  var verification: URL?
  var errorDescription: String? { message }
}
struct UserProfile: Identifiable {
  var raw: JSON = [:]
  var id: String { first(raw, ["id", "user_id", "uid", "lz_uid"]) }
  var name: String { first(raw, ["name_show", "show_nickname", "user_nickname", "name", "user_name"]) }
  var username: String { first(raw, ["username", "user_name", "name"]) }
  var portrait: String { first(raw, ["portrait", "user_portrait"]) }
  var avatar: String {
    let candidate = first(raw, ["avatar", "portraith"])
    if !candidate.isEmpty { return https(candidate) }
    if portrait.hasPrefix("http") || portrait.hasPrefix("//") { return https(portrait) }
    return portrait.isEmpty ? "" : "https://tb.himg.baidu.com/sys/portrait/item/\(portrait)"
  }
  var level: Int { integer(raw["level_id"] ?? raw["level"]) }
  var intro: String { first(raw, ["intro", "display_intro"]) }
  var following: Bool { boolean(raw["has_concerned"]) || boolean(raw["is_friend"]) || boolean(raw["isFollowing"]) }
  var followers: Int { integer(raw["fans_num"] ?? raw["followerCount"]) }
  var follows: Int { integer(raw["concern_num"] ?? raw["followingCount"]) }
  var posts: Int { integer(raw["post_num"] ?? raw["threadCount"]) }
  var stored: JSON { ["id": id, "name": name, "username": username, "portrait": portrait, "avatar": avatar, "level": level, "intro": intro, "isFollowing": following, "followerCount": followers, "followingCount": follows, "threadCount": posts, "sex": integer(raw["sex"]), "birthday": first(raw, ["birthday"]), "showBirthday": boolean(raw["showBirthday"])] }
}
struct Forum: Identifiable {
  var raw: JSON = [:]
  var id: String { first(raw, ["id", "forum_id", "fid"]) }
  var name: String { first(raw, ["name", "forum_name", "forum_name_show"]) }
  var avatar: String { https(first(raw, ["avatar", "avatar_url"])) }
  var intro: String { first(raw, ["slogan", "intro", "description", "desc"]) }
  var members: Int? {
    let value = raw["member_num"] ?? raw["member_count"] ?? raw["concern_num"] ?? raw["memberCount"]
    return Int(string(value))
  }
  var threads: Int { integer(raw["thread_num"] ?? raw["thread_count"] ?? raw["post_num"] ?? raw["threadCount"]) }
  var level: Int { integer(raw["user_level"] ?? raw["level_id"] ?? raw["level"]) }
  var following: Bool { boolean(raw["is_like"]) || boolean(raw["has_concerned"]) || boolean(raw["isFollowing"]) }
  var signed: Bool {
    get { boolean(raw["isSigned"] ?? raw["is_sign_in"] ?? object(object(raw["sign_in_info"])["user_info"])["is_sign_in"]) }
    set { raw["isSigned"] = newValue }
  }
  var stored: JSON {
    var value: JSON = ["id": id, "name": name, "avatar": avatar, "description": intro, "threadCount": threads, "level": level, "isFollowing": following, "isSigned": signed]
    if let members { value["memberCount"] = members }
    return value
  }
}
struct Session {
  var raw: JSON
  var bduss: String { string(raw["bduss"]) }
  var stoken: String { string(raw["stoken"]) }
  var userID: String { string(raw["userId"]) }
  var tbs: String { get { string(raw["tbs"]) } set { raw["tbs"] = newValue } }
  var zid: String { get { string(raw["zid"]) } set { raw["zid"] = newValue } }
  var cookie: String { string(raw["rawCookie"]) }
  var user: UserProfile { UserProfile(raw: object(raw["user"])) }
  var authenticated: Bool { !bduss.isEmpty && !stoken.isEmpty && !userID.isEmpty }
}
struct ContentPart: Identifiable {
  let id = UUID()
  var type: Int
  var text: String
  var url: URL?
  var thumbnail: URL?
  var sourceID: String
  var caption: String
  var width: Int
  var height: Int
  static func parse(_ value: Any?) -> [ContentPart] {
    if let text = value as? String { return [ContentPart(type: 0, text: stripHTML(text), sourceID: "", caption: "", width: 0, height: 0)] }
    return records(value).map { part in
      let type = integer(part["type"])
      let size = string(part["bsize"]).split(separator: ",").map(String.init)
      var target = first(part, [3, 20].contains(type) ? ["origin_src", "big_cdn_src", "big_src", "dynamic", "cdn_src", "cdn_src_active", "src"] : ["link", "src", "text"])
      var text = string(part["text"])
      let sourceID = type == 2 ? text : string(part["uid"])
      let caption = string(part["c"])
      if type == 2 {
        if text.range(of: "^image_emoticon[0-9]+$", options: .regularExpression) != nil { target = "https://tieba.baidu.com/tb/editor/images/client/\(text).png" }
        if !caption.isEmpty { text = "#(\(caption))" }
      }
      if type == 10 {
        let voice = string(part["voice_md5"])
        target = voice.isEmpty ? "" : "https://tiebac.baidu.com/c/p/voice?voice_md5=\(urlEncode(voice))&play_from=pb_voice_play"
      }
      return ContentPart(type: type, text: text, url: safeURL(target), thumbnail: safeURL(first(part, ["cdn_src", "src", "big_src"])), sourceID: sourceID, caption: caption,
                         width: integer(part["width"] ?? size.first), height: integer(part["height"] ?? (size.count > 1 ? size[1] : "")))
    }
  }
}
struct ThreadSummary: Identifiable {
  var raw: JSON
  var author: UserProfile
  var forum: Forum
  var id: String { first(raw, ["id", "tid", "thread_id"]) }
  var title: String { stripHTML(string(raw["title"])) }
  var excerpt: String {
    let value = raw["abstract"] ?? raw["abstract_thread"] ?? raw["rich_abstract"] ?? raw["first_post_content"]
    return stripHTML(value == nil ? first(raw, ["content", "content_thread", "_abstract"]) : ContentPart.parse(value).map(\.text).joined())
  }
  var replies: Int { integer(raw["reply_num"] ?? raw["post_num"] ?? raw["count"]) }
  var likes: Int { integer(raw["agree_num"] ?? raw["like_num"] ?? object(raw["agree"])["agree_num"]) }
  var liked: Bool { boolean(object(raw["agree"])["has_agree"] ?? raw["user_agree"]) }
  var saved: Bool { boolean(raw["is_collect"] ?? raw["collect_status"]) }
  var pinned: Bool { boolean(raw["is_top"]) }
  var digest: Bool { boolean(raw["is_good"]) }
  var video: URL? { safeURL(string(object(raw["video_info"])["video_url"])) }
  var anchor: String { first(raw, ["mark_pid", "collect_mark_pid", "post_id", "pid"]) }
  var images: [URL] { records(raw["media"]).compactMap { safeURL(first($0, ["small_pic", "big_pic", "origin_pic", "src", "water_pic"])) } }
  init(_ raw: JSON, forum: Forum? = nil, users: [String: JSON] = [:]) {
    self.raw = raw
    var user = object(raw["author"] ?? raw["user"])
    if user.isEmpty { user = users[string(raw["author_id"] ?? raw["user_id"])] ?? ["id": string(raw["author_id"] ?? raw["user_id"]), "name": string(raw["user_name"]), "portrait": string(raw["user_portrait"])] }
    self.author = UserProfile(raw: user)
    var forumData: JSON = ["forum_id": string(raw["forum_id"]), "forum_name": string(raw["forum_name"])]
    forumData.merge(object(raw["forum_info"])) { _, next in next }
    self.forum = forum ?? Forum(raw: forumData)
  }
}
struct Post: Identifiable {
  let id: String
  var threadID: String
  var parentID: String
  var author: UserProfile
  var floor: Int
  var time: Date?
  var content: [ContentPart]
  var replyCount: Int
  var replies: [Post]
  var liked: Bool
  var likes: Int
  var plainText: String { content.map(\.text).joined() }
  func isOriginalPoster(_ ownerID: String?) -> Bool {
    guard let ownerID, !ownerID.isEmpty, ownerID != "0" else { return false }
    return author.id == ownerID
  }
  init(_ raw: JSON, threadID: String, users: [String: JSON] = [:], parentID: String = "") {
    id = first(raw, ["id", "pid", "post_id"]); self.threadID = threadID; self.parentID = parentID
    let data = object(raw["author"])
    author = UserProfile(raw: data.isEmpty ? users[string(raw["author_id"])] ?? ["id": string(raw["author_id"])] : data)
    floor = integer(raw["floor"])
    let seconds = integer(raw["time"])
    time = seconds > 0 ? Date(timeIntervalSince1970: Double(seconds > 100_000_000_000 ? seconds / 1000 : seconds)) : nil
    content = ContentPart.parse(raw["content"])
    let nested = object(raw["sub_post_list"])
    replyCount = integer(raw["sub_post_number"] ?? nested["sub_post_number"])
    replies = records(nested["sub_post_list"]).map { Post($0, threadID: threadID, users: users, parentID: first(raw, ["id", "pid", "post_id"])) }
    liked = boolean(object(raw["agree"])["has_agree"]); likes = integer(object(raw["agree"])["agree_num"])
  }
}
struct PageResult<T> {
  var items: [T] = []
  var page = 1
  var hasMore = false
  var forum: Forum?
  var thread: ThreadSummary?
  var total = 0
  var raw: JSON = [:]
}
func urlEncode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")) ?? "" }
