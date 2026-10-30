import Foundation
import UserNotifications
import VademCore
#if os(iOS)
import UIKit
#endif

/// ``ReminderCenter`` backed by `UNUserNotificationCenter`; the only place that imports `UserNotifications`.
@MainActor
public final class SystemReminderCenter: ReminderCenter {
    // Uygulamanın bekleyen bildirim id önekleri: hatırlatmalar (PlannedReminder.id) ve
    // aylık özet (PlannedMonthlySummary.id).
    private static let idPrefixes = ["due-", "insight-"]

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

    public func replacePending(_ reminders: [PlannedReminder], summary: PlannedMonthlySummary?) async throws {
        // Yalnızca uygulamanın "due-" ve "insight-" bildirimleri silinir; başka bekleyen istek varsa korunur.
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { id in Self.idPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        // Metin cihaz dilinde, katalogdan kurulur (VademCore'un İngilizce metni kullanılmaz).
        var requests = reminders.map { reminder in
            request(id: reminder.id, title: ReminderText.title(for: reminder),
                    body: ReminderText.body(for: reminder), fireDate: reminder.fireDate)
        }
        if let summary {
            requests.append(request(id: summary.id, title: ReminderText.title(for: summary),
                                    body: ReminderText.body(for: summary), fireDate: summary.fireDate))
        }

        var firstError: (any Error)?
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                // Biri eklenemezse diğerleri yine kurulur; ilk hata sonda iletilir.
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    private func request(id: String, title: String, body: String, fireDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Takvim tetikleyicisi yerel saatle çalar (ör. 09:00), tekrarlamaz. Bileşenler enjekte edilen
        // takvimden gelir ama tetikleyicide açık saat dilimi yoktur: cihazın o anki diliminde çalar.
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
