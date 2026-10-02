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
  func testOriginalPosterMatchesLaterRepliesByIDNotDisplayName() throws {
    let sameName = post(1).replacingOccurrences(of: "User 1", with: "User 0")
    let ownerReply = post(2).replacingOccurrences(of: "uid-102", with: "uid-100")
    let result = try parse(post(0) + sameName + ownerReply)
    let library = LibraryDocument(site: .south)
    XCTAssertEqual(result.originalPosterID, "100")
    XCTAssertEqual(result.posts.map { library.isOriginalPoster($0, in: result) }, [true, false, true])
    XCTAssertFalse(LibraryDocument(site: .simp).isOriginalPoster(result.posts[0], in: result))
  }
  func testVerifiedGFHeaderIdentifiesOwnerWhenOpeningLaterPagesDirectly() throws {
    let source = post(8).replacingOccurrences(of: "Only this author", with: "\u{53EA}\u{770B}GF")
    let later = URL(string: "https://south-plus.net/read.php?tid=20&page=2")!
    let parsed = try ForumParser().parse(source, url: later)
    XCTAssertEqual(parsed.originalPosterID, "108")
    XCTAssertTrue(LibraryDocument(site: .south).isOriginalPoster(parsed.posts[0], in: parsed))
    let restored = try JSONDecoder().decode(ForumPage.self, from: JSONEncoder().encode(parsed))
    XCTAssertEqual(restored.originalPosterID, "108")
    for destination in ["read.php?tid-99-uid-108.html", "read.php?tid-20-uid-999.html",
                        "https://example.com/read.php?tid-20-uid-108.html"] {
      let invalid = source.replacingOccurrences(of: "read.php?tid-20-uid-108.html", with: destination)
      XCTAssertNil(try ForumParser().parse(invalid, url: later).originalPosterID)
    }
    let quoted = "<blockquote><div class='tiptop'><a href='read.php?tid-20-uid-108.html'>\u{53EA}\u{770B}GF</a></div></blockquote>Reply"
    XCTAssertNil(try parse(post(8, content: quoted)).originalPosterID)
    let filtered = URL(string: "https://south-plus.net/read.php?tid-20-uid-108.html")!
    XCTAssertNil(try ForumParser().parse(post(8), url: filtered).originalPosterID)
  }
  func testLegacyCachedPageAndKnownOwnerRemainUsableWithoutNewMetadata() throws {
    let page = try parse(post(0))
    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
    raw.removeValue(forKey: "originalPosterID")
    let legacy = try JSONDecoder().decode(ForumPage.self, from: JSONSerialization.data(withJSONObject: raw))
    XCTAssertNil(legacy.originalPosterID)
    var library = LibraryDocument(site: .south)
    XCTAssertTrue(library.isOriginalPoster(legacy.posts[0], in: legacy))
    library.capturePresentation(legacy)
    let later = try parse(post(8).replacingOccurrences(of: "uid-108", with: "uid-100"))
    XCTAssertNil(later.originalPosterID)
    XCTAssertTrue(library.isOriginalPoster(later.posts[0], in: later))
    var unknown = later.posts[0]; unknown.authorID = nil
    XCTAssertFalse(library.isOriginalPoster(unknown, in: later))
    var otherThread = later; otherThread.url = URL(string: "https://south-plus.net/read.php?tid=99")!
    XCTAssertFalse(library.isOriginalPoster(later.posts[0], in: otherThread))
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
  func testGeneratedAttachmentLabelsAreOmittedWithoutDroppingImagesOrCaptions() throws {
    let label = "\u{56fe}\u{7247}\u{ff1a}"
    let attachments = (1...3).map { index in
      "<div id='att_\(index)'> \(label) <br><img src='//south-plus.net/attachment/Mon_2609/sample-\(index).jpeg'><p>Caption \(index)</p></div>"
    }.joined()
    let html = post(0, content: label + " Body text")
      .replacingOccurrences(of: "<div class=\"f14\" id=\"read_tpc\">", with: attachments + "<div class=\"f14\" id=\"read_tpc\">")
    let value = try XCTUnwrap(parse(html).posts.first)
    XCTAssertEqual(value.blocks.filter { $0.kind == .image }.count, 3)
    let text = value.blocks.flatMap(\.runs).map(\.text).joined()
    XCTAssertEqual(text.components(separatedBy: label).count - 1, 1)
    for index in 1...3 { XCTAssertTrue(text.contains("Caption \(index)")) }
    XCTAssertTrue(text.contains(label + " Body text"))
  }
  func testAttachmentLikeTextInAuthorBodyAndOtherFilesIsPreserved() throws {
    let label = "\u{56fe}\u{7247}:"
    let body = "<div id='att_1'>\(label)<br><img src='/attachment/Mon_2609/inline.jpeg'></div>"
    let download = "<div id='att_2'>\(label)<br><a href='/attachment/file.zip'>Download file</a></div>"
    let html = post(0, content: body)
      .replacingOccurrences(of: "<div class=\"f14\" id=\"read_tpc\">", with: download + "<div class=\"f14\" id=\"read_tpc\">")
    let text = try parse(html).posts.flatMap(\.blocks).flatMap(\.runs).map(\.text).joined()
    XCTAssertEqual(text.components(separatedBy: label).count - 1, 2)
    XCTAssertTrue(text.contains("Download file"))
  }

  private func fileAttachment(_ id: Int, postID: String = "9001", query: Bool = false) -> String {
    let address = query ? "job.php?action=download&amp;pid=\(postID)&amp;tid=20&amp;aid=\(id)" :
      "job.php?action-download-pid-\(postID)-tid-20-aid-\(id).html"
    return """
      <div style="margin:5px 0" class="f12" id="att_\(id)">
        \u{9644}\u{4ef6}\u{ff1a} <img src="images/colorImagination/file/zip.gif" align="absmiddle">
        <a id="fg_\(id)" href="\(address)" target="_blank"><font color="red">Collection-\(id).zip</font></a>
        (1762 K) \u{4e0b}\u{8f7d}\u{6b21}\u{6570}:320
      </div>
      """
  }
  private func footer(_ html: String, index: Int = 1, content: String? = nil) -> String {
    let key = index == 0 ? "tpc" : String(9000 + index)
    return post(index, content: content).replacingOccurrences(of: "<div id=\"w_\(key)\" class=\"c\"></div>",
      with: html + "<div id='w_\(key)' class='c'></div>")
  }
  func testSecondRowFileAttachmentBelongsToOriginalPost() throws {
    let result = try parse(post(0) + footer(fileAttachment(81)) + post(2))
    XCTAssertEqual(result.posts.count, 3)
    let value = result.posts[1]
    XCTAssertEqual(value.id, "post_9001")
    XCTAssertEqual(value.number, "#1")
    XCTAssertEqual(value.authorID, "101")
    XCTAssertEqual(value.blocks.map(\.kind), [.paragraph, .link, .paragraph])
    XCTAssertEqual(value.blocks[1].label, "Collection-81.zip")
    XCTAssertEqual(value.blocks[1].url?.absoluteString, "https://south-plus.net/job.php?action-download-pid-9001-tid-20-aid-81.html")
    XCTAssertEqual(value.blocks[2].runs.map(\.text).joined(), "(1762 K) \u{4e0b}\u{8f7d}\u{6b21}\u{6570}:320")
    XCTAssertEqual(result.posts[0].blocks.count, 1)
    XCTAssertEqual(result.posts[2].blocks.count, 1)
    XCTAssertFalse(PostTextExport.text(in: value.blocks).contains("signature"))
  }
  func testAttachmentOnlySecondRowDoesNotBecomeAnEmptyCard() throws {
    let value = try XCTUnwrap(parse(footer(fileAttachment(81), content: "")).posts.first)
    XCTAssertEqual(value.number, "#1")
    XCTAssertEqual(value.blocks.map(\.kind), [.link, .paragraph])
  }
  func testPurchaseGateAndSecondRowFileBothRemainPresent() throws {
    let gate = """
      <h6 class="quote jumbotron"><span class="s3">\u{6b64}\u{5e16}\u{552e}\u{4ef7} 0 SP\u{5e01}</span>
      <input type="button" onclick="location.href='job.php?action=buytopic&amp;tid=20&amp;pid=9001&amp;verify=synthetic'"></h6>
      """
    let result = try parse(footer(fileAttachment(81), content: gate))
    XCTAssertEqual(result.purchaseOffers.count, 1)
    XCTAssertEqual(result.posts.first?.blocks.map(\.kind), [.purchase, .link, .paragraph])
    XCTAssertEqual(result.posts.first?.blocks[1].url?.path, "/job.php")
  }
  func testFileAttachmentsInsideBodyAndFooterKeepOrderWithoutDuplicates() throws {
    let html = footer(fileAttachment(81) + fileAttachment(82, query: true), content: fileAttachment(81))
    let blocks = try XCTUnwrap(parse(html).posts.first).blocks
    XCTAssertEqual(blocks.filter { $0.kind == .link }.map(\.label), ["Collection-81.zip", "Collection-82.zip"])
    XCTAssertEqual(blocks.filter { $0.kind == .link }.last?.url?.query, "action=download&pid=9001&tid=20&aid=82")
    XCTAssertFalse(blocks.contains { $0.kind == .image })
  }
  func testFooterImageStillWorksWithoutCapturingSignatureOrQuotedAttachments() throws {
    let html = footer("<div id='att_81'><img src='/attachment/sample.jpeg'></div>" +
      "<blockquote>\(fileAttachment(82))</blockquote><div class='signature'>\(fileAttachment(83))</div>")
    let blocks = try XCTUnwrap(parse(html).posts.first).blocks
    XCTAssertEqual(blocks.map(\.kind), [.paragraph, .image])
    XCTAssertEqual(blocks.last?.url?.path, "/attachment/sample.jpeg")
  }
  func testSharedTableCannotAssignFooterAttachmentsToMultipleBodies() throws {
    let html = """
      <table class="js-post"><tr><td><div class="tpc_content"><div id="read_9001">First</div>
      <div id="read_9002">Second</div></div></td></tr><tr><td><div class="tpc_content">
      \(fileAttachment(81))</div></td></tr></table>
      """
    let result = try parse(html)
    XCTAssertEqual(result.posts.count, 2)
    XCTAssertEqual(result.posts.map { $0.blocks.flatMap(\.runs).map(\.text).joined() }, ["First", "Second"])
  }
  func testFileDecorationRuleDoesNotConsumeUnrelatedLinks() throws {
    let html = fileAttachment(81).replacingOccurrences(of: "action-download-", with: "action-other-")
    let blocks = try XCTUnwrap(parse(post(1, content: html)).posts.first).blocks
    XCTAssertTrue(blocks.contains { $0.kind == .image })
    XCTAssertTrue(blocks.flatMap(\.runs).contains { $0.url?.query?.contains("action-other-") == true })
  }
}
