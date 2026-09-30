import Foundation
import XCTest
@testable import ForumCore

final class SouthPostStructureTests: XCTestCase {
  private let page = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  // Preserve the supplied PHPWind layout, with synthetic identities and content.
  private func post(_ index: Int, content: String? = nil, modernProfile: Bool = false) -> String {
    let key = index == 0 ? "tpc" : String(9000 + index)
    let profile = modernProfile ? "u.php?action=show&amp;uid=\(100 + index)" : "u.php?action-show-uid-\(100 + index).html"
    let avatar = index == 2 ? "https://images.example/avatar.png" : "images/face/\(index).gif"
    return """
      <table class="js-post" cellspacing="0" cellpadding="0" width="100%">
      <tr class="tr1">
        <th class="r_two" rowspan="2">
          <div><table><tr><td><a href="\(profile)"><img loading="lazy" src="\(avatar)"></a></td></tr></table></div>
          <div align="center"><a href="\(profile)"><strong>User \(index)</strong></a>
            <span class="user-info" style="display:none"><a href="\(profile)">Profile menu</a>UID: <span>\(100 + index)</span></span>
          </div>
        </th>
        <th class="r_one" id="td_\(key)">
          <div class="tiptop"><span class="fl"><a title="Copy post address">\(index == 0 ? "OP" : "B\(index)F")</a></span>
            <span class="fl gray" title="Posted twelve days ago">2026-09-18 14:59</span>
            <div class="fr"><a href="read.php?tid-20-uid-\(100 + index).html">Only this author</a>
              <a data-uid="\(100 + index)" data-name="User \(index)">Hide author</a>
            </div>
          </div>
          <div class="tpc_content"><div id="p_\(key)" class="c"></div>
            <div class="f14" id="read_\(key)">\(content ?? "Reply \(index)")</div>
          </div>
        </th>
      </tr>
      <tr class="tr1 r_one"><th><div class="tpc_content"><div id="w_\(key)" class="c"></div></div>
        <div class="tipad">Reply controls and signature</div>
      </th></tr></table>
      """
  }
  private func parse(_ posts: String) throws -> ForumPage {
    try ForumParser().parse("<html><h1 id='subject_tpc'>A sample thread</h1>\(posts)</html>", url: page)
  }
  func testThirtyOnePostsDoNotBecomeSixtyTwoCards() throws {
    let result = try parse((0...30).map { post($0) }.joined())
    XCTAssertEqual(result.posts.count, 31)
    XCTAssertEqual(Set(result.posts.map(\.id)).count, 31)
    for (index, value) in result.posts.enumerated() {
      XCTAssertEqual(value.id, index == 0 ? "post_tpc" : "post_\(9000 + index)")
      XCTAssertEqual(value.author, "User \(index)")
      XCTAssertEqual(value.authorID, String(100 + index))
      XCTAssertEqual(value.date, "2026-09-18 14:59")
      XCTAssertEqual(value.number, "#\(index)")
      XCTAssertEqual(value.blocks.count, 1)
      XCTAssertEqual(value.blocks.flatMap(\.runs).map(\.text).joined(), "Reply \(index)")
      XCTAssertNotNil(value.avatar)
      XCTAssertEqual(value.authorFilterURL?.query, "tid-20-uid-\(100 + index).html")
    }
  }
  func testRelativeAndExternalAvatarsUseTheCorrectAuthor() throws {
    let values = try parse(post(1) + post(2, modernProfile: true)).posts
    XCTAssertEqual(values[0].avatar?.absoluteString, "https://south-plus.net/images/face/1.gif")
    XCTAssertEqual(values[1].avatar?.absoluteString, "https://images.example/avatar.png")
    XCTAssertEqual(values[1].authorID, "102")
    XCTAssertEqual(values[1].author, "User 2")
  }
  func testQuotedProfilesAndDatesNeverReplacePostMetadata() throws {
    let body = """
      <blockquote><a href="u.php?uid=999"><strong>Quoted member</strong></a><time>2001-01-01</time></blockquote>
      Actual reply.
      """
    let value = try XCTUnwrap(parse(post(1, content: body)).posts.first)
    XCTAssertEqual(value.author, "User 1")
    XCTAssertEqual(value.authorID, "101")
    XCTAssertEqual(value.date, "2026-09-18 14:59")
    XCTAssertEqual(value.number, "#1")
  }
  func testAuthorFilterRejectsOtherThreadsAuthorsAndBodyLinks() throws {
    let original = "read.php?tid-20-uid-101.html"
    let quote = "<blockquote><div class='tiptop'><a href='\(original)'>Quoted action</a></div></blockquote>"
    for replacement in ["read.php?tid-99-uid-101.html", "read.php?tid-20-uid-999.html",
                        "read.php?tid-20-uid-0.html", "https://example.org/read.php?tid-20-uid-101.html", "#"] {
      let html = post(1).replacingOccurrences(of: original, with: replacement)
        .replacingOccurrences(of: "Reply 1", with: quote + "Reply 1")
      XCTAssertNil(try parse(html).posts.first?.authorFilterURL, replacement)
    }
  }
  func testAuthorFilterStartsAtFirstPageWithoutFragment() throws {
    let html = post(1).replacingOccurrences(of: "read.php?tid-20-uid-101.html", with: "read.php?tid=20&amp;uid=101&amp;page=3#post_9001")
    let target = try XCTUnwrap(parse(html).posts.first?.authorFilterURL)
    XCTAssertEqual(target.query, "tid-20-uid-101.html")
    XCTAssertNil(target.fragment)
  }
  func testEmojiAndMediaOnlyPostsAreNotConsideredEmpty() throws {
    let emoji = "<img src='images/post/smile/smallface/face077.gif'>"
    let video = "<video src='https://media.example/video.mp4'></video>"
    let values = try parse(post(1, content: emoji) + post(2, content: video)).posts
    XCTAssertEqual(values.count, 2)
    XCTAssertEqual(values[0].blocks.first?.runs.compactMap(\.emoticon).count, 1)
    XCTAssertEqual(values[1].blocks.first?.kind, .media)
  }
  func testEmptyCompatibilityPlaceholderIsSkipped() throws {
    let html = """
      <article class="post"><span class="author">Legacy member</span>
      <div data-post-body>Reply text</div><div class="tpc_content"><div id="w_old"></div></div></article>
      """
    let values = try parse(html).posts
    XCTAssertEqual(values.count, 1)
    XCTAssertEqual(values[0].author, "Legacy member")
    XCTAssertTrue(values[0].date.isEmpty)
  }
  func testUploadedAttachmentsBesideIdentifiedBodyKeepOrderAndPostIdentity() throws {
    let before = (1...3).map { index in
      "<div id='att_\(index)'><img src='//south-plus.net/attachment/Mon_2609/sample-\(index).jpeg' loading='lazy' referrerpolicy='no-referrer'></div>"
    }.joined()
    let after = "<div id='att_4'><img src='/attachment/Mon_2609/sample-4.jpeg'></div>"
    let html = post(0, content: "Caption")
      .replacingOccurrences(of: "<div class=\"f14\" id=\"read_tpc\">Caption</div>",
                            with: before + "<div class='f14' id='read_tpc'>Caption</div>" + after)
    let values = try parse(html + post(1)).posts
    XCTAssertEqual(values.count, 2)
    let first = try XCTUnwrap(values.first)
    XCTAssertEqual(first.id, "post_tpc")
    XCTAssertEqual(first.authorID, "100")
    XCTAssertEqual(first.number, "#0")
    XCTAssertEqual(first.blocks.map(\.kind), [.image, .image, .image, .paragraph, .image])
    XCTAssertEqual(first.blocks.filter { $0.kind == .image }.compactMap(\.url).map(\.absoluteString),
                   (1...4).map { "https://south-plus.net/attachment/Mon_2609/sample-\($0).jpeg" })
    XCTAssertEqual(first.blocks.flatMap(\.runs).map(\.text).joined(), "Caption")
    XCTAssertEqual(values[1].blocks.flatMap(\.runs).map(\.text).joined(), "Reply 1")
  }
  func testAttachmentOnlyPostIsRetainedWithoutFooterOrAvatarImages() throws {
    let image = "<div id='att_1'><img src='/attachment/Mon_2609/sample.jpeg'></div>"
    let html = post(0, content: "")
      .replacingOccurrences(of: "<div class=\"f14\" id=\"read_tpc\">", with: image + "<div class=\"f14\" id=\"read_tpc\">")
      .replacingOccurrences(of: "<div id=\"w_tpc\" class=\"c\"></div>", with: "<img src='/signature.jpeg'>Signature")
    let value = try XCTUnwrap(parse(html).posts.first)
    XCTAssertEqual(value.blocks.count, 1)
    XCTAssertEqual(value.blocks.first?.kind, .image)
    XCTAssertEqual(value.blocks.first?.url?.path, "/attachment/Mon_2609/sample.jpeg")
  }
  func testSharedOuterWrapperDoesNotMergeSeparatePosts() throws {
    let html = """
      <div class="tpc_content"><div id="read_tpc">First body</div>
      <div id="read_9001">Second body</div></div>
      """
    let values = try parse(html).posts
    XCTAssertEqual(values.count, 2)
    XCTAssertEqual(values.map { $0.blocks.flatMap(\.runs).map(\.text).joined() }, ["First body", "Second body"])
  }
}
