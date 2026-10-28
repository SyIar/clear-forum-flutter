import SwiftUI

struct ForumSelectionView: View {
  let openTieba: () -> Void
  let openDownloader: () -> Void
  @EnvironmentObject private var wallpaper: DailyWallpaperStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var external: URL?

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(spacing: 16) {
          ForEach(ForumSite.allCases) { site in
            NavigationLink(value: ForumDestination.home(site)) {
              moduleCard(logo: site == .bookhouse ? "BookhouseLogo" : site == .simp ? "ForumLogo" : "SouthLogo")
            }.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 20))
              .accessibilityLabel(AppText.format("Open %@ home", site.host))
          }
          HStack(spacing: 16) {
            Button(action: openTieba) {
              moduleCard(logo: "TiebaLogo")
            }.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 20))
              .frame(maxWidth: .infinity)
              .accessibilityLabel(AppText.format("Open %@ home", "tieba.baidu.com"))
            Button(action: openDownloader) {
              Image(systemName: "square.and.arrow.down").font(.system(size: 46))
                .foregroundStyle(.primary).accessibilityHidden(true)
                .frame(maxWidth: .infinity).frame(height: 82)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 20))
              .frame(maxWidth: .infinity)
              .accessibilityLabel(AppText.text("Downloader"))
          }
        }
        if let photo = wallpaper.wallpaper {
          Button { external = photo.source } label: {
            VStack(spacing: 3) {
              if !photo.title.isEmpty { Text(photo.title).appFont(.caption, weight: .semibold) }
              Text("Bing · " + photo.credit).appFont(.caption2)
            }.multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
              .shadow(color: .black.opacity(0.8), radius: 4, y: 1)
              .padding(.horizontal, 12).padding(.vertical, 8)
          }.buttonStyle(.plain).accessibilityLabel(AppText.text("Wallpaper source"))
        }
      }.frame(maxWidth: 520).padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }.scrollIndicators(.hidden)
      .background { ForumSelectionBackdrop().ignoresSafeArea() }
      // The moving page must not expose a default white navigation surface.
      .containerBackground(.clear, for: .navigation)
      .toolbar(.hidden, for: .navigationBar)
      .background { ExternalBrowserPresenter(url: $external) }
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        await wallpaper.run()
      }
  }

  private func moduleCard(logo: String) -> some View {
    Image(logo).resizable().scaledToFit().frame(height: 82)
      .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
      .padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity)
  }

}

// Also rendered behind the navigation host, outside its animated page bounds.
struct ForumSelectionBackdrop: View {
  @EnvironmentObject private var wallpaper: DailyWallpaperStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        LinearGradient(colors: [Color(red: 0.09, green: 0.2, blue: 0.32),
                                Color(red: 0.13, green: 0.33, blue: 0.38),
                                Color(red: 0.08, green: 0.1, blue: 0.21)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        if let image = wallpaper.image {
          Image(uiImage: image).resizable().scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .id(wallpaper.wallpaper?.id).transition(.opacity)
        }
        LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.48)],
                       startPoint: .top, endPoint: .bottom)
      }.animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: wallpaper.wallpaper?.id)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}
