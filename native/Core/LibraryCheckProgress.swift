import Foundation

struct LibraryCheckProgress {
  var running = false
  var total = 0
  var completed = 0
  var updated = 0
  var failed = 0
  var finishedAt: Date?
  var skippedFresh = false
  var currentTitle: String?
  private var threadAttempts: [String: UUID] = [:]
  private(set) var threadFailures: [String: ReaderFailure] = [:]

  init(running: Bool = false, total: Int = 0, skippedFresh: Bool = false) {
    self.running = running
    self.total = total
    self.skippedFresh = skippedFresh
  }

  mutating func beginThread(_ key: String) -> UUID {
    resolveThread(key)
    let token = UUID()
    threadAttempts[key] = token
    return token
  }

  // A live foreground read supersedes an older background request, even before
  // its last-page lookup finishes. Cached reading never calls this method.
  mutating func supersedeThread(_ key: String) {
    threadAttempts.removeValue(forKey: key)
  }

  @discardableResult mutating func resolveThread(_ key: String) -> Bool {
    supersedeThread(key)
    guard threadFailures.removeValue(forKey: key) != nil else { return false }
    failed = max(0, failed - 1)
    return true
  }

  @discardableResult mutating func failThread(_ key: String, attempt: UUID, reason: ReaderFailure) -> Bool {
    guard threadAttempts[key] == attempt else { return false }
    threadAttempts.removeValue(forKey: key)
    if threadFailures[key] == nil { failed += 1 }
    threadFailures[key] = reason
    return true
  }
}
