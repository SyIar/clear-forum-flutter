import UIKit

// iOS completion is acknowledged only after both delegate delivery and queue persistence.
enum FileBackgroundEvents {
  static let prefix = "dev.sylar.forumlite.files."
  private static var callbacks: [UUID: () -> Void] = [:]
  private static var delivered: Set<UUID> = []
  private static var settled: Set<UUID> = []
  static func identifier(_ id: UUID) -> String { prefix + id.uuidString }
  static func receive(_ identifier: String, completion: @escaping () -> Void) -> UUID? {
    guard identifier.hasPrefix(prefix), let id = UUID(uuidString: String(identifier.dropFirst(prefix.count))) else { completion(); return nil }
    callbacks[id] = completion; complete(id); return id
  }
  static func eventsReady(_ id: UUID) { delivered.insert(id); complete(id) }
  static func saved(_ id: UUID) { settled.insert(id); complete(id) }
  static func cancelOrphan(_ id: UUID) {
    let session = URLSession(configuration: .background(withIdentifier: identifier(id)))
    session.getAllTasks { tasks in
      tasks.forEach { $0.cancel() }; session.finishTasksAndInvalidate()
      DispatchQueue.main.async { saved(id); eventsReady(id) }
    }
  }
  private static func complete(_ id: UUID) {
    guard delivered.contains(id), settled.contains(id), let callback = callbacks.removeValue(forKey: id) else { return }
    delivered.remove(id); settled.remove(id); callback()
  }
}

final class FileBackgroundDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
    guard let id = FileBackgroundEvents.receive(identifier, completion: completionHandler) else { return }
    if let batch = HostedDownloadManager.shared.items.first(where: { $0.transferID == id }), batch.running || batch.canResume { batch.resume() }
    else if let batch = GofileDownloadManager.shared.items.first(where: { $0.transferID == id }), batch.running || batch.canResume { batch.resume() }
    else { FileBackgroundEvents.cancelOrphan(id) }
  }
}
