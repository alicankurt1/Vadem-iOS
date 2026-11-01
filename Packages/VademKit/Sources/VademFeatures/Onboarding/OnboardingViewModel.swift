import Foundation
import Observation
import VademCore

/// A page of the first-run walkthrough, in display order.
public enum OnboardingPage: Int, CaseIterable, Sendable, Hashable, Identifiable {
    /// "How much do I pay this month?" (Home).
    case monthlyTotal
    /// Adding installments and subscriptions with the ＋ button.
    case addPayments
    /// Importing from a statement (PDF or photo).
    case statementImport
    /// Due-date reminders, with "Turn on reminders" and "Not now".
    case reminders

    public var id: Int { rawValue }

    /// The 1-based page number used in the accessibility identifier `onboarding.page.<number>`.
    public var number: Int { rawValue + 1 }

    /// The SF Symbol shown above the title.
    public var systemImage: String {
        switch self {
        case .monthlyTotal: return "turkishlirasign.circle"
        case .addPayments: return "plus.circle"
        case .statementImport: return "doc.text.viewfinder"
        case .reminders: return "bell.badge"
        }
    }

    /// The page title.
    public var title: String {
        switch self {
        case .monthlyTotal:
            return String(localized: "How much do I pay this month?", bundle: .module)
        case .addPayments:
            return String(localized: "Add installments and subscriptions", bundle: .module, comment: "Walkthrough page 2 title")
        case .statementImport:
            return String(localized: "Import from a statement", bundle: .module, comment: "Walkthrough page 3 title")
        case .reminders:
            return String(localized: "Never miss a due date", bundle: .module, comment: "Walkthrough page 4 title")
        }
    }

    /// The one-sentence text under the title.
    public var message: String {
        switch self {
        case .monthlyTotal:
            return String(
                localized: "Vadem adds up your installments and subscriptions and shows this month's total at a glance.",
                bundle: .module, comment: "Walkthrough page 1 text"
            )
        case .addPayments:
            return String(
                localized: "Tap + to add an installment, a subscription or a one-time payment in a few quick steps.",
                bundle: .module, comment: "Walkthrough page 2 text"
            )
        case .statementImport:
            return String(
                localized: "Pick a statement PDF or photo; Vadem reads it on your device and lists the installments for you to review.",
                bundle: .module, comment: "Walkthrough page 3 text"
            )
        case .reminders:
            return String(
                localized: "Vadem can remind you the day before and on the day a payment is due.",
                bundle: .module, comment: "Walkthrough page 4 text"
            )
        }
    }
}

/// Drives the first-run walkthrough: the current page, Continue / Skip / Get started, the
/// reminder choice on the last page and the seen state.
///
/// The seen state is the walkthrough version saved under ``seenVersionKey`` in the injected
/// `UserDefaults`. Skip and Get started save it and call `onFinish`; neither asks for the
/// notification permission. "Turn on reminders" goes through ``SettingsViewModel/turnOnReminders()``
/// (which asks the system once); "Not now" turns payment reminders off with
/// ``SettingsViewModel/setEnabled(_:)``. Neither closes the walkthrough.
@MainActor
@Observable
public final class OnboardingViewModel: Identifiable {
    /// What the user chose on the reminders page.
    public enum ReminderChoice: Sendable, Hashable {
        /// "Turn on reminders" was tapped.
        case turnedOn
        /// "Not now" was tapped.
        case declined
    }

    /// The `UserDefaults` key of the seen walkthrough version (`Int`).
    public nonisolated static let seenVersionKey = "onboarding.seenVersion"

    /// The pages in display order.
    public let pages: [OnboardingPage] = OnboardingPage.allCases

    /// The index of the shown page in ``pages``; out-of-range values are clamped.
    public var pageIndex: Int = 0 {
        didSet {
            let clamped = min(max(pageIndex, 0), pages.count - 1)
            if clamped != pageIndex { pageIndex = clamped }
        }
    }

