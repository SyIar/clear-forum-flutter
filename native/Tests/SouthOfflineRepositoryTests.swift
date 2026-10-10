import Foundation
import XCTest
@testable import ForumCore

final class SouthOfflineRepositoryTests: XCTestCase {
  private let root = URL(string: "https://south-plus.net/read.php?tid=123")!
  private func page(_ number: Int, total: Int = 3) -> ForumPage {
    ForumPage(url: SouthSitePolicy.pageURL(root, number: number)!, title: "Saved thread", kind: .posts, entries: [],
      posts: [ForumPost(id: "post-\(number)", author: "Author", date: "2026-10-10", number: String(number),
        blocks: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Offline text \(number)")])])],
      pageNumber: number, totalPages: total)
  }
  private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

  func testResumeAcrossRestartAndOfflinePagination() async throws {
    let folder = directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = SouthOfflineRepository(directory: folder)
    let queued = try await repository.enqueue(url: root, title: "Thread")
    let token = try XCTUnwrap(queued.entries.first?.token)
    _ = try await repository.store(page(1), token: token, expectedPage: 1)
    let restarted = SouthOfflineRepository(directory: folder)
    let resumed = try await restarted.snapshot()
    XCTAssertEqual(resumed.entries[0].state, .pending)
    XCTAssertEqual(resumed.entries[0].savedPages, [1])
    XCTAssertEqual(resumed.entries[0].totalPages, 3)
    let beforeDownload = try await restarted.page(SouthSitePolicy.pageURL(root, number: 2)!, threadID: "123")
    XCTAssertNil(beforeDownload)
    _ = try await restarted.store(page(2), token: token, expectedPage: 2)
    _ = try await restarted.store(page(3), token: token, expectedPage: 3)
    let complete = try await restarted.finish(token, missingImages: 0)
    XCTAssertEqual(complete.entries[0].state, .complete)
    let final = SouthOfflineRepository(directory: folder)
    let middle = try await final.page(SouthSitePolicy.pageURL(root, number: 2)!, threadID: "123")
    XCTAssertEqual(middle?.previous, root)
    XCTAssertEqual(middle?.next, SouthSitePolicy.pageURL(root, number: 3))
    XCTAssertEqual(middle?.posts[0].blocks[0].runs[0].text, "Offline text 2")
    let last = try await final.page(SouthSitePolicy.pageURL(root, number: 3)!, threadID: "123")
    XCTAssertNil(last?.next)
  }

  func testUnfilteredIdentityAndRejectWrongPages() async throws {
    let folder = directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = SouthOfflineRepository(directory: folder)
    let filtered = URL(string: "https://south-plus.net/read.php?tid-123-uid-456-page-2.html")!
    let snapshot = try await repository.enqueue(url: filtered, title: "Thread")
    let entry = snapshot.entries[0]
    XCTAssertEqual(entry.url, root)
    var wrong = page(1)
    wrong.url = filtered
    do { _ = try await repository.store(wrong, token: entry.token, expectedPage: 1); XCTFail("Must not save an author-filtered response") }
    catch { XCTAssertEqual(error as? ReaderFailure, .unsupported) }
    wrong.url = URL(string: "https://south-plus.net/read.php?tid=999")!
    do { _ = try await repository.store(wrong, token: entry.token, expectedPage: 1); XCTFail("Must reject a different thread") }
    catch { XCTAssertEqual(error as? ReaderFailure, .unsupported) }
    do { _ = try await repository.store(page(1), token: entry.token, expectedPage: 2); XCTFail("Must reject a redirect to page one") }
    catch { XCTAssertEqual(error as? ReaderFailure, .unsupported) }
    _ = try await repository.store(page(1), token: entry.token, expectedPage: 1)
    let unreadable = try await repository.page(filtered, threadID: entry.id)
    XCTAssertNil(unreadable)
  }

  func testIncompletePagesAndFailedImagesCannotBecomeComplete() async throws {
    let folder = directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = SouthOfflineRepository(directory: folder)
    let queued = try await repository.enqueue(url: root, title: "Thread")
    let token = queued.entries[0].token
    _ = try await repository.store(page(1, total: 2), token: token, expectedPage: 1)
    do { _ = try await repository.finish(token, missingImages: 0); XCTFail("Missing pages cannot be complete") }
    catch { XCTAssertEqual(error as? ReaderFailure, .storage) }
    let failed = try await repository.finish(token, missingImages: 0, failure: "Network unavailable")
    XCTAssertEqual(failed.entries[0].state, .failed)
    let retry = try await repository.enqueue(url: root, title: "Thread")
    XCTAssertEqual(retry.entries[0].token, token)
    XCTAssertEqual(retry.entries[0].savedPages, [1])
    _ = try await repository.store(page(2, total: 2), token: token, expectedPage: 2)
    let partial = try await repository.finish(token, missingImages: 2)
    XCTAssertEqual(partial.entries[0].state, .partial)
    XCTAssertEqual(partial.entries[0].missingImages, 2)
    _ = try await repository.enqueue(url: root, title: "Thread")
    let complete = try await repository.finish(token, missingImages: 0)
    XCTAssertEqual(complete.entries[0].state, .complete)
  }

  func testImageDeduplicationAndViewerCopyPreservePersistentAsset() async throws {
    let folder = directory(), source = directory()
    defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: source) }
    try Data([1, 2, 3, 4]).write(to: source)
    let repository = SouthOfflineRepository(directory: folder)
    let queued = try await repository.enqueue(url: root, title: "Thread")
    let token = queued.entries[0].token
    let url = URL(string: "https://south-plus.net/attachment/image.jpg")!
    let first = try await repository.storeImage(source, url: url, token: token)
    let second = try await repository.storeImage(source, url: url, token: token)
    XCTAssertEqual(first.entries[0].bytes, second.entries[0].bytes)
    XCTAssertEqual(second.entries[0].imageCount, 1)
    let restarted = SouthOfflineRepository(directory: folder)
    let copied = try await restarted.copyImageForViewer(url, threadID: "123")
    let copy = try XCTUnwrap(copied)
    let cached = try await restarted.imageFile(url, threadID: "123")
    XCTAssertNotEqual(copy, cached)
    try FileManager.default.removeItem(at: copy)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(cached)), Data([1, 2, 3, 4]))
  }

  func testDeletedThreadRejectsLateWriteAndCanBeDownloadedAgain() async throws {
    let folder = directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = SouthOfflineRepository(directory: folder)
    let first = try await repository.enqueue(url: root, title: "Thread")
    let oldToken = first.entries[0].token
    _ = try await repository.remove(oldToken)
    let second = try await repository.enqueue(url: root, title: "New copy")
    XCTAssertNotEqual(second.entries[0].token, oldToken)
    do { _ = try await repository.store(page(1), token: oldToken, expectedPage: 1); XCTFail("A removed download must stay removed") }
    catch is CancellationError { }
    let restored = try await repository.snapshot()
    XCTAssertEqual(restored.entries[0].title, "New copy")
    XCTAssertTrue(restored.entries[0].savedPages.isEmpty)
  }

  func testImageDiscoveryIncludesNestedContentButNotDownloadsOrVideos() {
    let image = URL(string: "https://south-plus.net/attachment/picture.jpg")!
    let original = URL(string: "https://south-plus.net/attachment/original.jpg")!
    let video = URL(string: "https://example.com/movie.mp4")!
    var value = page(1)
    value.posts[0].blocks = [
      BodyBlock(kind: .quote, children: [BodyBlock(kind: .image, url: image, original: original)]),
      BodyBlock(kind: .image, url: image),
      BodyBlock(kind: .link, url: URL(string: "https://south-plus.net/job.php?action=download")!),
      BodyBlock(kind: .media, url: video, poster: image),
      BodyBlock(kind: .image, url: URL(string: "file:///etc/passwd")!)
    ]
    XCTAssertEqual(SouthOfflineImages.urls(in: value), [image, original])
  }
}
