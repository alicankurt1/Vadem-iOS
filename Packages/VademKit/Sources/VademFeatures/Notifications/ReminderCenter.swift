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
    /// Throws when the request got no answer (e.g. the alert could not be shown); callers may ask again.
    func requestAuthorization() async throws -> Bool
    /// Removes every pending request whose id starts with `"due-"` (see ``PlannedReminder/id``) or
    /// `"insight-"` (see ``PlannedMonthlySummary/id``), then schedules `reminders` and `summary`
    /// (title, body, at `fireDate`). An empty array and `nil` only clear them.
    func replacePending(_ reminders: [PlannedReminder], summary: PlannedMonthlySummary?) async throws
}

extension ReminderCenter {
    /// Replaces the pending notifications with `reminders` and no monthly summary.
    public func replacePending(_ reminders: [PlannedReminder]) async throws {
        try await replacePending(reminders, summary: nil)
    }
}
