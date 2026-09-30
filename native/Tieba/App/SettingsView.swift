import SwiftUI
import PhotosUI

struct SettingsView: View {
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var cacheSize = 0
  @State private var clearing = false
  @State private var background: PhotosPickerItem?
  private let reading: [(String, String)] = [
    ("compactCards", "compactCards"), ("hideMedia", "hide"), ("hideReply", "hideReply"), ("blockVideo", "hideVideo"),
    ("imageDarkenWhenNightMode", "imageDarken"), ("homePageShowHistoryForum", "showRecentForums"), ("restoreReading", "restoreReading"),
    ("showBothUsernameAndNickname", "bothUserNames"), ("showTopForumInNormalList", "repeatPinnedForums"),
    ("hideForumIntroAndStat", "hideForumHeader"), ("showShortcutInThread", "threadShortcuts"), ("collectThreadSeeLz", "savedAuthorOnly"), ("collectThreadDescSort", "savedNewestFirst")]
  var body: some View {
    Form {
      Section(tr("appearance")) {
        Picker(tr("theme"), selection: settings.stringBinding("themeMode")) { Text(tr("systemTheme")).tag("system"); Text(tr("lightTheme")).tag("light"); Text(tr("darkTheme")).tag("dark") }
        HStack { Text(tr("fontSize")); Slider(value: Binding(get: { settings.fontScale }, set: { settings.set("fontScale", $0) }), in: 0.75...2, step: 0.05); Text(String(format: "%.0f%%", settings.fontScale * 100)).appFont(.caption).monospacedDigit() }
        HStack {
          Text(tr("accentColor")); Spacer()
          ForEach([0xFF007AFF, 0xFF34C759, 0xFFFF9500, 0xFFAF52DE, 0xFF808080], id: \.self) { value in
            Button { settings.set("customPrimaryColor", value) } label: {
              Circle().fill(Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)).frame(width: 24, height: 24)
                .overlay {
                  if Int(settings.number("customPrimaryColor")) == value { Image(systemName: "checkmark").appFont(.caption2, weight: .bold).foregroundStyle(.white) }
                }
            }
          }
        }
        HStack { Text(tr("cornerRadius")); Slider(value: Binding(get: { settings.number("radius") }, set: { settings.set("radius", $0) }), in: 8...28) }
        Toggle(tr("hideExplore"), isOn: settings.toggle("hideExplore"))
        NavigationLink(tr("backgroundTheme")) { BackgroundSettings() }

      }
      Section(tr("reading")) {
        ForEach(reading, id: \.0) { key, label in Toggle(tr(label), isOn: settings.toggle(key)) }
        Picker(tr("defaultSort"), selection: settings.stringBinding("defaultSortType")) { Text(tr("latestReply")).tag("reply"); Text(tr("latestPost")).tag("post") }
        Picker(tr("imageLoadPolicy"), selection: settings.stringBinding("imageLoadType")) { Text(tr("imageSmartOriginal")).tag("0"); Text(tr("imageSmartLoad")).tag("1"); Text(tr("imageAllOriginal")).tag("2"); Text(tr("imageNever")).tag("3") }
      }
      Section(tr("reply")) {
        TextField(tr("signature"), text: settings.stringBinding("littleTail"), axis: .vertical)
        Toggle(tr("replyWarningTitle"), isOn: settings.toggle("postOrReplyWarning"))
        Toggle(tr("originalImage"), isOn: settings.toggle("originalImages"))
        Picker(tr("watermark"), selection: settings.stringBinding("picWatermarkType")) { Text(tr("watermarkNone")).tag("0"); Text(tr("watermarkUsername")).tag("1"); Text(tr("watermarkForum")).tag("2") }
      }
      Section { Toggle(tr("autoCheckIn"), isOn: settings.toggle("autoSign")); if settings.flag("autoSign") { DatePicker(tr("autoCheckIn"), selection: Binding(get: { time }, set: { let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; settings.set("autoSignTime", formatter.string(from: $0)) }), displayedComponents: .hourAndMinute) }; Toggle(tr("slowCheckIn"), isOn: settings.toggle("signSlowMode")); Toggle(tr("officialBatchCheckIn"), isOn: settings.toggle("oksignUseOfficialOksign")) } header: { Text(tr("checkIn")) } footer: { Text(tr("autoCheckInBody")) }
      Section(tr("privacyAndFilters")) {
        Toggle(tr("hideBlocked"), isOn: settings.toggle("hideBlockedContent")); Toggle(tr("showBlockTip"), isOn: settings.toggle("showBlockTip"))
        NavigationLink(tr("privacyAndFilters")) { BlockRulesView() }
        LabeledContent(tr("imageCache"), value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
        Button(tr("clearImageCache"), role: .destructive) { clearing = true }
      }
      Section(tr("about")) {
        LabeledContent(tr("version"), value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") + ")")
        Link(tr("sourceCode"), destination: URL(string: "https://github.com/SyIar/clear-forum-flutter/tree/main/native/Tieba")!)
        Link(tr("upstreamProject"), destination: URL(string: "https://github.com/HuanCheng65/TiebaLite")!)
        NavigationLink(tr("licenses")) { LicenseView() }
      }
    }.accessibilityIdentifier("settings.form").navigationTitle(tr("settings")).task { cacheSize = PictureCache.shared.bytes }
      .confirmationDialog(tr("clearImageCacheConfirm"), isPresented: $clearing, titleVisibility: .visible) { Button(tr("clearImageCache"), role: .destructive) { do { try PictureCache.shared.clear(); cacheSize = PictureCache.shared.bytes } catch { app.error = error.localizedDescription } } }
  }
  private var time: Date { let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; return formatter.date(from: settings.text("autoSignTime")) ?? formatter.date(from: "09:00")! }
}

