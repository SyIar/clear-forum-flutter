import Foundation

@MainActor
final class TiebaAPI {
  let transport: TiebaTransport
  private var tokens: [String: String] = [:]
  private var concernCursors = [1: ""]
  private var concernAccount = ""
  init(transport: TiebaTransport) { self.transport = transport }
  private func tbs(_ session: Session) -> String { tokens[session.userID] ?? session.tbs }
  private func common(posting: Bool = false, legacy: Bool = false) -> JSON {
    let session = transport.sessionProvider()
    var fields: JSON = ["_client_type": 2, "_client_version": posting ? "12.35.1.0" : legacy ? "11.10.8.6" : "12.52.1.0",
      "_client_id": "wappc_\(transport.deviceID.split(separator: "|").first ?? "")", "_timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
      "_os_version": "33", "model": "iPhone", "brand": "Apple", "from": "1020031h", "cuid": transport.deviceID,
      "cuid_galaxy2": transport.deviceID, "net_type": 1, "pversion": "1.0.3", "lego_lib_version": "3.0.0"]
    if let session {
      fields["BDUSS"] = session.bduss; fields["stoken"] = session.stoken
      if posting { fields["tbs"] = tbs(session) }
      if !session.zid.isEmpty { fields["z_id"] = session.zid }
    }
    return fields
  }
  private func proto(_ path: String, codec: String, _ fields: JSON, authenticated: Bool = false, outerToken: Bool = true, posting: Bool = false, legacy: Bool = false) async throws -> JSON {
    let account = transport.sessionProvider()?.userID
    var fields = fields
    fields["common"] = common(posting: posting, legacy: legacy)
    let result = try await transport.proto(path, codec: codec, fields: fields, authenticated: authenticated, outerToken: outerToken, posting: posting, legacy: legacy)
    if let account, let token = object(result["anti"])["tbs"] as? String, !token.isEmpty { tokens[account] = token }
    return result
  }
  private func hasMore(_ data: JSON, count: Int) -> Bool {
    if data["page"] is JSON { return boolean(object(data["page"])["has_more"]) }
    if let more = data["has_more"] { return boolean(more) }
    return count >= 15
  }
  private func users(_ value: Any?) -> [String: JSON] {
    Dictionary(records(value).map { (string($0["id"]), $0) }, uniquingKeysWith: { _, next in next })
  }
  private func content(_ record: JSON) -> Bool { record["ala_info"] == nil && record["advertisement"] == nil && integer(record["is_ad"]) == 0 }
  func login(bduss: String, stoken: String, cookie: String) async throws -> Session {
    guard !bduss.isEmpty, !stoken.isEmpty else { throw APIError(message: "Complete sign-in on the Baidu page first.") }
    var candidate = Session(raw: ["bduss": bduss, "stoken": stoken, "rawCookie": cookie])
    let result = try await transport.form("/c/s/login", ["bdusstoken": bduss + "|", "stoken": stoken, "channel_id": "", "channel_uid": "", "authsid": "null"], session: candidate, omit: ["BDUSS"])
    let user = UserProfile(raw: object(result["user"]))
    guard !user.id.isEmpty else { throw APIError(message: "The server did not return an account.") }
    _ = try await transport.form("/c/s/initNickname", ["BDUSS": bduss, "stoken": stoken], session: candidate)
    candidate.raw["userId"] = user.id; candidate.raw["user"] = user.stored
    candidate.tbs = string(object(result["anti"])["tbs"])
    tokens[user.id] = candidate.tbs
    candidate.zid = (try? await transport.fetchZid()) ?? ""
    return candidate
  }
  func followedForums() async throws -> [Forum] {
    let session = try transport.requireSession()
    let data = try await transport.form("/c/f/forum/getforumlist", ["user_id": session.userID], authenticated: true)
    return records(data["forum_info"]).map { raw in var raw = raw; raw["is_like"] = 1; return Forum(raw: raw) }
  }
  func batchSign(_ forums: [Forum]) async throws -> Set<String> {
    let session = try transport.requireSession()
    let info = try await transport.form("/c/f/forum/getforumlist", ["user_id": session.userID], authenticated: true)
    guard try transport.requireSession().userID == session.userID else { throw APIError(message: "The account changed before check-in.") }
    let allowed = Set(forums.filter { !$0.signed }.map(\.id))
    let candidates = records(info["forum_info"]).map { Forum(raw: $0) }.filter { allowed.contains($0.id) && !$0.signed && $0.level >= integer(info["level"]) }.prefix(max(0, integer(info["msign_step_num"])))
    guard !candidates.isEmpty else { return [] }
    let result = try await transport.form("/c/c/forum/msign", ["forum_ids": candidates.map(\.id).joined(separator: ","), "tbs": tbs(session), "authsid": "null", "stoken": session.stoken, "user_id": session.userID], authenticated: true, session: session)
    let requested = Set(candidates.map(\.id))
    return Set(records(result["info"]).filter { boolean($0["signed"]) }.map { string($0["forum_id"]) }.filter { requested.contains($0) })
  }
  func suggestions(_ query: String, forum: Bool = false) async throws -> [String] {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
    let data = try await proto("/c/s/searchSug?cmd=309438&format=protobuf", codec: "SearchSug", ["word": query, "isforum": forum ? "1" : "0"])
    return (data["list"] as? [Any] ?? []).map(string).filter { !$0.isEmpty }
  }
  func feed(_ kind: String, page: Int = 1) async throws -> PageResult<ThreadSummary> {
    var data: JSON
    var values: [JSON]
    var more: Bool
    switch kind {
    case "concern":
      let account = try transport.requireSession().userID
      if account != concernAccount || page == 1 { concernAccount = account; concernCursors = [1: ""] }
      guard let cursor = concernCursors[page] else { throw APIError(message: "Refresh the following feed before loading another page.") }
      data = try await proto("/c/f/concern/userlike?cmd=309474", codec: "UserLike", ["pageTag": cursor, "lastRequestUnix": String(Int(Date().timeIntervalSince1970)), "followType": 1, "loadType": page == 1 ? 1 : 2], authenticated: true)
      concernCursors[page + 1] = string(data["page_tag"])
      values = records(data["thread_info"]).map { object($0["thread_list"]) }.filter { !$0.isEmpty }
      more = boolean(data["has_more"])
    case "hot":
      if page > 1 { return PageResult(page: page) }
      data = try await proto("/c/f/forum/hotThreadList?cmd=309661", codec: "HotThreadList", ["tabId": "0", "tabCode": ""])
      values = records(data["thread_info"]); more = false
    default:
      data = try await proto("/c/f/excellent/personalized?cmd=309264", codec: "Personalized", ["pn": page, "load_type": page == 1 ? 1 : 2, "page_thread_count": 20, "q_type": 1, "new_net_type": 1])
      values = records(data["thread_list"]); more = !values.isEmpty
    }
    return PageResult(items: values.filter(content).map { ThreadSummary($0) }, page: page, hasMore: more, raw: data)
  }
  func forum(_ name: String, page: Int = 1, sort: Int = 0, digest: Bool = false) async throws -> PageResult<ThreadSummary> {
    let data = try await proto("/c/f/frs/page?cmd=301001", codec: "FrsPage", ["kw": urlEncode(name), "pn": page, "rn": 90, "rn_need": 30, "q_type": 2, "sort_type": sort, "load_type": page == 1 ? 1 : 2, "is_good": digest ? 1 : 0, "cid": 0, "st_type": "recom_flist", "with_group": 1])
    var forumData = object(data["forum"])
    if first(forumData, ["name", "forum_name"]).isEmpty { forumData["name"] = name }
    let forum = Forum(raw: forumData)
    let userMap = users(data["user_list"])
    let items = records(data["thread_list"]).filter(content).map { ThreadSummary($0, forum: forum, users: userMap) }
    return PageResult(items: items, page: page, hasMore: hasMore(data, count: items.count), forum: forum, raw: data)
  }
  func thread(_ id: String, page: Int = 1, onlyAuthor: Bool = false, reverse: Bool = false, anchor: String = "") async throws -> PageResult<Post> {
    let data = try await proto("/c/f/pb/page?cmd=302001&format=protobuf", codec: "PbPage", ["kz": id, "pn": anchor.isEmpty ? page : 0, "pid": anchor.isEmpty ? "0" : anchor, "lz": onlyAuthor ? 1 : 0, "r": reverse ? 1 : 0, "with_floor": 1, "floor_rn": 4, "floor_sort_type": 1, "rn": 15, "q_type": 2, "source_type": 2])
    let forum = Forum(raw: object(data["forum"]))
    let userMap = users(data["user_list"])
    let items = records(data["post_list"]).map { Post($0, threadID: id, users: userMap) }
    let pageInfo = object(data["page"])
    return PageResult(items: items, page: integer(pageInfo["current_page"]) > 0 ? integer(pageInfo["current_page"]) : page, hasMore: hasMore(data, count: items.count), forum: forum,
                      thread: ThreadSummary(object(data["thread"]), forum: forum, users: userMap), total: integer(pageInfo["total_count"]), raw: data)
  }
  func floor(threadID: String, postID: String, forumID: String, page: Int = 1) async throws -> PageResult<Post> {
    let data = try await proto("/c/f/pb/floor?cmd=302002&format=protobuf", codec: "PbFloor", ["kz": threadID, "pid": postID, "forum_id": forumID.isEmpty ? "0" : forumID, "pn": page], outerToken: false)
    let items = records(data["subpost_list"]).map { Post($0, threadID: threadID, parentID: postID) }
    return PageResult(items: items, page: page, hasMore: hasMore(data, count: items.count), forum: Forum(raw: object(data["forum"])), thread: ThreadSummary(object(data["thread"])), raw: data)
  }
  func searchForums(_ query: String) async throws -> [Forum] {
    let json = try await transport.web("/mo/q/search/forum", ["word": query])
    let data = object(json["data"]); let exact = object(data["exact_match"])
    var seen = Set<String>()
    return ((exact.isEmpty ? [] : [exact]) + records(data["fuzzy_match"]))
      .map { Forum(raw: $0) }.filter { !$0.name.isEmpty && seen.insert($0.id.isEmpty ? $0.name : $0.id).inserted }
  }
  func searchThreads(_ query: String, page: Int = 1, sort: Int = 0, forum: String = "") async throws -> PageResult<ThreadSummary> {
    var fields: JSON = ["word": query, "pn": page, "st": sort, "tt": 1, "ct": 1, "is_use_zonghe": 1, "cv": "99.9.101"]
    if !forum.isEmpty { fields["fname"] = forum }
    let json = try await transport.web("/mo/q/search/thread", fields)
    let data = object(json["data"])
    return PageResult(items: records(data["post_list"]).map { ThreadSummary($0) }, page: page, hasMore: boolean(data["has_more"]))
  }
  func searchUsers(_ query: String) async throws -> [UserProfile] {
    let json = try await transport.web("/mo/q/search/user", ["word": query])
    let data = object(json["data"]); let exact = object(data["exact_match"])
    var seen = Set<String>()
    return ((exact.isEmpty ? [] : [exact]) + records(data["fuzzy_match"])).map { UserProfile(raw: $0) }.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
  }
  func favorites(page: Int = 1) async throws -> PageResult<ThreadSummary> {
    let session = try transport.requireSession()
    let data = try await transport.form("/c/f/post/threadstore", ["rn": 30, "offset": (page - 1) * 30, "user_id": session.userID], authenticated: true)
    let items = records(data["store_thread"]).map { ThreadSummary($0) }
    return PageResult(items: items, page: page, hasMore: items.count >= 30)
  }
  func notifications(_ kind: String, page: Int = 1) async throws -> PageResult<JSON> {
    let endpoint = kind == "mentions" ? "atme" : kind == "likes" ? "agreeme" : "replyme"
    let json = try await transport.form("/c/u/feed/\(endpoint)", ["pn": page - 1], authenticated: true, version: "8.2.2")
    let key = kind == "mentions" ? "at_list" : kind == "likes" ? "agree_list" : "reply_list"
    let items = records(json[key] ?? json["reply_list"])
    return PageResult(items: items, page: page, hasMore: hasMore(json, count: items.count))
  }
  func notificationCounts() async throws -> JSON {
    object(try await transport.form("/c/s/msg", ["bookmark": 1], authenticated: true, version: "8.2.2")["message"])
  }
  func profile(_ id: String) async throws -> UserProfile {
    let me = transport.sessionProvider()?.userID ?? ""
    var fields: JSON = ["uid": me.isEmpty ? id : me, "is_guest": me == id ? 0 : 1, "has_plist": 1, "is_from_usercenter": 1, "need_post_count": 1, "page": 1, "pn": 1, "rn": 20]
    if me != id { fields["friend_uid"] = id }
    let data = try await proto("/c/u/user/profile?cmd=303012&format=protobuf", codec: "Profile", fields)
    return UserProfile(raw: object(data["user"]))
  }
  func userPosts(_ id: String, page: Int = 1, replies: Bool = false) async throws -> PageResult<ThreadSummary> {
    let data = try await proto("/c/u/feed/userpost?cmd=303002&format=protobuf", codec: "UserPost", ["uid": id, "pn": page, "offset": (page - 1) * 20, "rn": 20, "is_thread": replies ? 0 : 1, "need_content": 1])
    let items = records(data["post_list"]).map { ThreadSummary($0) }
    return PageResult(items: items, page: page, hasMore: items.count >= 20)
  }
  func userForums(_ id: String, page: Int = 1) async throws -> PageResult<Forum> {
    let me = transport.sessionProvider()?.userID ?? id
    let data = try await transport.form("/c/f/forum/like", ["page_no": page, "page_size": 50, "uid": me, "friend_uid": id, "is_guest": me == id ? 0 : 1], version: "7.2.0.0")
    let lists = object(data["forum_list"])
    let items = (lists.isEmpty ? records(data["forum_list"]) : records(lists["non-gconforum"]) + records(lists["gconforum"])).map { Forum(raw: $0) }
    return PageResult(items: items, page: page, hasMore: boolean(data["has_more"]))
  }
  func forumDetail(_ id: String) async throws -> Forum {
    let data = try await proto("/c/f/forum/getforumdetail?cmd=303021&format=protobuf", codec: "GetForumDetail", ["forum_id": id])
    return Forum(raw: object(data["forum_info"]))
  }
  func forumRules(_ id: String) async throws -> JSON {
    try await proto("/c/f/forum/forumRuleDetail?cmd=309690&format=protobuf", codec: "ForumRuleDetail", ["forum_id": id])
  }
  func hotOverview(code: String = "all") async throws -> JSON {
    try await proto("/c/f/forum/hotThreadList?cmd=309661", codec: "HotThreadList", ["tabId": "1", "tabCode": code], legacy: true)
  }
  func hotTopics() async throws -> [JSON] {
    let data = try await proto("/c/f/recommend/topicList?cmd=309289", codec: "TopicList", ["call_from": "newbang", "list_type": "all", "need_tab_list": "0", "fid": "0"], legacy: true)
    return records(data["topic_list"])
  }
  func topic(_ id: String, name: String, page: Int = 1) async throws -> PageResult<ThreadSummary> {
    let json = try await transport.web("/mo/q/newtopic/topicDetail", ["topic_id": id, "topic_name": name, "is_new": 0, "is_share": 1, "pn": page, "rn": 10, "offset": 0, "derivative_to_pic_id": ""])
    let data = object(json["data"])
    var items = page == 1 ? records(data["special_topic"]).flatMap { records($0["thread_list"]) } : []
    items += records(object(data["relate_thread"])["thread_list"]).map { row in var value = object(row["thread_info"]); value["user_agree"] = row["user_agree"]; return value }
    var seen = Set<String>()
    let threads = items.map { ThreadSummary($0) }.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    return PageResult(items: threads, page: page, hasMore: !threads.isEmpty && boolean(data["has_more"]), raw: data)
  }
  func sign(_ forum: Forum) async throws {
    let session = try transport.requireSession()
    _ = try await transport.form("/c/c/forum/sign", ["fid": forum.id, "kw": forum.name, "tbs": tbs(session)], authenticated: true)
  }
  func follow(_ forum: Forum, enabled: Bool) async throws {
    let session = try transport.requireSession()
    _ = try await transport.form(enabled ? "/c/c/forum/like" : "/c/c/forum/unfavolike", ["fid": forum.id, "kw": forum.name, "tbs": tbs(session)], authenticated: true, version: enabled ? "7.2.0.0" : "11.10.8.6")
  }
  func follow(_ user: UserProfile, enabled: Bool) async throws {
    let session = try transport.requireSession()
    guard !user.portrait.isEmpty else { throw APIError(message: "The profile has no portrait identifier.") }
    _ = try await transport.form(enabled ? "/c/c/user/follow" : "/c/c/user/unfollow", ["portrait": user.portrait, "tbs": tbs(session), "authsid": "null", "from_type": 2, "in_live": 0], authenticated: true)
  }
  func agree(thread: String, post: String? = nil, forum: String = "", undo: Bool = false) async throws {
    let session = try transport.requireSession()
    var fields: JSON = ["thread_id": thread, "obj_type": post == nil ? 1 : 3, "agree_type": 2, "op_type": undo ? 1 : 0, "forum_id": forum, "tbs": tbs(session), "personalized_rec_switch": 1]
    fields["post_id"] = post
    _ = try await transport.form("/c/c/agree/opAgree", fields, authenticated: true, version: "12.25.1.0")
  }
  func bookmark(thread: String, post: String = "", remove: Bool = false) async throws {
    let session = try transport.requireSession()
    let json = try JSONSerialization.data(withJSONObject: [["tid": thread, "pid": post.isEmpty ? "0" : post, "status": 1]])
    let fields: JSON = remove ? ["tid": thread, "fid": "null", "tbs": tbs(session), "user_id": session.userID] : ["data": String(decoding: json, as: UTF8.self)]
    _ = try await transport.form(remove ? "/c/c/post/rmstore" : "/c/c/post/addstore", fields, authenticated: true, version: "12.25.1.0")
  }
  func reply(content: String, forum: Forum, thread: String, parent: String = "", subpost: String = "", replyUser: String = "") async throws -> String {
    let session = try transport.requireSession()
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError(message: "Write a reply before sending.") }
    var fields: JSON = ["content": content, "fid": forum.id, "kw": forum.name, "tid": thread, "name_show": session.user.name,
      "anonymous": "1", "can_no_forum": "0", "entrance_type": "0", "floor_num": "0", "is_ad": "0", "is_addition": "0", "is_barrage": "0", "is_feedback": "0", "is_giftpost": "0", "is_pictxt": "0", "is_twzhibo_thread": "0", "new_vcode": "1", "takephoto_num": "0", "vcode_tag": "12"]
    if parent.isEmpty { fields["barrage_time"] = "0"; fields["post_from"] = "13" }
    else { fields["quote_id"] = parent; fields["repostid"] = parent; if subpost.isEmpty { fields["post_from"] = "0" } }
    if !subpost.isEmpty { fields["sub_post_id"] = subpost }
    if !replyUser.isEmpty { fields["reply_uid"] = replyUser }
    let data = try await proto("/c/c/post/add?cmd=309731&format=protobuf", codec: "AddPost", fields, authenticated: true, posting: true)
    let id = string(data["pid"])
    guard !id.isEmpty else { throw APIError(message: "The server did not confirm the reply. Check the thread before trying again.") }
    return id
  }
  func uploadImage(_ bytes: Data, width: Int, height: Int, forum: String, watermark: Int, original: Bool) async throws -> JSON {
    let account = try transport.requireSession().userID
    guard !bytes.isEmpty, bytes.count <= 10_485_760, width > 0, height > 0 else { throw APIError(message: "Choose an image smaller than 10 MiB.") }
    let chunk = 512_000
    let resource = TiebaTransport.md5(bytes).uppercased() + String(chunk)
    var result: JSON = [:]
    for start in stride(from: 0, to: bytes.count, by: chunk) {
      guard try transport.requireSession().userID == account else { throw APIError(message: "The account changed during upload.") }
      let end = min(start + chunk, bytes.count)
      var fields = ["alt": "json", "chunkNo": String(start / chunk + 1), "groupId": "1", "height": String(height), "width": String(width), "isFinish": end == bytes.count ? "1" : "0", "is_bjh": "0", "pic_water_type": String(watermark), "resourceId": resource, "saveOrigin": original ? "1" : "0", "size": String(bytes.count)]
      if !forum.isEmpty { fields["forum_name"] = forum; fields["small_flow_fname"] = forum }
      result = try await transport.upload("/c/s/uploadPicture", fields: fields, bytes: bytes.subdata(in: start..<end))
    }
    let picture = object(object(result["pic_info"])["origin_pic"])
    guard !string(picture["pic_url"]).isEmpty, !string(result["pic_id"]).isEmpty else { throw APIError(message: "The server did not confirm the uploaded image.") }
    return ["url": https(string(picture["pic_url"])), "pictureId": string(result["pic_id"]), "width": width, "height": height, "size": bytes.count]
  }
  func updateProfile(_ fields: JSON) async throws {
    var fields = fields
    fields.merge(["cam": "", "need_cam_decrypt": "1", "need_keep_nickname_flag": "0"]) { _, next in next }
    _ = try await transport.form("/c/c/profile/modify", fields, authenticated: true, version: "12.25.1.0")
  }
  func uploadPortrait(_ bytes: Data) async throws { _ = try await transport.upload("/c/c/img/portrait", fields: [:], bytes: bytes, field: "pic", version: "11.10.8.6") }
  func report(_ post: String) async throws -> JSON {
    try await transport.form("/c/f/ueg/checkjubao", ["category": "1", "pid": post], authenticated: true, version: "12.25.1.0")
  }
  func removeOwnContent(forum: Forum, thread: String, post: String? = nil, nested: Bool = false) async throws {
    let session = try transport.requireSession()
    var fields: JSON = ["fid": forum.id, "word": forum.name, "z": thread, "tbs": tbs(session), "src": 1, "is_vipdel": 0]
    if let post { fields["pid"] = post; fields["isfloor"] = nested ? 1 : 0; fields["src"] = nested ? 3 : 1; fields["delete_my_post"] = 1 }
    else { fields["delete_my_thread"] = 1; fields["is_frs_mask"] = 0 }
    _ = try await transport.form(post == nil ? "/c/c/bawu/delthread" : "/c/c/bawu/delpost", fields, authenticated: true, version: "12.25.1.0")
  }
}
