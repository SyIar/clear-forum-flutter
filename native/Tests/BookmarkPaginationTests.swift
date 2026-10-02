import Foundation
import XCTest
@testable import ForumCore

final class BookmarkPaginationTests: XCTestCase {
  private func url(_ suffix: String = "page-48#post-941") -> URL {
    URL(string: "https://simpcity.cr/threads/example.42/" + suffix)!
  }
  private func parsedPage(number: Int = 48, total: Int = 49) throws -> ForumPage {
    let html = """
      <html data-template="thread_view">
        <h1 class="p-title-value">Example</h1>
        <article id="post-9001" class="message--post">
          <div class="message-attribution-opposite"><a>#941</a></div>
          <div class="message-body"><div class="bbWrapper">Example post</div></div>
        </article>
        <span class="pageNav-page--current">\(number)</span>
        <a class="js-pageJump" data-last="\(total)">Jump</a>
      </html>
      """
    return try ForumParser().parse(html, url: url("page-\(number)"))
  }
  private func library(at destination: URL? = nil) -> LibraryDocument {
    var result = LibraryDocument()
    result.toggle(SavedPage(url: destination ?? url(), title: "My label", titleIsCustom: true))
    return result
  }

  func testOpeningUsesCurrentBookmarkAndOnlyNextVisitUsesNewPage() throws {
    var library = library()
    let saved = try XCTUnwrap(library.bookmarks.first)
    let opened = library.bookmarkDestination(for: saved)
    let page = try parsedPage()
    XCTAssertNil(page.maximumPostNumber)
    library.remember(SavedPage(url: opened, title: page.title))
    library.recordLatestPage(page)

    XCTAssertEqual(opened, url())
    XCTAssertEqual(page.url, url("page-48"))
    XCTAssertEqual(library.recent.first?.url, opened)
    XCTAssertEqual(library.bookmarkDestination(for: saved), url("page-49"))
    XCTAssertEqual(library.bookmarks, [saved])
    XCTAssertNil(library.threads["42"]?.seenMaximum)
    XCTAssertNil(library.threads["42"]?.checkedAt)
  }

  func testLoadedHTMLAdvancesDestinationInsideRefreshCooldown() throws {
    var library = library()
    let checked = Date(timeIntervalSince1970: 100)
    library.threads["42"] = ThreadReadState(seenMaximum: 940, latestMaximum: 941, checkedAt: checked, attemptedAt: checked)
    let before = try XCTUnwrap(library.threads["42"])
    library.recordLatestPage(try parsedPage())
    XCTAssertEqual(library.bookmarkDestination(for: library.bookmarks[0]), url("page-49"))
    let after = try XCTUnwrap(library.threads["42"])
    XCTAssertEqual(after.checkedAt, before.checkedAt)
    XCTAssertEqual(after.attemptedAt, before.attemptedAt)
    XCTAssertEqual(after.seenMaximum, before.seenMaximum)
    XCTAssertEqual(after.latestMaximum, before.latestMaximum)
    XCTAssertTrue(after.updated)
  }

  func testOlderResponsesAndCachedPagesCannotRegressDestination() throws {
    var library = library()
    library.recordLatestPage(try parsedPage(total: 51))
    library.recordLatestPage(try parsedPage(total: 49))
    library.recordLatestPage(try parsedPage(number: 48, total: 48))
    XCTAssertEqual(library.bookmarkDestination(for: library.bookmarks[0]), url("page-51"))
  }

  func testTerminalPageDiscoveredByFloorCheckAdvancesAgain() throws {
    var library = library()
    library.recordLatestPage(try parsedPage())
    let terminal = try parsedPage(number: 50, total: 50)
    XCTAssertEqual(terminal.maximumPostNumber, 941)
    library.recordLatestPage(terminal)
    XCTAssertEqual(library.bookmarkDestination(for: library.bookmarks[0]), url("page-50"))
  }

