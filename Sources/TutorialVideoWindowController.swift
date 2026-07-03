import AppKit
import AVKit
import SwiftUI

@MainActor
final class TutorialVideoWindowController: ReleasingWindowController {
    static let shared = TutorialVideoWindowController()
    static let windowIdentifier = "cmux.tutorialVideo"

    private override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        let window = managedWindow()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    override func makeWindow() -> NSWindow {
        let appearanceMode = UserDefaults.standard.string(forKey: AppearanceSettings.appearanceModeKey)
        let root = TutorialVideoView(videoURL: TutorialVideoResource.videoURL())
            .cmuxAppearanceColorScheme(appearanceMode)
        let hostingController = NSHostingController(rootView: root)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "tutorial.video.window.title", defaultValue: "Welcome to mosaic")
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 960, height: 620))
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.center()
        return window
    }
}

enum TutorialVideoResource {
    static let fileName = "demo"
    static let fileExtension = "mov"
    static let subdirectory = "Tutorial"

    static func videoURL(bundle: Bundle = .main) -> URL? {
        videoURL { resource, extensionName, subdirectory in
            bundle.url(
                forResource: resource,
                withExtension: extensionName,
                subdirectory: subdirectory
            )
        }
    }

    static func videoURL(
        resolve: (_ resource: String, _ extensionName: String?, _ subdirectory: String?) -> URL?
    ) -> URL? {
        resolve(fileName, fileExtension, subdirectory)
            ?? resolve(fileName, fileExtension, nil)
    }
}

private struct TutorialVideoView: View {
    let videoURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let videoURL {
                TutorialVideoPlayerView(url: videoURL)
                    .accessibilityIdentifier("TutorialVideoPlayer")
            } else {
                TutorialVideoMissingResourceView()
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("TutorialVideoWindowContent")
    }
}

private struct TutorialVideoMissingResourceView: View {
    var body: some View {
        VStack(spacing: 12) {
            CmuxSystemSymbolImage(systemName: "exclamationmark.triangle", pointSize: 28, weight: .medium)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Text(String(localized: "tutorial.video.missing", defaultValue: "The tutorial video is missing from this app build."))
                .cmuxFont(size: 13)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("TutorialVideoMissingResource")
    }
}

private struct TutorialVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        context.coordinator.configure(view, url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.configure(nsView, url: url)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.close(nsView)
    }

    @MainActor
    final class Coordinator {
        private var currentURL: URL?
        private var player: AVPlayer?

        deinit {
            player?.pause()
        }

        func configure(_ view: AVPlayerView, url: URL) {
            guard currentURL != url else { return }
            player?.pause()
            currentURL = url
            let player = AVPlayer(url: url)
            self.player = player
            view.player = player
            player.play()
        }

        func close(_ view: AVPlayerView) {
            player?.pause()
            view.player = nil
            player = nil
            currentURL = nil
        }
    }
}
