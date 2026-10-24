import Foundation

/// What the app refreshes outside Home when the payments or "today" may have changed:
/// the reminders and the widget timelines.
///
/// Sample-data and gallery launches use ``none`` so they never schedule reminders or touch WidgetKit.
@MainActor
public struct AppRefresh {
    private let reminders: ReminderScheduler?
    private let widgets: any WidgetReloading

    /// Creates the hooks; `reminders` is `nil` when no reminders are scheduled.
    public init(reminders: ReminderScheduler?, widgets: any WidgetReloading) {
        self.reminders = reminders
        self.widgets = widgets
    }

    /// Refreshes nothing (no reminders, ``NoWidgetReloading``).
    public static var none: AppRefresh {
        AppRefresh(reminders: nil, widgets: NoWidgetReloading())
    }

    /// Call after the payments changed (Home's `onDataChanged`).
    public func dataChanged() {
        refreshAll()
    }

    /// Call when the scene becomes active (the day may have changed, permissions may have changed).
    public func sceneBecameActive() {
        refreshAll()
    }

    // İki durumda da aynı iş: hatırlatmalar yeniden planlanır, widget yeni zaman çizelgesi ister.
    private func refreshAll() {
        if let reminders {
            Task { await reminders.refresh() }
        }
        widgets.reloadTimelines()
    }
}
