import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("HomeViewModel settings wiring")
struct HomeSettingsWiringTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    }

    private static func home(settings: SettingsDependencies?) -> HomeViewModel {
        HomeViewModel(
            repository: InMemoryPaymentRepository(), today: today, calendar: calendar, settings: settings
        )
    }

    @Test("makeSettingsModel reflects the injected store and saves to it")
    func injectedStore() async {
        let saved = ReminderPreferences(isEnabled: false, timing: .dayBefore)
        let store = InMemoryReminderPreferencesStore(preferences: saved)
        let center = ReminderSchedulerTests.FakeCenter(status: .allowed)
        let home = Self.home(settings: SettingsDependencies(store: store, center: center))

        let model = home.makeSettingsModel()
        #expect(model.preferences == saved)
        #expect(!model.isEnabled)
        #expect(model.timing == .dayBefore)

        await model.setEnabled(true).value
        #expect(store.load() == ReminderPreferences(isEnabled: true, timing: .dayBefore))
        // Yeni bir model aynı depodan okur.
        #expect(home.makeSettingsModel().isEnabled)
        // Merkez enjekte edildiği için izin okunmuştur.
        #expect(model.authorization == .allowed)
    }

    @Test("Without settings the model gets a working in-memory store with default preferences")
    func defaultSettings() async {
        let home = Self.home(settings: nil)
        let model = home.makeSettingsModel()
        #expect(model.preferences == .default)
        #expect(model.authorization == nil)

        await model.setTiming(.dueDay).value
        #expect(model.timing == .dueDay)
        #expect(home.makeSettingsModel().timing == .dueDay)
    }
}