struct BlockRulesView: View {
  @EnvironmentObject private var app: AppState
  @State private var adding = false
  @State private var kind = "keyword"
  @State private var value = ""
  @State private var allow = false
  var body: some View {
    List {
      ForEach(Array(app.library.rows("blocks").enumerated()), id: \.offset) { index, rule in
        HStack { Image(systemName: boolean(rule["allow"]) ? "checkmark.shield" : "eye.slash"); VStack(alignment: .leading) { Text(first(rule, ["label", "value"])); Text(string(rule["kind"])).appFont(.caption).foregroundStyle(.secondary) } }
          .swipeActions { Button(tr("clear"), role: .destructive) { app.updateLibrary { var rules = $0.rows("blocks"); if rules.indices.contains(index) { rules.remove(at: index) }; $0.document["blocks"] = rules } } }
      }
    }.navigationTitle(tr("privacyAndFilters")).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("addKeyword"), systemImage: "plus") { adding = true } } }
      .sheet(isPresented: $adding) { NavigationStack { Form {
        Picker(tr("filter"), selection: $kind) { Text(tr("keyword")).tag("keyword"); Text(tr("userId")).tag("user"); Text(tr("forumName")).tag("forum"); Text(tr("threadId")).tag("thread") }
        TextField(tr("keyword"), text: $value); Toggle(tr("showContent"), isOn: $allow)
      }.navigationTitle(tr("privacyAndFilters")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("cancel")) { adding = false } }; ToolbarItem(placement: .confirmationAction) { Button(tr("save")) { let value = value.trimmingCharacters(in: .whitespacesAndNewlines); app.updateLibrary { $0.addBlock(kind: kind, value: value, label: value, allow: allow) }; adding = false }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
  }
}
struct BackgroundSettings: View {
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var settings: Preferences
  @State private var item: PhotosPickerItem?
  var body: some View {
    Form {
      PhotosPicker(selection: $item, matching: .images) { Label(tr("chooseBackground"), systemImage: "photo") }
      Button(tr("removeBackground"), role: .destructive) { settings.set("nativeBackground", "") }
      HStack { Text(tr("backgroundBlur")); Slider(value: Binding(get: { settings.number("translucentBackgroundBlur") }, set: { settings.set("translucentBackgroundBlur", $0) }), in: 0...25) }
      HStack { Text(tr("surfaceOpacity")); Slider(value: Binding(get: { settings.number("nativeSurfaceOpacity") == 0 ? 0.9 : settings.number("nativeSurfaceOpacity") }, set: { settings.set("nativeSurfaceOpacity", $0) }), in: 0.5...1) }
    }.navigationTitle(tr("backgroundTheme"))
      .onChange(of: item) { _, item in Task { @MainActor in
        do { if let data = try await item?.loadTransferable(type: Data.self) { let file = try DraftFiles.retain(data); settings.set("nativeBackground", file.lastPathComponent) } } catch { app.error = error.localizedDescription }
      } }
  }
}
struct LicenseView: View {
  private var text: String {
    ["THIRD_PARTY_NOTICES.md", "LICENSE", "SwiftProtobuf-LICENSE.txt"].compactMap { name in TiebaResources.bundle.url(forResource: name, withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) } }.joined(separator: "\n\n")
  }
  var body: some View { ScrollView { Text(text).font(.caption.monospaced()).textSelection(.enabled).padding() }.navigationTitle(tr("licenses")) }
}
