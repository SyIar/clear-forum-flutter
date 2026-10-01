import SwiftUI
import UIKit
import ChunUI

public struct ForumEdgeBlur: View {
  public var bottom: Bool
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  public init(bottom: Bool = false) { self.bottom = bottom }
  private static var supportsVariableBlur: Bool {
    let selector = NSSelectorFromString("filterWithType:")
    guard let type = NSClassFromString("CAFilter") as? NSObject.Type,
          type.responds(to: selector), let result = type.perform(selector, with: "variableBlur") else { return false }
    return result.takeUnretainedValue() is NSObject
  }
  public var body: some View {
    Group {
      if !reduceTransparency, Self.supportsVariableBlur {
        VariableBlurView(maxBlurRadius: 14,
          direction: bottom ? .blurredBottomClearTop : .blurredTopClearBottom)
      } else {
        LinearGradient(colors: bottom ? [.clear, .black.opacity(0.55)] : [.black.opacity(0.45), .clear],
                       startPoint: .top, endPoint: .bottom)
      }
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}

// Use ChunUI's shader locally. Its public fire() API owns a fullscreen window,
// which would highlight unrelated rows and obscure the item being updated.
public struct ForumBookmarkUpdate: ViewModifier {
  public let maximum: Int?
  public let enabled: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var started: Date?
  @State private var token = 0
  public init(maximum: Int?, enabled: Bool) { self.maximum = maximum; self.enabled = enabled }
  public func body(content: Content) -> some View {
    content.overlay {
      if let started, !reduceMotion {
        GeometryReader { geometry in
          TimelineView(.animation) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(started))
            let progress = 1 - pow(1 - min(1, elapsed / 0.62), 4)
            let alpha = elapsed <= 0.62 ? 0.25 : max(0, 0.25 * (1 - (elapsed - 0.62) / 0.26))
            Rectangle().fill(.white).colorEffect(CCShaders.glimmSweep(
              .float2(Float(geometry.size.width), Float(geometry.size.height)),
              .float(Float(elapsed)), .float(Float(progress)), .float(Float(alpha)),
              .float(0), .float3(0.2, 0.65, 1), .float(0.85)))
          }
        }.clipShape(RoundedRectangle(cornerRadius: 12))
          .allowsHitTesting(false).accessibilityHidden(true)
      }
    }
    .onChange(of: maximum) { previous, current in
      guard enabled, let previous, let current, current > previous, !reduceMotion else { return }
      started = Date(); token += 1
    }
    .task(id: token) {
      guard started != nil else { return }
      do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
      started = nil
    }
    .onDisappear { started = nil }
  }
}
