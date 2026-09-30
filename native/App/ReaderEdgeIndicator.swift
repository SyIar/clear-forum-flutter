import SwiftUI

struct ReaderEdgePull: Equatable {
  var top = 0
  var bottom = 0
  init() {}
  init(_ geometry: ScrollGeometry) {
    let start = -geometry.contentInsets.top
    let end = max(start, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
    top = Int(max(0, start - geometry.contentOffset.y).rounded())
    bottom = Int(max(0, geometry.contentOffset.y - end).rounded())
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
        Text(failure.message).font(.forum(.caption)).lineLimit(3)
        Button(AppText.text("Retry"), action: retry).font(.forum(.caption, weight: .bold))
      }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
  }
}
