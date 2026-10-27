import Foundation
import UserNotifications
import VademCore
#if os(iOS)
import UIKit
#endif

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

    /// Throws ``SceneNotActiveError`` without asking when the app is not active: iOS shows no alert
    /// then, so the request would end without an answer (the scheduler retries on its next refresh).
    public func requestAuthorization() async throws -> Bool {
        #if os(iOS)
        // Uygulama etkin değilken sistem izin penceresini göstermez; cevapsız istek harcanmasın.
        guard UIApplication.shared.applicationState == .active else { throw SceneNotActiveError() }
        #endif
        return try await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Thrown by ``requestAuthorization()`` when the app is not active, so no alert could be shown.
    public struct SceneNotActiveError: Error {}

    public func replacePending(_ reminders: [PlannedReminder]) async throws {
        // Yalnızca uygulamanın "due-" hatırlatmaları silinir; başka bekleyen istek varsa korunur.
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        var firstError: (any Error)?
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            // Metin cihaz dilinde, katalogdan kurulur (VademCore'un İngilizce metni kullanılmaz).
            content.title = ReminderText.title(for: reminder)
            content.body = ReminderText.body(for: reminder)
            content.sound = .default
            // Takvim tetikleyicisi yerel saatle çalar (ör. 09:00), tekrarlamaz. Bileşenler enjekte edilen
            // takvimden gelir ama tetikleyicide açık saat dilimi yoktur: cihazın o anki diliminde çalar.
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                // Biri eklenemezse diğerleri yine kurulur; ilk hata sonda iletilir.
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
