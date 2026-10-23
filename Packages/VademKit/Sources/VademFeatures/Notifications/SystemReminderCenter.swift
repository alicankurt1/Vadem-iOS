import Foundation
import UserNotifications
import VademCore

/// ``ReminderCenter`` backed by `UNUserNotificationCenter`; the only place that imports `UserNotifications`.
@MainActor
public final class SystemReminderCenter: ReminderCenter {
    // Planlayıcının her hatırlatma id'sinin öneki (PlannedReminder.id).
    private static let idPrefix = "due-"

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    /// Uses the app's notification center; `calendar` turns fire dates into local trigger times.
    public init(calendar: Calendar = .current) {
        self.center = UNUserNotificationCenter.current()
        self.calendar = calendar
    }

    public func authorizationStatus() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        default:
            // authorized, provisional, ephemeral: bildirim gösterilebilir.
            return .allowed
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func replacePending(_ reminders: [PlannedReminder]) async throws {
        // Yalnızca uygulamanın "due-" hatırlatmaları silinir; başka bekleyen istek varsa korunur.
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            // Takvim tetikleyicisi yerel saatle çalar (ör. 09:00), tekrarlamaz.
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try await center.add(request)
        }
    }
}
