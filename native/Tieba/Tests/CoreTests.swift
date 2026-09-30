import Foundation
import XCTest
@testable import TiebaCore

final class CoreTests: XCTestCase {
  func testLegacyDartProtobufWireCompatibility() throws {
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!) }
    XCTAssertEqual(try ProtoCodec.encode("PbPage", json: fixture("anchor-request.json")), try fixture("anchor-request.bin"))
    let response = normalized(try ProtoCodec.decode("PbPage", bytes: fixture("anchor-response.bin")))
    let data = object(response["data"])
    XCTAssertEqual(integer(object(data["page"])["current_page"]), 7)
    XCTAssertFalse(boolean(object(data["page"])["has_more"]))
    let user = records(data["user_list"])[0]
    let post = Post(records(data["post_list"])[0], threadID: "123", users: ["42": user])
    XCTAssertEqual(post.author.name, "Author")
    XCTAssertEqual(post.content.map(\.type), [9, 20, 2, 10])
    XCTAssertEqual(post.content[1].width, 80)
    XCTAssertEqual(post.content[3].url?.query, "voice_md5=voice-id&play_from=pb_voice_play")
  }
  @MainActor func testLegacyFormSignatureVector() {
    XCTAssertEqual(TiebaTransport.sign(["b": "two", "a": "x y", "sign": "ignored"]), "1D9722E384CAA1E7693DB1062F7ADFEA")
    XCTAssertEqual(Array(DeviceCipher.rc442(Data("Plaintext".utf8), key: Data("Key".utf8))), [0x91, 0xd9, 0x3c, 0xc2, 0xf3, 0x6a, 0x85, 0x20, 0xf9])
  }
  func testLegacyFIFOAndAccountNamespaces() throws {
    let defaults = UserDefaults(suiteName: "TiebaCoreTests.\(UUID())")!
    var library = try LocalLibrary.load(account: "123", defaults: defaults)
    for value in 1...6 { library.visit(Forum(raw: ["id": String(value), "name": "Forum\(value)"])) }
    library.visit(Forum(raw: ["id": "3", "name": "Forum3", "memberCount": 42]))
    XCTAssertEqual(library.recentForums.map(\.name), ["Forum6", "Forum5", "Forum4", "Forum3", "Forum2"])
    XCTAssertEqual(library.recentForums[3].members, 42)
    try library.save(account: "123", defaults: defaults)
    XCTAssertEqual(LocalLibrary.key(account: "123"), "flutter.tieba_lite.local.v1.MTIz")
    XCTAssertEqual(try LocalLibrary.load(account: "123", defaults: defaults).recentForums.count, 5)
    XCTAssertTrue(try LocalLibrary.load(account: "456", defaults: defaults).recentForums.isEmpty)
  }
  func testCorruptDataIsPreserved() {
    let defaults = UserDefaults(suiteName: "TiebaCoreTests.\(UUID())")!
    defaults.set("invalid", forKey: LocalLibrary.key(account: nil))
    XCTAssertThrowsError(try LocalLibrary.load(account: nil, defaults: defaults))
    XCTAssertEqual(defaults.string(forKey: LocalLibrary.key(account: nil)), "invalid")
  }
  func testLegacyRecentForumsMigrateWithoutInventingDates() throws {
    let defaults = UserDefaults(suiteName: "TiebaCoreTests.\(UUID())")!
    let old = LocalLibrary(document: ["version": 1, "history": [], "pins": [], "search": [], "blocks": [], "drafts": [], "recentForums": [["id": "1", "name": "Original"]]])
    try old.save(account: nil, defaults: defaults)
    let migrated = try LocalLibrary.load(account: nil, defaults: defaults)
    XCTAssertEqual(migrated.rows("forumHistory").count, 1)
    XCTAssertEqual(Forum(raw: object(migrated.rows("forumHistory")[0]["forum"])).name, "Original")
    XCTAssertNil(migrated.rows("forumHistory")[0]["visitedAt"])
  }
  func testUnknownMemberCountAndCheckIn() {
    var forum = Forum(raw: ["id": "1", "name": "Example"])
    XCTAssertNil(forum.members)
    forum.signed = true
    XCTAssertTrue(Forum(raw: forum.stored).signed)
  }
  func testContentMappingAndProtocolNormalization() {
    let data = normalized(["postList": [["authorId": "123"]]])
    XCTAssertEqual(string(records(data["post_list"])[0]["author_id"]), "123")
    let parts = ContentPart.parse([["type": 3, "origin_src": "http://example.test/image.jpg", "bsize": "600,400"], ["type": 10, "voice_md5": "abc"]])
    XCTAssertEqual(parts[0].url?.scheme, "https")
    XCTAssertEqual(parts[0].width, 600)
    XCTAssertEqual(parts[1].url?.host, "tiebac.baidu.com")
  }
  func testBlockAllowOverrideAndKeywordConjunction() throws {
    var library = LocalLibrary(document: ["blocks": []])
    library.addBlock(kind: "keyword", value: "one two", label: "Test")
    XCTAssertFalse(library.blocked(text: "one", extraText: "two"))
    XCTAssertTrue(library.blocked(text: "two and one"))
    library.addBlock(kind: "user", value: "123", label: "User")
    library.addBlock(kind: "user", value: "reader", label: "User", allow: true)
    XCTAssertFalse(library.blocked(user: UserProfile(raw: ["id": "123", "username": "reader"])))
  }
  func testVerificationCipherRoundTrip() throws {
    let key = Data("abcdefghijklmnop".utf8), input = Data("sample verification payload".utf8)
    XCTAssertEqual(try DeviceCipher.aes(DeviceCipher.aes(input, key: key, encrypt: true), key: key, encrypt: false), input)
    XCTAssertEqual(DeviceCipher.rc442(DeviceCipher.rc442(input, key: key), key: key), input)
    XCTAssertEqual(Array(try DeviceCipher.gzip(input).prefix(2)), [31, 139])
  }
}
