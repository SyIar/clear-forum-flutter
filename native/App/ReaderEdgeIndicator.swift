import SwiftUI

struct ReaderEdgePull: Equatable {
  var top = 0
  var bottom = 0
  var remaining = Int.max
  var offset = 0
  init() {}
  init(_ geometry: ScrollGeometry) {
    let metrics = ReaderScrollMetrics(contentOffset: Double(geometry.contentOffset.y),
      contentHeight: Double(geometry.contentSize.height), viewportHeight: Double(geometry.containerSize.height),
      topInset: Double(geometry.contentInsets.top), bottomInset: Double(geometry.contentInsets.bottom))
    top = Int(metrics.topPull.rounded())
    bottom = Int(metrics.bottomPull.rounded())
    remaining = Int(metrics.remaining.rounded())
    offset = Int(metrics.offset.rounded())
  }
}

// Geometry observations do not publish per-pixel changes to the entire reader.
// Only request/loading state changes need to redraw post cards.
final class ReaderScrollTracking {
  var pull = ReaderEdgePull()
  var trigger = ReaderEdgeTrigger()
  var peakTopPull = 0
  var peakBottomPull = 0
  func record(_ value: ReaderEdgePull, interacting: Bool) {
    pull = value
    if interacting {
      peakTopPull = max(peakTopPull, value.top)
      peakBottomPull = max(peakBottomPull, value.bottom)
    }
  }
}

struct ReaderEdgeFailure {
  let edge: ReaderEdge
  let message: String
}

struct ReaderEdgeIndicator: View {
  let edge: ReaderEdge
  let loading: Bool
  let failure: ReaderEdgeFailure?
  let retry: () -> Void
  var body: some View {
    if loading {
      ProgressView().padding(10).background(.regularMaterial, in: Capsule())
        .accessibilityLabel(edge == .previous ? AppText.text("Loading previous page") : AppText.text("Loading next page"))
    } else if let failure, failure.edge == edge {
      HStack(spacing: 8) {
        Text(failure.message).forumFont(.caption).lineLimit(3)
        Button(AppText.text("Retry"), action: retry).forumFont(.caption, weight: .bold)
      }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
  }
}
