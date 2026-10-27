import SwiftUI

public struct ForumOriginalPosterBadge: View {
  private let label: String
  public init(label: String) { self.label = label }
  public var body: some View {
    Image(systemName: "person.fill")
      .font(.caption).foregroundStyle(.blue)
      .accessibilityLabel(Text(label))
  }
}
