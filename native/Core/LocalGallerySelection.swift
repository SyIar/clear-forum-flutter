import Foundation

/// Keep a stable folder snapshot while the viewer is open, even if downloads finish.
public struct LocalGallerySelection: Sendable {
  public let files: [LocalFileEntry]
  public let initialIndex: Int
  public init?(entries: [LocalFileEntry], selected: [String]) {
    files = entries.filter { !$0.directory }
    guard let index = files.firstIndex(where: { $0.path == selected }) else { return nil }
    initialIndex = index
  }
  public func neighbor(of index: Int, offset: Int) -> Int? {
    guard files.indices.contains(index), offset == -1 || offset == 1 else { return nil }
    let next = index + offset
    return files.indices.contains(next) ? next : nil
  }
}

public enum LocalGalleryDrag {
  public static func canBegin(x: Double, y: Double, zoomed: Bool) -> Bool {
    !zoomed && y > 0 && y > abs(x) * 1.25
  }
  public static func shouldClose(distance: Double, velocity: Double, height: Double) -> Bool {
    guard height > 0, distance > 0 else { return false }
    let threshold = min(180, max(96, height * 0.2))
    return (distance >= threshold && velocity > -150) || (distance >= 28 && velocity > 900)
  }
}
