import SwiftUI

/// The app's top-level tabs, in the order the ``FloatingTabBar`` shows them.
///
/// Identifiers: `tab.home`, `tab.analytics`, `tab.cards`, `tab.settings` (``accessibilityIdentifier``)
/// and `tab.add` (``addIdentifier``, the separate ＋ button).
public enum AppTab: String, CaseIterable, Sendable, Hashable, Identifiable {
    /// This month: the Home screen.
    case home
    /// The Analytics chart.
    case analytics
    /// The card list.
    case cards
    /// Reminders, privacy policy and version.
    case settings

    public var id: Self { self }

    /// The tab's label, e.g. `"This month"`.
    public var title: String {
        switch self {
        case .home: return String(localized: "This month", bundle: .module)
        case .analytics: return String(localized: "Analytics", bundle: .module)
        case .cards: return String(localized: "Cards", bundle: .module)
        case .settings: return String(localized: "Settings", bundle: .module)
        }
    }

    /// The tab's SF Symbol.
    public var systemImage: String {
        switch self {
        case .home: return "calendar"
        case .analytics: return "chart.bar"
        case .cards: return "creditcard"
        case .settings: return "gearshape"
        }
    }

    /// The tab button's accessibility identifier, e.g. `"tab.home"`.
    public var accessibilityIdentifier: String { "tab.\(rawValue)" }

    /// The accessibility identifier of the ＋ (Add) button next to the tabs.
    public static let addIdentifier = "tab.add"

    /// The launch argument that opens the app on this tab (debug builds), e.g. `"-ui-tab-analytics"`.
    public var launchArgument: String { "-ui-tab-\(rawValue)" }

    /// The tab a debug launch argument opens, or `nil` when none of them is given (Home is shown).
    ///
    /// ``launchArgument`` selects its tab. Screen arguments select the tab that shows the screen:
    /// ``AnalyticsView/launchArgument`` → ``analytics``; ``CardListView/launchArgument`` and
    /// ``CardListView/emptyLaunchArgument`` → ``cards``; ``SettingsView/launchArgument``,
    /// ``SettingsView/deniedLaunchArgument`` and ``PrivacyPolicyView/launchArgument`` → ``settings``.
    /// The first match in tab order wins.
    public static func launchTab(in arguments: [String]) -> AppTab? {
        allCases.first { tab in
            tab.screenLaunchArguments.contains { arguments.contains($0) }
        }
    }

    // Bu sekmeyi seçen başlatma argümanları: sekmenin kendi argümanı ve sekmedeki ekranlarınki.
    private var screenLaunchArguments: [String] {
        switch self {
        case .home:
            return [launchArgument]
        case .analytics:
            return [launchArgument, AnalyticsView.launchArgument]
        case .cards:
            return [launchArgument, CardListView.launchArgument, CardListView.emptyLaunchArgument]
        case .settings:
            return [
                launchArgument, SettingsView.launchArgument, SettingsView.deniedLaunchArgument,
                PrivacyPolicyView.launchArgument,
            ]
        }
    }
}

public extension EnvironmentValues {
    /// The tab the ``AppTabShell`` shows; ``AppTab/home`` outside the shell.
    ///
    /// Views can read it for a per-tab look (e.g. tint or background).
    @Entry var selectedAppTab: AppTab = .home
}
