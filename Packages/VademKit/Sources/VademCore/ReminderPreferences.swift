import Foundation

/// When payment reminders fire relative to the due day.
public enum ReminderTiming: String, Sendable, Hashable, CaseIterable {
    /// The day before and on the due day (the default).
    case both
    /// On the due day only.
    case dueDay
    /// The day before only.
    case dayBefore

    /// The planner kinds this timing asks for (see ``NotificationPlanner/plan(now:calendar:cards:installments:subscriptions:lookaheadMonths:kinds:formatAmount:)``).
    public var kinds: Set<PlannedReminder.Kind> {
        switch self {
        case .both: return [.dayBefore, .dueDay]
        case .dueDay: return [.dueDay]
        case .dayBefore: return [.dayBefore]
        }
    }
}

/// The user's reminder settings: payment reminders on or off and when they fire, and the
/// monthly summary on or off.
///
/// The two switches are independent: the monthly summary is sent while payment reminders are
/// off, and payment reminders are sent while the summary is off.
public struct ReminderPreferences: Sendable, Hashable {
    /// The settings used before the user changes anything: reminders on, day before and on the
    /// day, monthly summary on.
    public static let `default` = ReminderPreferences()

    /// `false` turns every payment reminder off (not the monthly summary).
    public var isEnabled: Bool
    /// When the reminders fire; kept while reminders are off.
    public var timing: ReminderTiming
    /// `false` turns the monthly summary notification off (see ``PlannedMonthlySummary``).
    public var monthlySummaryEnabled: Bool

    /// Creates preferences; the defaults are ``ReminderPreferences/default``.
    public init(isEnabled: Bool = true, timing: ReminderTiming = .both, monthlySummaryEnabled: Bool = true) {
        self.isEnabled = isEnabled
        self.timing = timing
        self.monthlySummaryEnabled = monthlySummaryEnabled
    }
}

/// Saves and loads the ``ReminderPreferences`` (storage is up to the implementation).
@MainActor
public protocol ReminderPreferencesStore: AnyObject {
    /// The saved preferences, or ``ReminderPreferences/default`` for anything never saved.
    func load() -> ReminderPreferences
    /// Saves `preferences`, replacing the previous ones.
    func save(_ preferences: ReminderPreferences)
}

/// A ``ReminderPreferencesStore`` that keeps the preferences in memory (previews, sample data, tests).
@MainActor
public final class InMemoryReminderPreferencesStore: ReminderPreferencesStore {
    private var preferences: ReminderPreferences

    /// Starts with `preferences` (default: ``ReminderPreferences/default``).
    public init(preferences: ReminderPreferences = .default) {
        self.preferences = preferences
    }

    public func load() -> ReminderPreferences {
        preferences
    }

    public func save(_ preferences: ReminderPreferences) {
        self.preferences = preferences
    }
}
