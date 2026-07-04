import AppKit
import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class TutorialVideoPresentationCenter {
    static let shared = TutorialVideoPresentationCenter()

    private var pendingUntargetedPresentation = false
    private var pendingTargetWindowIDs: Set<ObjectIdentifier> = []

    private init() {}

    func requestPresentation(in window: NSWindow? = nil) {
        if let window {
            pendingTargetWindowIDs.insert(ObjectIdentifier(window))
        } else {
            pendingUntargetedPresentation = true
        }
        NotificationCenter.default.post(name: .tutorialVideoPresentationRequested, object: window)
    }

    func consumePendingPresentation(
        for window: NSWindow?,
        requestedWindow: NSWindow? = nil,
        keyWindow: NSWindow? = NSApp.keyWindow,
        mainWindow: NSWindow? = NSApp.mainWindow
    ) -> Bool {
        guard let window else { return false }
        if let requestedWindow, requestedWindow !== window {
            return false
        }

        let windowID = ObjectIdentifier(window)
        if pendingTargetWindowIDs.remove(windowID) != nil {
            return true
        }

        guard requestedWindow == nil, pendingUntargetedPresentation else {
            return false
        }
        let shouldHandleUntargetedRequest =
            window === keyWindow
            || (keyWindow == nil && window === mainWindow)
            || (keyWindow == nil && mainWindow == nil)
        guard shouldHandleUntargetedRequest else { return false }
        pendingUntargetedPresentation = false
        return true
    }
}

extension Notification.Name {
    static let tutorialVideoPresentationRequested = Notification.Name("cmux.tutorialVideo.presentationRequested")
}

enum TutorialVideoStyle {
    static let cornerRadius: CGFloat = 16
    static let fallbackVideoSize = CGSize(width: 960, height: 620)
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

    static func naturalVideoSize(url: URL? = videoURL()) -> CGSize? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return nil
        }
        return size
    }
}

struct TutorialVideoView: View {
    let videoURL: URL?
    let cornerRadius: CGFloat
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let videoURL {
                TutorialVideoPlayerView(url: videoURL, cornerRadius: cornerRadius)
                    .accessibilityIdentifier("TutorialVideoPlayer")
            } else {
                TutorialVideoMissingResourceView()
            }

            closeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityIdentifier("TutorialVideoWindowContent")
    }

    private var closeButton: some View {
        let label = String(localized: "tutorial.video.close", defaultValue: "Close tutorial video")
        return Button(action: onClose) {
            Text(verbatim: "X")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .safeHelp(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("TutorialVideoCloseButton")
        .cmuxCursorOnHover(.pointingHand)
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
    let cornerRadius: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = DraggableAVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.black.cgColor
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

private final class DraggableAVPlayerView: AVPlayerView {
    override var mouseDownCanMoveWindow: Bool { false }
}
