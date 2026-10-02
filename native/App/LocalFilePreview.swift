import AVKit
import ForumUI
import QuickLook
import SwiftUI

/// Opens saved media directly; no URL handoff to another installed player.
struct LocalFilePreview: View {
  let file: URL
  @State private var checked = false
  @State private var available = false

  var body: some View {
    Group {
      if !checked { ProgressView() }
      else if !available {
        ForumUnavailableView(AppText.text("File unavailable"), forumSymbol: "doc",
          description: Text(AppText.text("This file was moved or is no longer available. Refresh the folder.")))
      } else if [.video, .audio].contains(LocalMediaKind.kind(file)) {
        LocalMediaPlayer(file: file)
      } else if QLPreviewController.canPreview(file as NSURL) {
        GofileQuickLook(file: file)
      } else {
        ForumUnavailableView(AppText.text("Preview unavailable"), forumSymbol: "doc",
          description: Text(AppText.text("This file format cannot be previewed here. You can share or export the file.")))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .appFont(.body).navigationTitle(file.lastPathComponent).navigationBarTitleDisplayMode(.inline)
      .toolbarRole(.editor).toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .bottomBar)
      .toolbar {
        if available {
          ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: file) { Image(forumSymbol: "square.and.arrow.up") }.accessibilityLabel(AppText.text("Share"))
          }
        }
      }
      .task(id: file) {
        available = file.isFileURL && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        checked = true
      }
  }
}

private struct LocalMediaPlayer: View {
  let file: URL
  @StateObject private var playback = LocalMediaPlayback()
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    ZStack {
      Color.black
      LocalPlayerSurface(player: playback.player)
      if let error = playback.error {
        VStack(spacing: 16) {
          Text(error).appFont(.body).multilineTextAlignment(.center)
          Button(AppText.text("Retry"), forumSymbol: "arrow.clockwise") { playback.open(file) }.buttonStyle(.glass)
        }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
      } else if playback.preparing {
        ProgressView().tint(.white).allowsHitTesting(false)
      }
    }.onAppear { playback.open(file) }
      .onDisappear { playback.close() }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active { playback.pause() }
      }
  }
}

@MainActor private final class LocalMediaPlayback: ObservableObject {
  let player = AVPlayer()
  @Published private(set) var preparing = true
  @Published private(set) var error: String?
  private var status: NSKeyValueObservation?
  private var failure: NSObjectProtocol?
  private var shouldAutoplay = false
  private var audioActive = false

  func open(_ file: URL) {
    close()
    preparing = true; error = nil; shouldAutoplay = true
    guard file.isFileURL, FileManager.default.isReadableFile(atPath: file.path) else {
      fail(missing: true); return
    }
    let item = AVPlayerItem(url: file)
    player.replaceCurrentItem(with: item)
    status = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
      Task { @MainActor [weak self, weak item] in
        guard let self, let item, self.player.currentItem === item else { return }
        switch item.status {
        case .readyToPlay:
          self.preparing = false
          do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            self.audioActive = true
            if self.shouldAutoplay { self.player.play() }
          } catch { self.fail(missing: false) }
        case .failed: self.fail(missing: false)
        default: break
        }
      }
    }
    failure = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
      Task { @MainActor [weak self, weak item] in
        guard let self, let item, self.player.currentItem === item else { return }
        self.fail(missing: false)
      }
    }
  }

  private func fail(missing: Bool) {
    pause(); preparing = false
    error = missing ? AppText.text("This file was moved or is no longer available. Refresh the folder.")
      : AppText.text("This video or audio cannot be played by the built-in player. Its format may be unsupported or the file may be incomplete. You can share or export it.")
  }
  func pause() { shouldAutoplay = false; player.pause() }
  func close() {
    status = nil
    if let failure { NotificationCenter.default.removeObserver(failure) }
    failure = nil
    pause(); player.replaceCurrentItem(with: nil)
    if audioActive {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      audioActive = false
    }
  }
}

private struct LocalPlayerSurface: UIViewControllerRepresentable {
  let player: AVPlayer
  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.allowsPictureInPicturePlayback = false
    return controller
  }
  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
  static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
    controller.player?.pause(); controller.player = nil
  }
}