  func testQueryURLsAliasesAndLabelsSurvivePersistence() throws {
    let imported = url("?page=48#post-941")
    let alias = URL(string: "https://simpcity.cr/threads/old-name.42/page-47")!
    var library = library(at: imported)
    library.toggle(SavedPage(url: alias, title: "Other label", titleIsCustom: true))
    let original = library.bookmarks
    library.recordLatestPage(try parsedPage())
    let suite = "BookmarkPaginationTests-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try library.save(to: defaults)
    let restored = try LibraryDocument.load(from: defaults)
    XCTAssertEqual(restored.bookmarks, original)
    XCTAssertEqual(Set(restored.bookmarks.map(\.id)).count, 2)
    XCTAssertEqual(restored.bookmarks.map { SitePolicy.pageNumber(restored.bookmarkDestination(for: $0)) }, [49, 49])
    XCTAssertNil(restored.bookmarkDestination(for: restored.bookmarks[0]).fragment)
    XCTAssertEqual(restored.threads["42"]?.latestPageNumber, 49)
  }

  func testLegacyLibraryKeepsImportedPageUntilNewPaginationArrives() throws {
    let source = #"{"version":1,"bookmarks":[{"url":"https://simpcity.cr/threads/example.42/?page=48#post-941","title":"My label"}],"recent":[],"threads":{"42":{"seenMaximum":940,"latestMaximum":941}}}"#
    var library = try JSONDecoder().decode(LibraryDocument.self, from: Data(source.utf8))
    let saved = try XCTUnwrap(library.bookmarks.first)
    XCTAssertNil(library.threads["42"]?.latestPageNumber)
    XCTAssertEqual(library.bookmarkDestination(for: saved), saved.url)
    library.recordLatestPage(try parsedPage())
    XCTAssertEqual(library.bookmarkDestination(for: saved), url("page-49"))
  }

  func testLatestDestinationHasBookmarkIndicatorAndCanBeRemovedAfterSlugRedirect() throws {
    var library = library()
    library.recordLatestPage(try parsedPage())
    let redirected = URL(string: "https://simpcity.cr/threads/renamed.42/page-49#post-950")!
    XCTAssertTrue(library.containsBookmark(redirected))
    XCTAssertTrue(library.containsBookmark(url()))
    XCTAssertFalse(library.containsBookmark(url("page-50")))
    library.toggle(SavedPage(url: redirected, title: "Example"))
    XCTAssertTrue(library.bookmarks.isEmpty)
    library.pruneTracking()
    XCTAssertNil(library.threads["42"])
  }

  func testRemovingOriginalRowDoesNotRemoveOtherSavedAliases() throws {
    var library = library()
    let second = SavedPage(url: url("page-47"), title: "Another label", titleIsCustom: true)
    library.toggle(second)
    library.recordLatestPage(try parsedPage())
    library.toggle(SavedPage(url: url(), title: "My label"))
    XCTAssertEqual(library.bookmarks, [second])
    XCTAssertTrue(library.containsBookmark(url("page-49")))
  }

  func testUnchangedPaginationPreservesImportedFragmentAndDoesNotMoveBackward() throws {
    var library = library()
    library.recordLatestPage(try parsedPage(number: 47, total: 48))
    XCTAssertEqual(library.bookmarkDestination(for: library.bookmarks[0]), url())
  }

  func testDirectoriesSortedViewsAndOtherForumsKeepTheirDestinations() throws {
    let normal = try parsedPage()
    var library = library()
    var directory = normal
    directory.kind = .threads
    library.recordLatestPage(directory)
    var sorted = normal
    sorted.url = url("page-48?order=reaction_score")
    library.recordLatestPage(sorted)
    var foreignPagination = normal
    foreignPagination.lastPage = URL(string: "https://simpcity.cr/threads/other.99/page-999")!
    library.recordLatestPage(foreignPagination)
    var empty = normal
    empty.posts = []
    library.recordLatestPage(empty)
    XCTAssertTrue(library.threads.isEmpty)
    XCTAssertEqual(library.bookmarkDestination(for: library.bookmarks[0]), url())
    library.recordLatestPage(normal)
    let forum = SavedPage(url: URL(string: "https://simpcity.cr/forums/example.9/page-2")!, title: "Forum")
    XCTAssertEqual(library.bookmarkDestination(for: forum), forum.url)
    let ordered = SavedPage(url: sorted.url, title: "Sorted")
    XCTAssertEqual(library.bookmarkDestination(for: ordered), ordered.url)
    for site in [ForumSite.south, .bookhouse] {
      var other = LibraryDocument(site: site)
      other.recordLatestPage(normal)
      XCTAssertTrue(other.threads.isEmpty)
      XCTAssertEqual(other.bookmarkDestination(for: library.bookmarks[0]), url())
    }
  }
}
