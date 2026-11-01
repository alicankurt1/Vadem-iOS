import Foundation
import Testing
import VademCore
import VademFeatures

// Tanıtımın açılıp açılmayacağına dair saf karar ve veri var mı sorusu.
@Suite("OnboardingDecision")
struct OnboardingDecisionTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let seen: Int?
        let current: Int
        let hasData: Bool
        let expected: OnboardingDecision
        let name: String
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(seen: nil, current: 1, hasData: false, expected: .show, name: "fresh install shows"),
        Case(seen: 1, current: 1, hasData: false, expected: .hide, name: "seen current hides"),
        Case(seen: 2, current: 1, hasData: false, expected: .hide, name: "seen newer hides"),
        Case(seen: 0, current: 1, hasData: false, expected: .show, name: "older version without data shows again"),
        Case(seen: nil, current: 1, hasData: true, expected: .hideAndMarkSeen, name: "existing user with data is marked seen"),
        Case(seen: 0, current: 1, hasData: true, expected: .hideAndMarkSeen, name: "older version with data is marked seen"),
        Case(seen: 1, current: 1, hasData: true, expected: .hide, name: "seen with data just hides"),
        Case(seen: 1, current: 2, hasData: false, expected: .show, name: "raised version shows again"),
    ]

    @Test("Decides from seen version and data", arguments: cases)
    func decides(_ testCase: Case) {
        let result = OnboardingDecision.decide(
            seenVersion: testCase.seen, currentVersion: testCase.current,
            hasData: testCase.hasData, launchArguments: []
        )
        #expect(result == testCase.expected)
    }

    @Test("Unrelated launch arguments change nothing")
    func unrelatedArguments() {
        let result = OnboardingDecision.decide(
            seenVersion: nil, hasData: false, launchArguments: ["-ui-static-motion", "-AppleLanguages"]
        )
        #expect(result == .show)
    }

    @Test("Launch argument names are the documented ones")
    func argumentNames() {
        #expect(OnboardingDecision.showLaunchArgument == "-ui-onboarding")
        #expect(OnboardingDecision.skipLaunchArgument == "-ui-skip-onboarding")
        #expect(OnboardingViewModel.seenVersionKey == "onboarding.seenVersion")
    }

    #if DEBUG
    @Test("-ui-onboarding shows even when seen, with data or on sample data")
    func showArgumentWins() {
        let args = ["-ui-sample-data", "-ui-onboarding", "-ui-skip-onboarding"]
        #expect(OnboardingDecision.decide(seenVersion: 1, hasData: true, launchArguments: args) == .show)
    }

    @Test("-ui-skip-onboarding hides a fresh install without saving")
    func skipArgumentHides() {
        let result = OnboardingDecision.decide(
            seenVersion: nil, hasData: false, launchArguments: ["-ui-skip-onboarding"]
        )
        #expect(result == .hide)
    }

    @Test("Sample-data launches hide by default and never mark seen")
    func sampleDataHides() {
        let result = OnboardingDecision.decide(
            seenVersion: nil, hasData: true, launchArguments: ["-ui-sample-data"]
        )
        #expect(result == .hide)
    }
    #endif
}

// Veri var mı: kart, taksit, abonelik ya da tek seferlik ödemeden biri yeter.
@MainActor
@Suite("HomeViewModel.hasAnyData")
struct HomeHasAnyDataTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func home(_ repository: InMemoryPaymentRepository) -> HomeViewModel {
        HomeViewModel(
            repository: repository,
            today: calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!,
            calendar: calendar
        )
    }

    @Test("Empty repository has no data")
    func empty() throws {
        #expect(try !Self.home(InMemoryPaymentRepository()).hasAnyData())
    }

    @Test("Each kind of record counts as data", arguments: ["card", "installment", "subscription", "oneTime"])
    func eachKind(_ kind: String) throws {
        let repository = InMemoryPaymentRepository()
        let month = try #require(YearMonth(year: 2026, month: 6))
        switch kind {
        case "card":
            try repository.save(#require(Card(id: UUID(), name: "Bonus", statementDay: 10, dueDay: 20)))
        case "installment":
            let plan = try #require(InstallmentPlan(total: Money(1200), count: 3, firstMonth: month))
            try repository.save(#require(InstallmentItem(
                id: UUID(), title: "Telefon", cardID: nil, paymentDay: 15, plan: plan
            )))
        case "subscription":
            let subscription = try #require(Subscription(
                amount: Money(99), period: .monthly, renewalDay: 5, firstMonth: month
            ))
            try repository.save(#require(SubscriptionItem(
                id: UUID(), title: "Müzik", cardID: nil, subscription: subscription
            )))
        default:
            try repository.save(#require(OneTimePaymentItem(
                id: UUID(), title: "Vergi", cardID: nil, amount: Money(250), dueMonth: month, dueDay: 15
            )))
        }
        #expect(try Self.home(repository).hasAnyData())
    }
}
