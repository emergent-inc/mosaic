import AppKit
import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class TutorialVideoPresentationCenter {
    static let shared = TutorialVideoPresentationCenter()

    private var pendingUntargetedPresentation: TutorialVideoPresentationKind?
    private var pendingTargetWindowIDs: [ObjectIdentifier: TutorialVideoPresentationKind] = [:]

    private init() {}

    func requestPresentation(in window: NSWindow? = nil, kind: TutorialVideoPresentationKind = .manual) {
        if let window {
            pendingTargetWindowIDs[ObjectIdentifier(window)] = kind
        } else {
            pendingUntargetedPresentation = kind
        }
        NotificationCenter.default.post(name: .tutorialVideoPresentationRequested, object: window)
    }

    func consumePendingPresentation(
        for window: NSWindow?,
        requestedWindow: NSWindow? = nil,
        keyWindow: NSWindow? = NSApp.keyWindow,
        mainWindow: NSWindow? = NSApp.mainWindow
    ) -> TutorialVideoPresentationKind? {
        guard let window else { return nil }
        if let requestedWindow, requestedWindow !== window {
            return nil
        }

        let windowID = ObjectIdentifier(window)
        if let kind = pendingTargetWindowIDs.removeValue(forKey: windowID) {
            return kind
        }

        guard requestedWindow == nil, let kind = pendingUntargetedPresentation else {
            return nil
        }
        let shouldHandleUntargetedRequest =
            window === keyWindow
            || (keyWindow == nil && window === mainWindow)
            || (keyWindow == nil && mainWindow == nil)
        guard shouldHandleUntargetedRequest else { return nil }
        pendingUntargetedPresentation = nil
        return kind
    }
}

extension Notification.Name {
    static let tutorialVideoPresentationRequested = Notification.Name("cmux.tutorialVideo.presentationRequested")
}

enum TutorialVideoPresentationKind {
    case manual
    case automaticFirstRun
}

enum TutorialVideoStyle {
    static let cornerRadius: CGFloat = 16
    static let fallbackVideoSize = CGSize(width: 960, height: 620)
    static let popupPreferredScale: CGFloat = 0.62
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
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.86))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.86))
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
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
