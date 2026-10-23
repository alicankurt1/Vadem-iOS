import Foundation
import VademCore

/// Whether the app may show reminders.
public enum ReminderAuthorization: Sendable, Hashable {
    /// The user has not been asked yet.
    case notDetermined
    /// The user said no (or reminders are turned off in Settings).
    case denied
    /// Reminders can be shown.
    case allowed
}

/// The system's local notification center, as the app needs it.
///
/// ``SystemReminderCenter`` is the real implementation; tests use a fake.
@MainActor
public protocol ReminderCenter {
    /// The current permission.
    func authorizationStatus() async -> ReminderAuthorization
    /// Asks the user for permission; returns `true` when it is granted.
    func requestAuthorization() async throws -> Bool
    /// Removes every pending request whose id starts with `"due-"` (see ``PlannedReminder/id``), then schedules
    /// `reminders` (title, body, at `fireDate`). An empty array only clears them.
    func replacePending(_ reminders: [PlannedReminder]) async throws
}
