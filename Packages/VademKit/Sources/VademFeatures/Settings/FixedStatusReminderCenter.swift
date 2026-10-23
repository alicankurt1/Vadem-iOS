#if DEBUG
import Foundation
import VademCore

/// A ``ReminderCenter`` that always reports `status` and schedules nothing (previews and the UI check).
@MainActor
final class FixedStatusReminderCenter: ReminderCenter {
    private let status: ReminderAuthorization

    init(status: ReminderAuthorization) {
        self.status = status
    }

    func authorizationStatus() async -> ReminderAuthorization {
        status
    }

    func requestAuthorization() async throws -> Bool {
        // Sistem izin penceresi açılmaz.
        false
    }

    func replacePending(_ reminders: [PlannedReminder]) async throws {}
}
#endif
