import SwiftUI

private final class TiebaBundleAnchor: NSObject {}
enum TiebaResources {
  static let bundle = Bundle(for: TiebaBundleAnchor.self)
}

// Retain accounts and preferences across module switches without sharing forum sessions.
@MainActor public final class TiebaModuleSession: ObservableObject {
  let app = AppState()
  public fileprivate(set) var canReturnToForums = false
  public init() {}
}

private struct ExitTiebaKey: EnvironmentKey {
  static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
  var exitTieba: () -> Void {
    get { self[ExitTiebaKey.self] }
    set { self[ExitTiebaKey.self] = newValue }
  }
}

@MainActor public struct TiebaModuleView: View {
  private let session: TiebaModuleSession
  private let close: () -> Void
  public init(session: TiebaModuleSession, close: @escaping () -> Void) {
    self.session = session
    self.close = close
  }
  public var body: some View {
    AppRoot(onRootChange: { session.canReturnToForums = $0 })
      .environmentObject(session.app)
      .environmentObject(session.app.settings)
      .environment(\.exitTieba, close)
  }
}
