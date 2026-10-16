import Foundation

/// One seek at a time; intermediate slider positions never form a backlog.
struct VideoScrubState {
  struct Request: Equatable {
    let id = UUID()
    let seconds: Double
  }
  enum Completion: Equatable { case ignored, waiting, next(Request), finished, failed }
  private var active = false
  private var released = false
  private var pending: Double?
  private var current: Request?

  mutating func begin() { self = Self(); active = true }
  mutating func cancel() { self = Self() }
  mutating func update(_ seconds: Double) -> Request? {
    guard active, seconds.isFinite, seconds >= 0 else { return nil }
    pending = seconds
    guard current == nil else { return nil }
    let request = Request(seconds: seconds); current = request; pending = nil
    return request
  }
  mutating func end(_ seconds: Double) -> Request? {
    guard active else { return nil }
    released = true
    return update(seconds)
  }
  mutating func complete(_ request: Request, succeeded: Bool) -> Completion {
    guard active, current == request else { return .ignored }
    current = nil
    if let target = pending, target != request.seconds {
      return update(target).map(Completion.next) ?? .ignored
    }
    pending = nil
    if !succeeded { cancel(); return .failed }
    if released { cancel(); return .finished }
    return .waiting
  }
}
