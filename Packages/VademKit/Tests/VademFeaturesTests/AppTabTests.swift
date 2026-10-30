import Testing
import VademFeatures

@Suite("AppTab")
struct AppTabTests {
    @Test("Tabs are in bar order: This month, Analytics, Cards, Settings")
    func order() {
        #expect(AppTab.allCases == [.home, .analytics, .cards, .settings])
    }

    @Test("Stable accessibility identifiers", arguments: [
        (AppTab.home, "tab.home"),
        (AppTab.analytics, "tab.analytics"),
        (AppTab.cards, "tab.cards"),
        (AppTab.settings, "tab.settings"),
    ])
    func identifiers(tab: AppTab, expected: String) {
        #expect(tab.accessibilityIdentifier == expected)
    }

    @Test("Add button identifier is tab.add")
    func addIdentifier() {
        #expect(AppTab.addIdentifier == "tab.add")
    }

    @Test("Identifiers and symbols are unique")
    func unique() {
        #expect(Set(AppTab.allCases.map(\.accessibilityIdentifier)).count == 4)
        #expect(Set(AppTab.allCases.map(\.systemImage)).count == 4)
        #expect(!AppTab.allCases.contains { $0.title.isEmpty })
    }

    @Test("Each tab has its own launch argument", arguments: [
        (AppTab.home, "-ui-tab-home"),
        (AppTab.analytics, "-ui-tab-analytics"),
        (AppTab.cards, "-ui-tab-cards"),
        (AppTab.settings, "-ui-tab-settings"),
    ])
    func tabLaunchArgument(tab: AppTab, argument: String) {
        #expect(tab.launchArgument == argument)
        #expect(AppTab.launchTab(in: [argument]) == tab)
    }

    @Test("Screen launch arguments select the tab that shows the screen", arguments: [
        ("-ui-analytics", AppTab.analytics),
        ("-ui-card-list", AppTab.cards),
        ("-ui-card-list-empty", AppTab.cards),
        ("-ui-settings", AppTab.settings),
        ("-ui-settings-denied", AppTab.settings),
        ("-ui-privacy-policy", AppTab.settings),
    ])
    func screenArguments(argument: String, expected: AppTab) {
        #expect(AppTab.launchTab(in: ["-ui-sample-data", argument]) == expected)
    }

    @Test("No tab argument means no override (Home is shown)", arguments: [
        [String](), ["-ui-sample-data"], ["-ui-static-motion", "-ui-add-sheet"],
    ])
    func noOverride(arguments: [String]) {
        #expect(AppTab.launchTab(in: arguments) == nil)
    }

    @Test("Argument position does not matter")
    func position() {
        #expect(AppTab.launchTab(in: ["-ui-settings", "-ui-sample-data"]) == .settings)
        #expect(AppTab.launchTab(in: ["-ui-sample-data", "-ui-settings"]) == .settings)
    }
}