    /// The reminder choice, or `nil` before one was made.
    public private(set) var reminderChoice: ReminderChoice?
    /// `true` after Skip or Get started.
    public private(set) var isFinished = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reminders: SettingsViewModel?
    @ObservationIgnored private let onFinish: @MainActor () -> Void

    /// Creates the walkthrough on its first page.
    ///
    /// `defaults` keeps the seen version (tests pass `UserDefaults(suiteName:)`); `reminders` is the
    /// Settings model whose toggle the reminder choice changes (`nil` changes nothing); `onFinish`
    /// runs once after Skip or Get started.
    public init(
        defaults: UserDefaults = .standard,
        reminders: SettingsViewModel?,
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        self.defaults = defaults
        self.reminders = reminders
        self.onFinish = onFinish
    }

    /// The seen walkthrough version saved in `defaults`, or `nil` when it was never seen.
    public static func seenVersion(in defaults: UserDefaults = .standard) -> Int? {
        defaults.object(forKey: seenVersionKey) as? Int
    }

    /// The shown page.
    public var page: OnboardingPage { pages[pageIndex] }
    /// `true` on the reminders page.
    public var isLastPage: Bool { pageIndex == pages.count - 1 }
    /// Skip is offered on every page but the last.
    public var showsSkip: Bool { !isLastPage }
    /// `true` while "Turn on reminders" and "Not now" are offered (before a choice is made).
    public var showsReminderButtons: Bool { reminderChoice == nil }

    /// The line shown on the reminders page after a choice, or `nil` before one.
    public var reminderStatusText: String? {
        switch reminderChoice {
        case nil:
            return nil
        case .turnedOn:
            // İzin reddedildiyse Ayarlar'daki açıklama tekrarlanır; kullanıcı yine de devam eder.
            if reminders?.authorization == .denied { return SettingsView.permissionDeniedMessage }
            return String(localized: "Reminders are on.", bundle: .module, comment: "Walkthrough reminders page after turning them on")
        case .declined:
            return String(
                localized: "Reminders are off. You can turn them on in Settings.",
                bundle: .module, comment: "Walkthrough reminders page after Not now"
            )
        }
    }

    /// Continue: shows the next page; on the last page it is ``getStarted()``.
    public func continueTapped() {
        if isLastPage {
            getStarted()
        } else {
            pageIndex += 1
        }
    }

    /// Closes the walkthrough without asking for any permission and marks it seen.
    public func skip() {
        finish()
    }

    /// Closes the walkthrough from the last page and marks it seen.
    public func getStarted() {
        finish()
    }

    /// Turns payment reminders on and asks for the notification permission (once) through the
    /// Settings model.
    ///
    /// - Returns: The refresh; await its `value` to know it finished (`nil` without a Settings model).
    @discardableResult
    public func turnOnReminders() -> Task<Void, Never>? {
        guard reminderChoice == nil else { return nil }
        reminderChoice = .turnedOn
        return reminders?.turnOnReminders()
    }

    /// Turns payment reminders off; the walkthrough itself never asks for the permission here.
    ///
    /// - Returns: The refresh; await its `value` to know it finished (`nil` without a Settings model).
    @discardableResult
    public func notNow() -> Task<Void, Never>? {
        guard reminderChoice == nil else { return nil }
        reminderChoice = .declined
        return reminders?.setEnabled(false)
    }

    /// Saves ``OnboardingDecision/currentVersion`` as the seen version.
    public func markSeen() {
        Self.markSeen(in: defaults)
    }

    /// Saves ``OnboardingDecision/currentVersion`` as the seen version in `defaults`.
    public static func markSeen(in defaults: UserDefaults = .standard) {
        defaults.set(OnboardingDecision.currentVersion, forKey: seenVersionKey)
    }

    // Tek kapanış yolu: görüldü kaydedilir, kapatma bir kez çağrılır.
    private func finish() {
        guard !isFinished else { return }
        markSeen()
        isFinished = true
        onFinish()
    }
}
