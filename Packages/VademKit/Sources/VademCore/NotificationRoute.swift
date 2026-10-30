import Foundation

/// Routes a tapped system notification to a screen of the app (pure).
public enum NotificationRoute: Sendable, Hashable {
    /// The in-app inbox.
    case inbox

    /// The screen a notification with `identifier` opens: the inbox for the monthly summary
    /// (ids starting with `insight-`, see ``PlannedMonthlySummary/id``); `nil` otherwise
    /// (e.g. a payment reminder `due-…`, which just opens the app).
    public static func route(forNotificationIdentifier identifier: String) -> NotificationRoute? {
        identifier.hasPrefix("insight-") ? .inbox : nil
    }
}
