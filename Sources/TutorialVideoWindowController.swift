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
    static let tutorialVideoPresentationRequested = Notification.Name("mosaic.tutorialVideo.presentationRequested")
}

enum TutorialVideoPresentationKind {
    case manual
    case automaticFirstRun
}

enum TutorialVideoStyle {
    static let cornerRadius: CGFloat = 16
    static let fallbackVideoSize = CGSize(width: 960, height: 620)
    static let popupPreferredScale: CGFloat = 0.62
    /// Hard cap on the video area width so the popup stays a modest, non-distracting card
    /// even for high-resolution source videos on large displays.
    static let maxVideoWidth: CGFloat = 440
    /// Horizontal space consumed by the card padding around the video area.
    static let cardHorizontalChrome: CGFloat = 48
    /// Vertical space consumed by the card header, footer, and padding around the video area.
    static let cardVerticalChrome: CGFloat = 176
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

    /// A still frame extracted a moment into the video, used as a non-playing poster.
    static func posterImage(url: URL? = videoURL()) -> NSImage? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

struct TutorialVideoView: View {
    let videoURL: URL?
    let videoAreaSize: CGSize
    let cornerRadius: CGFloat
    let onClose: () -> Void

    @State private var isPlaying = true
    @State private var poster: NSImage?

    private let title = String(localized: "tutorial.video.title", defaultValue: "Welcome to Mosaic")
    private let subtitle = String(
        localized: "tutorial.video.subtitle",
        defaultValue: "A quick tour of the essentials"
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            videoArea
                .frame(width: videoAreaSize.width, height: videoAreaSize.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            footer
        }
        .frame(width: videoAreaSize.width)
        .padding(24)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius + 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .fixedSize()
        .accessibilityIdentifier("TutorialVideoWindowContent")
        .onAppear {
            if poster == nil {
                poster = TutorialVideoResource.posterImage(url: videoURL)
            }
        }
    }

    private var cardBackground: some View {
        Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Image("MosaicLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 26)
                    .accessibilityLabel(Text(title))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            Spacer(minLength: 12)
            closeButton
        }
    }

    @ViewBuilder
    private var videoArea: some View {
        if let videoURL {
            ZStack {
                Color.black
                if isPlaying {
                    TutorialVideoPlayerView(url: videoURL, cornerRadius: cornerRadius)
                        .accessibilityIdentifier("TutorialVideoPlayer")
                } else {
                    posterView
                }
            }
        } else {
            TutorialVideoMissingResourceView()
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var posterView: some View {
        let label = String(localized: "tutorial.video.play", defaultValue: "Play tutorial video")
        return ZStack {
            if let poster {
                Image(nsImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            Button(action: { isPlaying = true }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.white.opacity(0.92)))
                    .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .safeHelp(label)
            .accessibilityLabel(label)
            .accessibilityIdentifier("TutorialVideoPlayButton")
            .mosaicCursorOnHover(.pointingHand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            shortcutHint(
                keys: "\u{2318}N",
                label: String(localized: "tutorial.video.hint.newWorkspace", defaultValue: "New workspace")
            )
            shortcutHint(
                keys: "\u{2318}T",
                label: String(localized: "tutorial.video.hint.newTab", defaultValue: "New tab")
            )
            shortcutHint(
                keys: "\u{2318}\u{21E7}P",
                label: String(localized: "tutorial.video.hint.commandPalette", defaultValue: "Command palette")
            )
            Spacer(minLength: 0)
        }
    }

    private func shortcutHint(keys: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private var closeButton: some View {
        let label = String(localized: "tutorial.video.close", defaultValue: "Close tutorial video")
        return Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .safeHelp(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("TutorialVideoCloseButton")
        .mosaicCursorOnHover(.pointingHand)
    }
}

private struct TutorialVideoMissingResourceView: View {
    var body: some View {
        VStack(spacing: 12) {
            MosaicSystemSymbolImage(systemName: "exclamationmark.triangle", pointSize: 28, weight: .medium)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Text(String(localized: "tutorial.video.missing", defaultValue: "The tutorial video is missing from this app build."))
                .mosaicFont(size: 13)
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
        view.controlsStyle = .inline
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
            player.isMuted = true
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
