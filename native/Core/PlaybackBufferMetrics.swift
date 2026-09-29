import Foundation

struct PlaybackBufferMetrics {
  let fraction: Double?
  let secondsAhead: Double

  // Merge ranges before counting coverage: seeking can leave gaps or overlaps.
  init(ranges: [(start: Double, end: Double)], duration: Double, position: Double) {
    let total = duration.isFinite && duration > 0 ? duration : nil
    let valid = ranges.compactMap { range -> (Double, Double)? in
      guard range.start.isFinite, range.end.isFinite else { return nil }
      let start = max(0, range.start)
      let end = min(range.end, total ?? range.end)
      return end > start ? (start, end) : nil
    }.sorted { $0.0 < $1.0 }
    var merged: [(Double, Double)] = []
    for range in valid {
      if let last = merged.last, range.0 <= last.1 {
        merged[merged.count - 1].1 = max(last.1, range.1)
      } else { merged.append(range) }
    }
    let covered = merged.reduce(0) { $0 + $1.1 - $1.0 }
    fraction = total.map { min(1, max(0, covered / $0)) }
    secondsAhead = position.isFinite
      ? merged.first(where: { $0.0 <= position && position <= $0.1 }).map { $0.1 - position } ?? 0
      : 0
  }
}

struct PlaybackTransferRate {
  private var previous: (bytes: Int64, duration: Double)?
  private var estimate: (rate: Double, timestamp: Double)?

  // Access-log counters arrive in batches. Report recent measured throughput,
  // not a fabricated per-second reading or the video's encoded bitrate.
  mutating func sample(bytes: Int64?, transferDuration: Double?, now: Double) -> Double? {
    guard let bytes, bytes >= 0, let duration = transferDuration,
          duration.isFinite, duration >= 0, now.isFinite else {
      previous = nil; estimate = nil
      return nil
    }
    if let previous {
      if bytes < previous.bytes || duration < previous.duration {
        estimate = nil
        self.previous = (bytes, duration)
      } else if bytes > previous.bytes, duration > previous.duration {
        let rate = Double(bytes - previous.bytes) / (duration - previous.duration)
        estimate = rate.isFinite && rate > 0 ? (rate, now) : nil
        self.previous = (bytes, duration)
      }
    } else {
      previous = (bytes, duration)
      // The first entry is an average since this item's transfer began.
      if bytes > 0, duration > 0 {
        let rate = Double(bytes) / duration
        if rate.isFinite { estimate = (rate, now) }
      }
    }
    guard let estimate, now >= estimate.timestamp, now - estimate.timestamp <= 5 else { return nil }
    return estimate.rate
  }
}
