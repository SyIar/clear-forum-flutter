import ForumUI
import SwiftUI

@MainActor
final class ReadingSettings: ObservableObject {
  static let shared = ReadingSettings()
  @Published var value: ReadingAppearance {
    didSet { if let data = try? JSONEncoder().encode(value.normalized) { UserDefaults.standard.set(data, forKey: "bookhouse.appearance") } }
  }
  private init() {
    value = UserDefaults.standard.data(forKey: "bookhouse.appearance")
      .flatMap { try? JSONDecoder().decode(ReadingAppearance.self, from: $0) }?.normalized ?? ReadingAppearance()
  }
}

private struct ReadingAppearanceKey: EnvironmentKey { static let defaultValue = ReadingAppearance() }
extension EnvironmentValues {
  var readingAppearance: ReadingAppearance {
    get { self[ReadingAppearanceKey.self] }
    set { self[ReadingAppearanceKey.self] = newValue }
  }
}
extension ReadingAppearance {
  var background: Color {
    switch theme { case .system: return Color(uiColor: .systemBackground); case .paper: return Color(red: 0.97, green: 0.94, blue: 0.86); case .night: return Color(red: 0.07, green: 0.075, blue: 0.08) }
  }
  var foreground: Color { theme == .paper ? Color(red: 0.20, green: 0.17, blue: 0.13) : theme == .night ? Color(white: 0.85) : .primary }
}

struct ReadingSettingsView: View {
  @ObservedObject private var settings = ReadingSettings.shared
  @ObservedObject private var offline = BookhouseOfflineStore.shared
  @Environment(\.dismiss) private var nativeDismiss
  @Environment(\.forumDismiss) private var forumDismiss
  var body: some View {
    NavigationStack {
      Form {
        Section(AppText.text("Reading appearance")) {
          adjustment("Text size", key: \.fontSize, range: 16...32)
          adjustment("Line spacing", key: \.lineSpacing, range: 2...18)
          adjustment("Paragraph spacing", key: \.paragraphSpacing, range: 6...30)
          adjustment("Side margins", key: \.margin, range: 12...40)
          Picker(AppText.text("Background"), selection: $settings.value.theme) {
            Text(AppText.text("System")).tag(ReadingAppearance.Theme.system)
            Text(AppText.text("Paper")).tag(ReadingAppearance.Theme.paper)
            Text(AppText.text("Night")).tag(ReadingAppearance.Theme.night)
          }
          Button(AppText.text("Reset reading appearance")) { settings.value = ReadingAppearance() }
        }
        Section(AppText.text("Offline chapters")) {
          Text(AppText.text("Cache the next five chapters from a book's menu in My reading. Only chapter text is kept offline; images still need a connection."))
            .appFont(.caption).foregroundStyle(.secondary)
          Picker(AppText.text("Cache limit"), selection: Binding(get: { offline.limitMB }, set: { offline.setLimit($0) })) {
            ForEach([50, 100, 250], id: \.self) { Text("\($0) MB").tag($0) }
          }
          Text(ByteCountFormatter.string(fromByteCount: Int64(offline.bytes), countStyle: .file)).foregroundStyle(.secondary)
          Button(AppText.text("Clear offline chapters"), role: .destructive) { offline.clear() }.disabled(offline.busy)
          if let error = offline.error { Text(error).foregroundStyle(.secondary) }
        }
      }.appFont(.body).navigationTitle(AppText.text("Reading settings")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
          Button(AppText.text("Done")) { if forumDismiss.available { forumDismiss() } else { nativeDismiss() } }
        } }
    }.presentationDetents([.medium, .large])
  }
  private func adjustment(_ title: String, key: WritableKeyPath<ReadingAppearance, Double>, range: ClosedRange<Double>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack { Text(AppText.text(title)); Spacer(); Text(Int(settings.value[keyPath: key]).formatted()).monospacedDigit().foregroundStyle(.secondary) }
      Slider(value: Binding(get: { settings.value[keyPath: key] }, set: { settings.value[keyPath: key] = $0 }), in: range, step: 1)
        .accessibilityLabel(AppText.text(title))
    }
  }
}
