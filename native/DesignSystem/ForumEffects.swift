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
        FeatheredEdgeBlur(bottom: bottom)
      } else {
        LinearGradient(colors: bottom ? [.clear, .black.opacity(0.55)] : [.black.opacity(0.45), .clear],
                       startPoint: .top, endPoint: .bottom)
      }
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}

// Mask a containing view, not UIVisualEffectView itself, so backdrop sampling
// remains live. The alpha fade also covers systems that restore a uniform blur.
private struct FeatheredEdgeBlur: UIViewRepresentable {
  let bottom: Bool
  func makeUIView(context: Context) -> EdgeBlurContainer { EdgeBlurContainer(bottom: bottom) }
  func updateUIView(_ view: EdgeBlurContainer, context: Context) { view.setDirection(bottom: bottom) }
}

private final class EdgeBlurContainer: UIView {
  private var bottom: Bool
  private var blur: VariableBlurUIView
  private let fade = CAGradientLayer()
  init(bottom: Bool) {
    self.bottom = bottom
    blur = VariableBlurUIView(maxBlurRadius: 14, direction: bottom ? .blurredBottomClearTop : .blurredTopClearBottom)
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    addSubview(blur)
    fade.startPoint = CGPoint(x: 0.5, y: 0)
    fade.endPoint = CGPoint(x: 0.5, y: 1)
    layer.mask = fade
    configureFade()
  }
  required init?(coder: NSCoder) { return nil }
  func setDirection(bottom: Bool) {
    guard self.bottom != bottom else { return }
    self.bottom = bottom
    blur.removeFromSuperview()
    blur = VariableBlurUIView(maxBlurRadius: 14, direction: bottom ? .blurredBottomClearTop : .blurredTopClearBottom)
    addSubview(blur)
    configureFade()
    setNeedsLayout()
  }
  private func configureFade() {
    let colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
    fade.colors = bottom ? colors : Array(colors.reversed())
    fade.locations = bottom ? [0, 0.8, 1] : [0, 0.2, 1]
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    blur.frame = bounds
    fade.frame = bounds
    CATransaction.commit()
  }
}

public enum ForumRefreshPhase: Equatable {
  case checking, checked, updated, failed
}

// Keep the animated feedback in an inset side rail, away from reading text.
public struct ForumRefreshFeedback: ViewModifier {
  public let phase: ForumRefreshPhase?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var visible = false
  @State private var started: Date?
  @State private var completion: Date?
  public init(phase: ForumRefreshPhase?) { self.phase = phase }
  public func body(content: Content) -> some View {
    content
    .padding(.horizontal, 12).padding(.vertical, 10)
    .overlay(alignment: .leading) {
      if visible, scenePhase == .active, !reduceMotion, let start = completion ?? started {
        GeometryReader { geometry in
          TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(start))
            let repeating = phase == .checking
            let time = repeating ? elapsed.truncatingRemainder(dividingBy: 1.6) : elapsed
            let duration = repeating ? 1.25 : 0.62
            let raw = min(1, time / duration)
            let progress = repeating ? raw : 1 - pow(1 - raw, 4)
            let peak = repeating ? 0.14 : 0.28
            let alpha = time <= duration ? peak : max(0, peak * (1 - (time - duration) / 0.26))
            Rectangle().fill(.white).colorEffect(CCShaders.glimmSweep(
              .float2(Float(geometry.size.width), Float(geometry.size.height)),
              .float(Float(time)), .float(Float(progress)), .float(Float(alpha)),
              .float(0), .float3(0.2, 0.65, 1), .float(0.85)))
          }
        }.frame(width: 3).padding(.vertical, 12).clipShape(Capsule())
          .allowsHitTesting(false).accessibilityHidden(true)
      }
    }
    .onChange(of: phase) { previous, current in
      started = current == .checking ? Date() : nil
      completion = previous == .checking && current == .updated && visible &&
        scenePhase == .active && !reduceMotion ? Date() : nil
    }
    .task(id: completion) {
      guard completion != nil else { return }
      do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
      completion = nil
    }
    .onChange(of: scenePhase) { _, current in
      completion = nil
      started = current == .active && phase == .checking ? Date() : nil
    }
    .onAppear { visible = true; started = phase == .checking ? Date() : nil; completion = nil }
    .onDisappear { visible = false; started = nil; completion = nil }
  }
}
