import Foundation
import Testing
import VademCore
import VademFeatures

@Suite("ReminderTiming and ReminderPreferences")
struct ReminderPreferencesTests {
    struct Case: Sendable {
        let timing: ReminderTiming
        let kinds: Set<PlannedReminder.Kind>
    }

    @Test("Timing maps to the planner kinds", arguments: [
        (ReminderTiming.both, Set<PlannedReminder.Kind>([.dayBefore, .dueDay])),
        (ReminderTiming.dueDay, Set<PlannedReminder.Kind>([.dueDay])),
        (ReminderTiming.dayBefore, Set<PlannedReminder.Kind>([.dayBefore])),
    ].map { Case(timing: $0.0, kinds: $0.1) })
    func kindsMapping(_ testCase: Case) {
        #expect(testCase.timing.kinds == testCase.kinds)
    }

    @Test("Default preferences: on, both")
    func defaults() {
        #expect(ReminderPreferences.default == ReminderPreferences(isEnabled: true, timing: .both))
        #expect(ReminderPreferences().isEnabled)
        #expect(ReminderPreferences().timing == .both)
    }

    @Test("Monthly summary is on by default and independent of the reminder switch")
    func summaryDefault() {
        #expect(ReminderPreferences.default.monthlySummaryEnabled)
        #expect(ReminderPreferences().monthlySummaryEnabled)
        #expect(ReminderPreferences(isEnabled: false).monthlySummaryEnabled)
        #expect(!ReminderPreferences(monthlySummaryEnabled: false).monthlySummaryEnabled)
        #expect(ReminderPreferences(monthlySummaryEnabled: false).isEnabled)
    }
}

@MainActor
@Suite("ReminderPreferencesStore")
struct ReminderPreferencesStoreTests {
    // Her test kendi UserDefaults paketini kullanır ve sonunda siler.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "vadem.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test("UserDefaults: nothing saved gives the defaults")
    func missingKeys() {
        withDefaults { defaults in
            let store = UserDefaultsReminderPreferencesStore(defaults: defaults)
            #expect(store.load() == .default)
        }
    }

    @Test("UserDefaults: save/load round trip", arguments: [
        ReminderPreferences(isEnabled: true, timing: .both),
        ReminderPreferences(isEnabled: false, timing: .both),
        ReminderPreferences(isEnabled: true, timing: .dueDay),
        ReminderPreferences(isEnabled: false, timing: .dayBefore),
    ])
    func roundTrip(preferences: ReminderPreferences) {
        withDefaults { defaults in
            UserDefaultsReminderPreferencesStore(defaults: defaults).save(preferences)
            // Yeni bir depo örneği aynı değeri okur.
            #expect(UserDefaultsReminderPreferencesStore(defaults: defaults).load() == preferences)
        }
    }

    @Test("UserDefaults: monthly summary round trip", arguments: [true, false])
    func summaryRoundTrip(enabled: Bool) {
        withDefaults { defaults in
            let preferences = ReminderPreferences(isEnabled: false, timing: .dueDay, monthlySummaryEnabled: enabled)
            UserDefaultsReminderPreferencesStore(defaults: defaults).save(preferences)
            #expect(UserDefaultsReminderPreferencesStore(defaults: defaults).load() == preferences)
            #expect(defaults.object(forKey: UserDefaultsReminderPreferencesStore.monthlySummaryEnabledKey) as? Bool == enabled)
        }
    }

    @Test("UserDefaults: a missing summary key means on, even when other keys are saved")
    func missingSummaryKeyIsOn() {
        withDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsReminderPreferencesStore.isEnabledKey)
            defaults.set("dueDay", forKey: UserDefaultsReminderPreferencesStore.timingKey)
            let loaded = UserDefaultsReminderPreferencesStore(defaults: defaults).load()
            #expect(loaded == ReminderPreferences(isEnabled: false, timing: .dueDay, monthlySummaryEnabled: true))
        }
    }

    @Test("UserDefaults: an explicit false summary key is kept")
    func explicitSummaryOff() {
        withDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsReminderPreferencesStore.monthlySummaryEnabledKey)
            #expect(!UserDefaultsReminderPreferencesStore(defaults: defaults).load().monthlySummaryEnabled)
        }
    }

    @Test("UserDefaults: unknown timing raw value falls back to default timing, keeps enabled flag")
    func unknownTiming() {
        withDefaults { defaults in
            defaults.set(false, forKey: UserDefaultsReminderPreferencesStore.isEnabledKey)
            defaults.set("weekly", forKey: UserDefaultsReminderPreferencesStore.timingKey)
            let loaded = UserDefaultsReminderPreferencesStore(defaults: defaults).load()
            #expect(loaded == ReminderPreferences(isEnabled: false, timing: .both))
        }
    }

    @Test("UserDefaults: a missing enabled key means on, even when timing is saved")
    func missingEnabledKeyIsOn() {
        withDefaults { defaults in
            defaults.set("dueDay", forKey: UserDefaultsReminderPreferencesStore.timingKey)
            let loaded = UserDefaultsReminderPreferencesStore(defaults: defaults).load()
            #expect(loaded == ReminderPreferences(isEnabled: true, timing: .dueDay))
        }
    }

    @Test("UserDefaults: save overwrites the previous value")
    func overwrite() {
        withDefaults { defaults in
            let store = UserDefaultsReminderPreferencesStore(defaults: defaults)
            store.save(ReminderPreferences(isEnabled: false, timing: .dueDay))
            store.save(ReminderPreferences(isEnabled: true, timing: .dayBefore))
            #expect(store.load() == ReminderPreferences(isEnabled: true, timing: .dayBefore))
        }
    }

    @Test("In-memory: starts with default or given preferences, save replaces")
    func inMemory() {
        #expect(InMemoryReminderPreferencesStore().load() == .default)
        let given = ReminderPreferences(isEnabled: false, timing: .dueDay)
        let store = InMemoryReminderPreferencesStore(preferences: given)
        #expect(store.load() == given)
        store.save(.default)
        #expect(store.load() == .default)
    }
}
