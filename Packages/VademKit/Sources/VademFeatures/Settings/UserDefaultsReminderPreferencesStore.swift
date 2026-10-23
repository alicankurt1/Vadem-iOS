import Foundation
import VademCore

/// A ``ReminderPreferencesStore`` backed by `UserDefaults` (device-local, not the App Group).
///
/// Keys: ``isEnabledKey`` (`Bool`) and ``timingKey`` (``ReminderTiming`` raw value). A missing
/// key, or an unknown timing value, gives the value of ``ReminderPreferences/default``.
@MainActor
public final class UserDefaultsReminderPreferencesStore: ReminderPreferencesStore {
    /// The key of ``ReminderPreferences/isEnabled``.
    public nonisolated static let isEnabledKey = "vadem.reminders.isEnabled"
    /// The key of ``ReminderPreferences/timing``.
    public nonisolated static let timingKey = "vadem.reminders.timing"

    private let defaults: UserDefaults

    /// Uses `defaults` (default: `.standard`); tests pass `UserDefaults(suiteName:)`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ReminderPreferences {
        let fallback = ReminderPreferences.default
        // `bool(forKey:)` eksik anahtarda false döner; varsayılan açık olduğundan önce varlığı kontrol edilir.
        let isEnabled = defaults.object(forKey: Self.isEnabledKey) as? Bool ?? fallback.isEnabled
        let timing = defaults.string(forKey: Self.timingKey).flatMap(ReminderTiming.init(rawValue:)) ?? fallback.timing
        return ReminderPreferences(isEnabled: isEnabled, timing: timing)
    }

    public func save(_ preferences: ReminderPreferences) {
        defaults.set(preferences.isEnabled, forKey: Self.isEnabledKey)
        defaults.set(preferences.timing.rawValue, forKey: Self.timingKey)
    }
}
