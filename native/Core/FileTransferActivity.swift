import Foundation

enum FileTransferActivity {
  case waiting, resolving, downloading, saving, readingFolder

  // The plan retains its first item until a transfer has been saved. It is not
  // still queued once the scheduler has started processing it.
  func queuedCount(pending: Int, running: Bool) -> Int {
    max(0, pending - (running && self != .waiting ? 1 : 0))
  }
}
