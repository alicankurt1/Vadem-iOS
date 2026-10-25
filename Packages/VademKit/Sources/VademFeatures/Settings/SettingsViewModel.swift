import Foundation
import Observation
import VademCore
#if os(iOS)
import UIKit
#endif

/// What the settings screen needs: the preferences store, and (when reminders are live) the
/// notification center and the scheduler.
///
/// Sample data, previews and tests use an in-memory store without a center or scheduler.
@MainActor
public struct SettingsDependencies {
    /// Where the reminder preferences are saved.
    public let store: any ReminderPreferencesStore
    /// Reads the system permission; `nil` means the permission is not shown (never denied).
    public let center: (any ReminderCenter)?
    /// Refreshed after each preference change; `nil` schedules nothing.
    public let scheduler: ReminderScheduler?
    /// Opens the app's page in the system Settings app.
    public let openSystemSettings: @MainActor () -> Void

    /// Creates the dependencies; `openSystemSettings` defaults to ``SettingsViewModel/openAppSettings()``.
    public init(
        store: any ReminderPreferencesStore,
        center: (any ReminderCenter)? = nil,
        scheduler: ReminderScheduler? = nil,
        openSystemSettings: @escaping @MainActor () -> Void = SettingsViewModel.openAppSettings
    ) {
        self.store = store
        self.center = center
        self.scheduler = scheduler
        self.openSystemSettings = openSystemSettings
    }

    /// An in-memory store, no center and no scheduler.
    public static func inMemory() -> SettingsDependencies {
        SettingsDependencies(store: InMemoryReminderPreferencesStore())
    }
}

/// Drives the settings sheet: the reminder toggle, the timing and the system permission.
///
/// Each change is saved to the store right away, then the scheduler is refreshed (turning reminders
/// on may show the system permission prompt), then the permission is read again.
@MainActor
@Observable
public final class SettingsViewModel: Identifiable {
    /// The current preferences, as saved in the store.
    public private(set) var preferences: ReminderPreferences
    /// The system permission, or `nil` before ``loadAuthorization()`` or without a center.
    public private(set) var authorization: ReminderAuthorization?

    @ObservationIgnored private let store: any ReminderPreferencesStore
    @ObservationIgnored private let center: (any ReminderCenter)?
    @ObservationIgnored private let scheduler: ReminderScheduler?
    @ObservationIgnored private let openSystemSettingsAction: @MainActor () -> Void

    /// Loads the preferences from `dependencies.store`.
    public init(dependencies: SettingsDependencies) {
        self.store = dependencies.store
        self.center = dependencies.center
        self.scheduler = dependencies.scheduler
        self.openSystemSettingsAction = dependencies.openSystemSettings
        self.preferences = dependencies.store.load()
    }

    /// The timings in display order: both (default), on the day, day before.
    public nonisolated static let timings: [ReminderTiming] = [.both, .dueDay, .dayBefore]

    /// The display title of `timing`, e.g. `"Day before and on the day"`.
    public nonisolated static func title(of timing: ReminderTiming) -> String {
        switch timing {
        case .both: return String(localized: "Day before and on the day", bundle: .module)
        case .dueDay: return String(localized: "On the day", bundle: .module)
        case .dayBefore: return String(localized: "Day before", bundle: .module)
        }
    }

    /// `true` when reminders are on.
    public var isEnabled: Bool { preferences.isEnabled }
    /// The selected timing.
    public var timing: ReminderTiming { preferences.timing }
    /// The timing row is shown only while reminders are on.
    public var showsTiming: Bool { preferences.isEnabled }
    /// `true` when reminders are on but the system permission is denied: the screen explains
    /// it and offers ``openSystemSettings()``.
    public var showsPermissionDenied: Bool { preferences.isEnabled && authorization == .denied }

    /// Turns reminders on or off: saves at once, then refreshes the scheduler and the permission.
    ///
    /// - Returns: The refresh; await its `value` to know it finished.
    @discardableResult
    public func setEnabled(_ isEnabled: Bool) -> Task<Void, Never> {
        update { $0.isEnabled = isEnabled }
    }

    /// Selects the timing: saves at once, then refreshes the scheduler and the permission.
    ///
    /// - Returns: The refresh; await its `value` to know it finished.
    @discardableResult
    public func setTiming(_ timing: ReminderTiming) -> Task<Void, Never> {
        update { $0.timing = timing }
    }

    /// Reads the system permission from the center (does nothing without one).
    public func loadAuthorization() async {
        guard let center else { return }
        authorization = await center.authorizationStatus()
    }

    /// Opens the app's page in the system Settings app (the injected action).
    public func openSystemSettings() {
        openSystemSettingsAction()
    }

    /// Opens the app's page in the system Settings app (`UIApplication.openSettingsURLString`);
    /// does nothing outside iOS.
    public static func openAppSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    // Değişiklik önce kaydedilir (UI hemen güncellenir), yenileme ardından çalışır.
    private func update(_ change: (inout ReminderPreferences) -> Void) -> Task<Void, Never> {
        var updated = preferences
        change(&updated)
        preferences = updated
        store.save(updated)
        return Task { [scheduler] in
            await scheduler?.refresh()
            // Açınca izin penceresi çıkmış olabilir; durum yeniden okunur.
            await self.loadAuthorization()
        }
    }
}
