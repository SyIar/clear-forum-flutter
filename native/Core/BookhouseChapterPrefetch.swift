import Foundation

// One speculative chapter per reader. The edge loader awaits the same task,
// then falls back to its normal request if speculation failed.
@MainActor
final class BookhouseChapterPrefetch {
  private struct Request {
    let id: UUID
    let key: String
    let task: Task<ForumPage, Error>
  }
  private var request: Request?
  private var attemptedKey: String?

  @discardableResult
  func start(_ url: URL, load: @escaping @MainActor () async throws -> ForumPage) -> Bool {
    guard let key = BookhouseSitePolicy.threadKey(url), key != attemptedKey else { return false }
    cancel()
    attemptedKey = key
    request = Request(id: UUID(), key: key, task: Task(priority: .utility) { try await load() })
    return true
  }

  func take(_ url: URL) async -> ForumPage? {
    guard let active = request, active.key == BookhouseSitePolicy.threadKey(url) else { return nil }
    defer { if request?.id == active.id { request = nil } }
    do {
      let page = try await active.task.value
      guard !Task.isCancelled, request?.id == active.id else { return nil }
      return page
    } catch { return nil }
  }

  func cancel() {
    request?.task.cancel()
    request = nil
    attemptedKey = nil
  }
}
