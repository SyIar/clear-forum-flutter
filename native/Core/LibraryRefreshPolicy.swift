import Foundation

enum LibraryRefreshPolicy {
  static let interval: TimeInterval = 3_600
  static func isDue(checkedAt: Date?, attemptedAt: Date?, manual: Bool, now: Date = Date()) -> Bool {
    // Manual checks may retry failures, but never bypass a recent success.
    if let checkedAt, now.timeIntervalSince(checkedAt) < interval { return false }
    if !manual, let attemptedAt, now.timeIntervalSince(attemptedAt) < interval { return false }
    return true
  }
}
