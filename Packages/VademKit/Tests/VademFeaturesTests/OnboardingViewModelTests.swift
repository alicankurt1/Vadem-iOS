import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("OnboardingViewModel")
struct OnboardingViewModelTests {
    // Cevap gelince durumu değiştiren sahte merkez: izin penceresi "izin ver" ya da "izin verme" ile kapanır.
    @MainActor
    private final class PromptCenter: ReminderCenter {
        var status: ReminderAuthorization
        let grants: Bool
        private(set) var requestCount = 0
        init(status: ReminderAuthorization = .notDetermined, grants: Bool) {
            self.status = status
            self.grants = grants
        }
        func authorizationStatus() async -> ReminderAuthorization { status }
        func requestAuthorization() async throws -> Bool {
            requestCount += 1
            status = grants ? .allowed : .denied
            return grants
        }
        func replacePending(_ reminders: [PlannedReminder], summary: PlannedMonthlySummary?) async throws {}
    }

    private struct Setup {
        let model: OnboardingViewModel
        let settings: SettingsViewModel
        let center: PromptCenter
        let store: InMemoryReminderPreferencesStore
        let defaults: UserDefaults
        let finishCount: Counter
    }

    @MainActor final class Counter { var value = 0 }

    private static func defaults() -> UserDefaults {
        let suite = "onboarding.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func setup(
        status: ReminderAuthorization = .notDetermined, grants: Bool = true,
        preferences: ReminderPreferences = .default
    ) -> Setup {
        let center = PromptCenter(status: status, grants: grants)
        let store = InMemoryReminderPreferencesStore(preferences: preferences)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let scheduler = ReminderScheduler(
            repository: InMemoryPaymentRepository(), center: center, preferences: store,
            calendar: calendar, now: { Date(timeIntervalSince1970: 1_780_000_000) }, formatAmount: { "\($0.amount)" }
        )
        let settings = SettingsViewModel(dependencies: SettingsDependencies(
            store: store, center: center, scheduler: scheduler, openSystemSettings: {}
        ))
        let defaults = defaults()
        let counter = Counter()
        let model = OnboardingViewModel(defaults: defaults, reminders: settings, onFinish: { counter.value += 1 })
        return Setup(model: model, settings: settings, center: center, store: store, defaults: defaults, finishCount: counter)
    }

    // MARK: Sayfalar

    @Test("Has four pages in order, starting on the first")
    func fourPages() {
        let model = Self.setup().model
        #expect(model.pages == [.monthlyTotal, .addPayments, .statementImport, .reminders])
        #expect(model.pageIndex == 0)
        #expect(model.page == .monthlyTotal)
        #expect(OnboardingPage.allCases.map(\.number) == [1, 2, 3, 4])
    }

    @Test("Every page has a symbol, a title and a text")
    func pageContent() {
        for page in OnboardingPage.allCases {
            #expect(!page.systemImage.isEmpty)
            #expect(!page.title.isEmpty)
            #expect(!page.message.isEmpty)
        }
        #expect(Set(OnboardingPage.allCases.map(\.title)).count == 4)
    }

    @Test("Continue pages through to the last page")
    func continuePaging() {
        let setup = Self.setup()
        for expected in 1...3 {
            setup.model.continueTapped()
            #expect(setup.model.pageIndex == expected)
        }
        #expect(setup.model.isLastPage)
        #expect(!setup.model.isFinished)
        #expect(setup.finishCount.value == 0)
        #expect(OnboardingViewModel.seenVersion(in: setup.defaults) == nil)
    }

    @Test("Skip is offered on pages 1 to 3 and not on the last", arguments: [0, 1, 2, 3])
    func skipVisibility(_ index: Int) {
        let model = Self.setup().model
        model.pageIndex = index
        #expect(model.showsSkip == (index < 3))
        #expect(model.isLastPage == (index == 3))
    }

    @Test("Page index is clamped to the valid range", arguments: [(-5, 0), (-1, 0), (4, 3), (99, 3)])
    func clamps(_ input: (Int, Int)) {
        let model = Self.setup().model
        model.pageIndex = input.0
        #expect(model.pageIndex == input.1)
    }

    // MARK: Geç ve Başla

    @Test("Skip finishes, marks the current version seen and never asks for permission", arguments: [0, 1, 2])
    func skip(_ index: Int) async {
        let setup = Self.setup()
        setup.model.pageIndex = index
        setup.model.skip()
        #expect(setup.model.isFinished)
        #expect(setup.finishCount.value == 1)
        #expect(OnboardingViewModel.seenVersion(in: setup.defaults) == OnboardingDecision.currentVersion)
        await Task.yield()
        #expect(setup.center.requestCount == 0)
        #expect(setup.store.load() == .default)
    }

