import MosaicMobileCore
import UIKit
import UserNotifications
import mosaicFeature

/// App delegate for APNs: installs the notification-center delegate, forwards
/// registered device tokens to the injected push coordinator, and routes
/// foreground presentation + taps. All push policy lives in
/// ``MobilePushCoordinator``, constructed at the app composition root and
/// injected here by `mosaicApp`.
final class MosaicAppDelegate: NSObject, @preconcurrency UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The app-root push coordinator, injected by `mosaicApp` at launch.
    @MainActor var pushCoordinator: MobilePushCoordinator?
    /// The app-root analytics emitter, injected by `mosaicApp` at launch.
    @MainActor var analytics: (any AnalyticsEmitting)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let launchedFromPush = launchOptions?[.remoteNotification] != nil
        // `analytics` is assigned in `mosaicApp.init()` which runs before
        // `didFinishLaunchingWithOptions`, so the emitter is available here.
        analytics?.capture("ios_app_launched", [
            "launch_type": .string("cold"),
            "launched_from": .string(launchedFromPush ? "push" : "normal"),
        ])
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await pushCoordinator?.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("mosaic.push registration failed: %@", error.localizedDescription)
        let nsError = error as NSError
        Task { @MainActor in
            analytics?.capture("ios_push_token_registration_failed", [
                "stage": .string("apns"),
                "error_code": .int(nsError.code),
                "error_domain": .string(nsError.domain),
            ])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let ids = Self.mosaicIDs(from: notification.request.content.userInfo)
        let present = await pushCoordinator?.shouldPresentInForeground(
            workspaceId: ids.workspaceId,
            surfaceId: ids.surfaceId,
            macDeviceId: ids.macDeviceId
        ) ?? true
        return present ? [.banner, .sound, .badge] : []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        // A swipe/clear of a mosaic banner delivers the custom dismiss action
        // (enabled via the `mosaic.terminal` category's `.customDismissAction`).
        // Forward it to the Mac so the desktop banner + store entry clear too.
        let ids = Self.mosaicIDs(from: request.content.userInfo)
        if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            await pushCoordinator?.handleDismiss(
                notificationId: Self.notificationID(from: request),
                macDeviceId: ids.macDeviceId
            )
            return
        }
        // A tap (default action) deep-links to the workspace/terminal AND marks
        // the notification read on the Mac, mirroring the Mac's own tap path
        // (which opens + marks read). The two compose: deep-link locally, clear
        // on the Mac.
        let appState = await UIApplication.shared.applicationState
        await analytics?.capture("ios_push_tapped", [
            "has_workspace_id": .bool(ids.workspaceId != nil),
            "has_surface_id": .bool(ids.surfaceId != nil),
            "app_state": .string(Self.appStateLabel(appState)),
        ])
        await pushCoordinator?.handleTap(
            workspaceId: ids.workspaceId,
            surfaceId: ids.surfaceId,
            macDeviceId: ids.macDeviceId
        )
        await pushCoordinator?.handleDismiss(
            notificationId: Self.notificationID(from: request),
            macDeviceId: ids.macDeviceId
        )
    }

    /// Silent dismiss push (the cold lane of Mac→iOS dismiss-sync): the Mac
    /// cleared notifications and sent every registered device a
    /// `content-available` push carrying the dismissed ids (idempotent no-op if
    /// this device already handled the live peer event). The system applies
    /// the authoritative badge from `aps.badge` without waking us; when iOS
    /// grants the background wake — strictly budgeted, a handful per hour at
    /// best — we also remove the matching delivered banners. Anything iOS
    /// defers is healed by the reconcile sweep on the next app open/attach.
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let dismissedIds = Self.dismissedIDs(from: userInfo)
        guard !dismissedIds.isEmpty else { return .noData }
        return await handleRemoteDismiss(ids: dismissedIds)
    }

    @MainActor
    private func handleRemoteDismiss(ids: [String]) async -> UIBackgroundFetchResult {
        await pushCoordinator?.handleRemoteDismiss(ids: ids)
        return .newData
    }

    private nonisolated static func dismissedIDs(from userInfo: [AnyHashable: Any]) -> [String] {
        guard let mosaic = userInfo["mosaic"] as? [String: Any],
              let ids = mosaic["dismissedIds"] as? [String] else {
            return []
        }
        return ids
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    private static func appStateLabel(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private nonisolated static func mosaicIDs(
        from userInfo: [AnyHashable: Any]
    ) -> (workspaceId: String?, surfaceId: String?, macDeviceId: String?) {
        guard let mosaic = userInfo["mosaic"] as? [String: Any] else { return (nil, nil, nil) }
        return (
            mosaic["workspaceId"] as? String,
            mosaic["surfaceId"] as? String,
            mosaic["macDeviceId"] as? String
        )
    }

    /// The stable Mac-side notification id for a delivered request, or `nil` when
    /// this push does not carry one.
    ///
    /// The `mosaic.notificationId` payload key is authoritative: the Mac stamps the
    /// same value as `apns-collapse-id`, so it equals `request.identifier` for a
    /// modern push. We deliberately do NOT fall back to a bare `request.identifier`
    /// when the payload key is absent: a push without `notificationId` (an older
    /// Mac, or any push that omitted it) has an OS-assigned random identifier that
    /// matches no Mac notification, so forwarding it would mark the wrong (or no)
    /// notification read. Returning `nil` degrades cleanly to "no dismiss-sync".
    private nonisolated static func notificationID(from request: UNNotificationRequest) -> String? {
        guard let mosaic = request.content.userInfo["mosaic"] as? [String: Any],
              let id = (mosaic["notificationId"] as? String)?.trimmingCharacters(in: .whitespaces),
              !id.isEmpty else {
            return nil
        }
        return id
    }
}
