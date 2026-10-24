import Foundation

/// Asks the system to rebuild the widget timelines (e.g. after the payments changed).
///
/// The WidgetKit-backed implementation lives in the app target; the package never imports WidgetKit.
@MainActor
public protocol WidgetReloading {
    /// Asks every widget of the app for a new timeline.
    func reloadTimelines()
}

/// A ``WidgetReloading`` that does nothing: tests, previews, sample-data and gallery launches.
public struct NoWidgetReloading: WidgetReloading {
    /// Creates the no-op reloader.
    public init() {}

    /// Does nothing.
    public func reloadTimelines() {}
}