    @Test("Get started on the last page finishes and marks seen")
    func getStarted() {
        let setup = Self.setup()
        setup.model.pageIndex = 3
        setup.model.continueTapped()
        #expect(setup.model.isFinished)
        #expect(setup.finishCount.value == 1)
        #expect(OnboardingViewModel.seenVersion(in: setup.defaults) == OnboardingDecision.currentVersion)
        #expect(setup.center.requestCount == 0)
    }

    @Test("Finishing twice calls onFinish once")
    func finishOnce() {
        let setup = Self.setup()
        setup.model.skip()
        setup.model.skip()
        setup.model.getStarted()
        #expect(setup.finishCount.value == 1)
    }

    @Test("Seen version round-trips in an isolated suite and is nil before")
    func seenRoundTrip() {
        let defaults = Self.defaults()
        #expect(OnboardingViewModel.seenVersion(in: defaults) == nil)
        OnboardingViewModel.markSeen(in: defaults)
        #expect(OnboardingViewModel.seenVersion(in: defaults) == OnboardingDecision.currentVersion)
        #expect(defaults.integer(forKey: "onboarding.seenVersion") == OnboardingDecision.currentVersion)
    }

    @Test("Once seen, the decision hides it; a raised version shows it again")
    func seenFeedsDecision() {
        let defaults = Self.defaults()
        OnboardingViewModel.markSeen(in: defaults)
        let seen = OnboardingViewModel.seenVersion(in: defaults)
        #expect(OnboardingDecision.decide(seenVersion: seen, hasData: false, launchArguments: []) == .hide)
        #expect(OnboardingDecision.decide(
            seenVersion: seen, currentVersion: OnboardingDecision.currentVersion + 1, hasData: false, launchArguments: []
        ) == .show)
    }

    // MARK: Hatırlatma

    @Test("Turn on reminders asks the permission once and shows in Settings")
    func turnOn() async throws {
        let setup = Self.setup(preferences: ReminderPreferences(isEnabled: false, timing: .both))
        setup.model.pageIndex = 3
        #expect(setup.model.showsReminderButtons)
        #expect(setup.model.reminderStatusText == nil)

        let task = try #require(setup.model.turnOnReminders())
        await task.value

        #expect(setup.center.requestCount == 1)
        #expect(setup.settings.isEnabled)
        #expect(setup.store.load().isEnabled)
        #expect(setup.settings.authorization == .allowed)
        #expect(setup.model.reminderChoice == .turnedOn)
        #expect(!setup.model.showsReminderButtons)
        #expect(setup.model.reminderStatusText != nil)
        // Seçim tanıtımı kapatmaz.
        #expect(!setup.model.isFinished)

        // İkinci dokunuş yeniden sormaz.
        #expect(setup.model.turnOnReminders() == nil)
        #expect(setup.center.requestCount == 1)
    }

    @Test("Turn on reminders with a denied answer is reflected and does not block")
    func turnOnDenied() async throws {
        let setup = Self.setup(grants: false)
        let task = try #require(setup.model.turnOnReminders())
        await task.value
        #expect(setup.center.requestCount == 1)
        #expect(setup.settings.authorization == .denied)
        #expect(setup.model.reminderStatusText == SettingsView.permissionDeniedMessage)
        #expect(!setup.model.isFinished)
        setup.model.getStarted()
        #expect(setup.model.isFinished)
    }

    @Test("Turn on reminders does not ask again when already denied")
    func alreadyDenied() async throws {
        let setup = Self.setup(status: .denied)
        await setup.model.turnOnReminders()?.value
        #expect(setup.center.requestCount == 0)
        #expect(setup.settings.authorization == .denied)
    }

    @Test("Turn on reminders does not ask when already allowed")
    func alreadyAllowed() async throws {
        let setup = Self.setup(status: .allowed)
        await setup.model.turnOnReminders()?.value
        #expect(setup.center.requestCount == 0)
        #expect(setup.settings.isEnabled)
    }

    @Test("Not now leaves reminders off and never asks for permission")
    func notNow() async throws {
        let setup = Self.setup()
        #expect(setup.settings.isEnabled)
        let task = try #require(setup.model.notNow())
        await task.value
        #expect(!setup.settings.isEnabled)
        #expect(!setup.store.load().isEnabled)
        #expect(setup.center.requestCount == 0)
        #expect(setup.model.reminderChoice == .declined)
        #expect(!setup.model.showsReminderButtons)
        #expect(setup.model.reminderStatusText != nil)
        #expect(!setup.model.isFinished)
        // Kullanıcı yine de ilerleyebilir.
        setup.model.pageIndex = 3
        setup.model.continueTapped()
        #expect(setup.model.isFinished)
    }

    @Test("A second choice after the first is ignored")
    func choiceOnce() async throws {
        let setup = Self.setup()
        await setup.model.notNow()?.value
        #expect(setup.model.turnOnReminders() == nil)
        #expect(!setup.settings.isEnabled)
        #expect(setup.center.requestCount == 0)
    }

    @Test("makeOnboardingModel ties the walkthrough to the same Settings model")
    func settingsFactory() async throws {
        let setup = Self.setup(preferences: ReminderPreferences(isEnabled: false, timing: .both))
        let counter = Counter()
        let model = setup.settings.makeOnboardingModel(defaults: setup.defaults) { counter.value += 1 }
        #expect(model.page == .monthlyTotal)
        await model.turnOnReminders()?.value
        #expect(setup.settings.isEnabled)
        model.skip()
        #expect(counter.value == 1)
    }

    // MARK: Yeniden gösterim (Ayarlar'dan)

    private static func replay(remindersOn: Bool, status: ReminderAuthorization = .notDetermined) -> (Setup, OnboardingViewModel) {
        let setup = setup(status: status, preferences: ReminderPreferences(isEnabled: remindersOn, timing: .both))
        let model = setup.settings.makeOnboardingModel(defaults: setup.defaults, isReplay: true)
        model.pageIndex = 3
        return (setup, model)
    }

    @Test("First run is not a replay and still turns reminders off with Not now")
    func firstRunUnchanged() async throws {
        let setup = Self.setup()
        #expect(!setup.model.isReplay)
        #expect(setup.model.showsReminderButtons)
        await setup.model.notNow()?.value
        #expect(!setup.settings.isEnabled)
        #expect(!setup.store.load().isEnabled)
    }

    @Test("Replay with reminders on offers no buttons and says reminders are on")
    func replayOnNoButtons() {
        let (setup, model) = Self.replay(remindersOn: true)
        #expect(model.isReplay)
        #expect(!model.showsReminderButtons)
        #expect(model.reminderStatusText != nil)
        #expect(model.reminderChoice == nil)
        #expect(setup.settings.isEnabled)
    }

    @Test("Replay with reminders on: Not now and Turn on do nothing and keep reminders on")
    func replayOnChoicesIgnored() async {
        let (setup, model) = Self.replay(remindersOn: true)
        #expect(model.notNow() == nil)
        #expect(model.turnOnReminders() == nil)
        await Task.yield()
        #expect(setup.settings.isEnabled)
        #expect(setup.store.load().isEnabled)
        #expect(setup.center.requestCount == 0)
        #expect(model.reminderChoice == nil)
    }

    @Test("Replay with reminders off offers both buttons")
    func replayOffButtons() {
        let (_, model) = Self.replay(remindersOn: false)
        #expect(model.showsReminderButtons)
        #expect(model.reminderStatusText == nil)
    }

    @Test("Replay with reminders off: Not now records the choice and keeps them off without a prompt")
    func replayOffNotNow() async {
        let (setup, model) = Self.replay(remindersOn: false)
        let task = model.notNow()
        await task?.value
        #expect(model.reminderChoice == .declined)
        #expect(!model.showsReminderButtons)
        #expect(model.reminderStatusText != nil)
        #expect(!setup.settings.isEnabled)
        #expect(!setup.store.load().isEnabled)
        #expect(setup.center.requestCount == 0)
    }

    @Test("Replay with reminders off: Turn on reminders asks once and turns them on")
    func replayOffTurnOn() async throws {
        let (setup, model) = Self.replay(remindersOn: false)
        let task = try #require(model.turnOnReminders())
        await task.value
        #expect(setup.center.requestCount == 1)
        #expect(setup.settings.isEnabled)
        #expect(setup.settings.authorization == .allowed)
        #expect(model.reminderChoice == .turnedOn)
        #expect(model.turnOnReminders() == nil)
        #expect(setup.center.requestCount == 1)
    }

    @Test("Replay Skip and Get started still mark seen and finish")
    func replayFinishes() {
        let (setup, model) = Self.replay(remindersOn: true)
        model.continueTapped()
        #expect(model.isFinished)
        #expect(OnboardingViewModel.seenVersion(in: setup.defaults) == OnboardingDecision.currentVersion)
        #expect(setup.center.requestCount == 0)
    }
}
