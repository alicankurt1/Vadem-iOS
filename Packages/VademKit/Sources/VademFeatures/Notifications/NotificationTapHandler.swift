import Foundation
import UserNotifications
import VademCore

/// The app's `UNUserNotificationCenterDelegate`: turns a tapped notification into a
/// ``NotificationRoute`` (``NotificationRoute/route(forNotificationIdentifier:)``) and hands it to
/// ``onRoute``.
///
/// Set it as the center's delegate early (before the app finishes launching), so the tap that
/// launched the app is not missed. A route that arrives before ``onRoute`` is set (cold launch:
/// the screens are not built yet) waits and is delivered as soon as ``onRoute`` is set.
@MainActor
public final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {
    /// Receives the routes of tapped notifications; setting it delivers a waiting route.
    public var onRoute: ((NotificationRoute) -> Void)? {
        didSet { deliverPending() }
    }

    // Ekranlar hazır olmadan gelen dokunuş (soğuk açılış) burada bekler.
    private var pendingRoute: NotificationRoute?

    /// Creates a handler; assign it to `UNUserNotificationCenter.current().delegate` yourself.
    override public init() {
        super.init()
    }

    /// Handles a tapped notification with `identifier` (what the delegate method calls).
    public func handleTap(identifier: String) {
        guard let route = NotificationRoute.route(forNotificationIdentifier: identifier) else { return }
        pendingRoute = route
        deliverPending()
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Yalnızca kimlik (String, Sendable) ana aktöre taşınır; çağrının hangi kuyrukta geldiği garanti değil.
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            self.handleTap(identifier: identifier)
        }
        completionHandler()
    }

    private func deliverPending() {
        guard let onRoute, let route = pendingRoute else { return }
        pendingRoute = nil
        onRoute(route)
    }
}
