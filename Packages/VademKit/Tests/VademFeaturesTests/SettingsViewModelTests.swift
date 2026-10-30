import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    private typealias Center = ReminderSchedulerTests.FakeCenter

    // Her denemede tercih kaydeden, kaç kez kaydedildiğini sayan depo.
    private final class CountingStore: ReminderPreferencesStore {
        var preferences: ReminderPreferences
        private(set) var saves: [ReminderPreferences] = []
        init(_ preferences: ReminderPreferences = .default) { self.preferences = preferences }
        func load() -> ReminderPreferences { preferences }
        func save(_ preferences: ReminderPreferences) {
            self.preferences = preferences
            saves.append(preferences)
        }
    }

    private static func model(
        store: any ReminderPreferencesStore = InMemoryReminderPreferencesStore(),
        center: (any ReminderCenter)? = nil,
        scheduler: ReminderScheduler? = nil,
        open: @escaping @MainActor () -> Void = {}
    ) -> SettingsViewModel {
        SettingsViewModel(dependencies: SettingsDependencies(
            store: store, center: center, scheduler: scheduler, openSystemSettings: open
        ))
    }

    // Sabit zamanlı, planlanacak ödemesi olan bir zamanlayıcı; merkez yenilemeyi kaydeder.
    private static func scheduler(center: Center, store: any ReminderPreferencesStore) throws -> ReminderScheduler {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let repository = InMemoryPaymentRepository()
        try repository.save(SubscriptionItem(
            id: UUID(), title: "Rent", cardID: nil,
            subscription: Subscription(
                amount: Money(1000), period: .monthly, renewalDay: 15, firstMonth: YearMonth(year: 2026, month: 1)!
            )!
        )!)
        return ReminderScheduler(
            repository: repository, center: center, preferences: store,
            calendar: calendar, now: { now }, formatAmount: { "TRY \($0.amount)" }
        )
    }

    @Test("Loads the saved preferences")
    func loadsPreferences() {
        let saved = ReminderPreferences(isEnabled: false, timing: .dayBefore)
        let model = Self.model(store: InMemoryReminderPreferencesStore(preferences: saved))
        #expect(model.preferences == saved)
        #expect(!model.isEnabled)
        #expect(model.timing == .dayBefore)
    }

    @Test("setEnabled saves immediately, before the refresh finishes")
    func setEnabledSaves() async {
        let store = CountingStore()
        let model = Self.model(store: store)
        let task = model.setEnabled(false)
        // Görev tamamlanmadan da kayıt yapılmıştır (eşzamanlı).
        #expect(store.preferences == ReminderPreferences(isEnabled: false, timing: .both))
        #expect(!model.isEnabled)
        await task.value
        #expect(store.saves.count == 1)
    }

    @Test("Monthly summary is on by default and shown independently of reminders")
    func summaryDefault() {
        #expect(Self.model().isMonthlySummaryEnabled)
        let remindersOff = Self.model(store: InMemoryReminderPreferencesStore(
            preferences: ReminderPreferences(isEnabled: false)
        ))
        #expect(remindersOff.isMonthlySummaryEnabled)
    }

    @Test("setMonthlySummaryEnabled saves immediately and keeps the other settings", arguments: [true, false])
    func setSummarySaves(enabled: Bool) async {
        let store = CountingStore(ReminderPreferences(isEnabled: false, timing: .dayBefore, monthlySummaryEnabled: !enabled))
        let model = Self.model(store: store)
        let task = model.setMonthlySummaryEnabled(enabled)
        #expect(store.preferences == ReminderPreferences(isEnabled: false, timing: .dayBefore, monthlySummaryEnabled: enabled))
        #expect(model.isMonthlySummaryEnabled == enabled)
        await task.value
        #expect(store.saves.count == 1)
    }

    @Test("Turning the summary off refreshes the scheduler: summary cancelled, no permission request")
    func summaryOffRefreshes() async throws {
        let center = Center(status: .allowed)
        let store = CountingStore()
        let scheduler = try Self.scheduler(center: center, store: store)
        let model = Self.model(store: store, center: center, scheduler: scheduler)
        await model.setMonthlySummaryEnabled(false).value
        #expect(center.replacedSummaries.last == .some(nil))
        #expect(center.requestCount == 0)
    }

    @Test("setTiming saves immediately and keeps the enabled flag", arguments: ReminderTiming.allCases)
    func setTimingSaves(timing: ReminderTiming) async {
        let store = CountingStore(ReminderPreferences(isEnabled: false, timing: .both))
        let model = Self.model(store: store)
        await model.setTiming(timing).value
        #expect(store.preferences == ReminderPreferences(isEnabled: false, timing: timing))
        #expect(model.timing == timing)
    }

    @Test("Titles and order of the timings")
    func timingTitles() {
        #expect(SettingsViewModel.timings == [.both, .dueDay, .dayBefore])
        #expect(Set(SettingsViewModel.timings.map(SettingsViewModel.title(of:))).count == 3)
        #expect(SettingsViewModel.title(of: .both) == "Day before and on the day")
        #expect(SettingsViewModel.title(of: .dueDay) == "On the day")
        #expect(SettingsViewModel.title(of: .dayBefore) == "Day before")
    }

    struct FlagCase: Sendable {
        let status: ReminderAuthorization
        let enabled: Bool
        let showsTiming: Bool
        let showsDenied: Bool
    }

    @Test("Flags by permission and enabled state", arguments: [
        FlagCase(status: .notDetermined, enabled: true, showsTiming: true, showsDenied: false),
        FlagCase(status: .allowed, enabled: true, showsTiming: true, showsDenied: false),
        FlagCase(status: .denied, enabled: true, showsTiming: true, showsDenied: true),
        FlagCase(status: .denied, enabled: false, showsTiming: false, showsDenied: false),
        FlagCase(status: .allowed, enabled: false, showsTiming: false, showsDenied: false),
    ])
    func flags(_ testCase: FlagCase) async {
        let center = Center(status: testCase.status)
        let model = Self.model(
            store: InMemoryReminderPreferencesStore(preferences: ReminderPreferences(isEnabled: testCase.enabled)),
            center: center
        )
        await model.loadAuthorization()
        #expect(model.authorization == testCase.status)
        #expect(model.showsTiming == testCase.showsTiming)
        #expect(model.showsPermissionDenied == testCase.showsDenied)
    }

    @Test("Without a center the permission stays nil and is never denied")
    func nilCenter() async {
        let model = Self.model()
        #expect(model.authorization == nil)
        await model.loadAuthorization()
        #expect(model.authorization == nil)
        #expect(!model.showsPermissionDenied)
        #expect(model.showsTiming)
    }

    @Test("Before loadAuthorization the permission is unknown")
    func beforeLoad() {
        let model = Self.model(center: Center(status: .denied))
        #expect(model.authorization == nil)
        #expect(!model.showsPermissionDenied)
    }

    @Test("openSystemSettings calls the injected closure once per call")
    func opensSettings() {
        var calls = 0
        let model = Self.model(open: { calls += 1 })
        model.openSystemSettings()
        #expect(calls == 1)
        model.openSystemSettings()
        #expect(calls == 2)
    }

    @Test("Each change refreshes the scheduler with the new preferences")
    func refreshesScheduler() async throws {
        let center = Center(status: .allowed)
        let store = InMemoryReminderPreferencesStore()
        let scheduler = try Self.scheduler(center: center, store: store)
        let model = Self.model(store: store, center: center, scheduler: scheduler)

        await model.setTiming(.dueDay).value
        #expect(center.replaced.count == 1)
        #expect(center.replaced.last?.isEmpty == false)
        #expect(center.replaced.last?.allSatisfy { $0.kind == .dueDay } == true)

        await model.setEnabled(false).value
        #expect(center.replaced.count == 2)
        #expect(center.replaced.last == [])

        await model.setEnabled(true).value
        await model.setTiming(.dayBefore).value
        #expect(center.replaced.count == 4)
        #expect(center.replaced.last?.isEmpty == false)
        #expect(center.replaced.last?.allSatisfy { $0.kind == .dayBefore } == true)
    }

    @Test("Turning reminders off does not ask for permission")
    func offDoesNotAsk() async throws {
        let center = Center(status: .notDetermined)
        let store = InMemoryReminderPreferencesStore()
        let model = Self.model(store: store, center: center, scheduler: try Self.scheduler(center: center, store: store))
        await model.setEnabled(false).value
        #expect(center.requestCount == 0)
    }

    @Test("After a change the permission is read again")
    func rereadsAuthorization() async throws {
        let center = Center(status: .notDetermined, requestResult: false)
        let store = InMemoryReminderPreferencesStore(preferences: ReminderPreferences(isEnabled: false))
        let model = Self.model(store: store, center: center, scheduler: try Self.scheduler(center: center, store: store))
        await model.loadAuthorization()
        #expect(model.authorization == .notDetermined)
        // Açınca izin istenir; sistem artık "denied" bildirir.
        center.status = .denied
        await model.setEnabled(true).value
        #expect(model.authorization == .denied)
        #expect(model.showsPermissionDenied)
    }

    @Test("Without a scheduler a change only saves")
    func noScheduler() async {
        let store = CountingStore()
        let model = Self.model(store: store)
        await model.setEnabled(false).value
        #expect(store.saves == [ReminderPreferences(isEnabled: false, timing: .both)])
    }
}
