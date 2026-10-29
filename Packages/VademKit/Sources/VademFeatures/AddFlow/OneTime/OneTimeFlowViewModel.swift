import Foundation
import Observation
import VademCore

/// The steps of the one-time payment add flow (``OneTimeFlowView``), in order.
public enum OneTimeFlowStep: String, CaseIterable, Sendable, Identifiable {
    /// The ``AmountKeypad`` ("How much?").
    case amount
    /// Today / Tomorrow / Pick a date chips ("When is it due?").
    case date
    /// The ``CardPickerStep`` ("Which card?").
    case card
    /// Optional title: typed, a quick chip, or Skip ("What is it for?").
    case title
    /// Everything chosen so far and the Save button.
    case summary

    public var id: String { rawValue }

    /// The launch argument that opens Home with the flow presented at this step (UI check):
    /// `-ui-add-onetime-flow-<step>`, e.g. `-ui-add-onetime-flow-summary`.
    public var launchArgument: String { "-ui-add-onetime-flow-\(rawValue)" }

    /// The step whose ``launchArgument`` is in `arguments` (the first in step order), or `nil`.
    public static func step(in arguments: [String]) -> OneTimeFlowStep? {
        allCases.first { arguments.contains($0.launchArgument) }
    }
}

/// A chip of the date step.
public enum OneTimeDateChoice: Hashable, Sendable, CaseIterable {
    /// The injected today.
    case today
    /// The day after today (the 1st of next month on the last day of a month).
    case tomorrow
    /// Any day: month and day steppers, then Continue.
    case pick
}

/// Drives the one-time payment add flow (amount → date → card → title → summary).
///
/// The flow builds a ``OneTimePaymentDraft`` (validated like every one-time payment) and saves the
/// ``OneTimePaymentItem`` through ``PaymentRepository``. An empty title is saved as ``defaultTitle``.
/// "Today" is injected (`todayMonth`, `todayDay`), never read from the clock. The due date starts at today.
/// After a successful ``save()`` the chosen card (or "No card") is remembered in the ``LastUsedCardStore``.
@MainActor
@Observable
public final class OneTimeFlowViewModel: Identifiable {
    /// The title saved when the title step is skipped or left empty: "Payment" ("Ödeme").
    public nonisolated static var defaultTitle: String {
        String(localized: "Payment", bundle: .module)
    }

    /// The quick title chips of the title step, in order.
    public nonisolated static var quickTitles: [String] {
        [
            String(localized: "Doctor", bundle: .module, comment: "Quick title chip of the one-time payment flow"),
            String(localized: "Repair", bundle: .module, comment: "Quick title chip of the one-time payment flow"),
            String(localized: "Gift", bundle: .module, comment: "Quick title chip of the one-time payment flow"),
            String(localized: "Tax", bundle: .module, comment: "Quick title chip of the one-time payment flow"),
            String(localized: "Ticket", bundle: .module, comment: "Quick title chip of the one-time payment flow"),
        ]
    }

    /// How many months before today's month "Pick a date" offers.
    public nonisolated static let monthsBefore = 12
    /// How many months after today's month "Pick a date" offers.
    public nonisolated static let monthsAfter = 24

    /// The steps and which one is showing.
    public private(set) var steps: FlowSteps<OneTimeFlowStep>
    /// The amount keypad's state; ``AmountKeypadState/amount`` is the payment's amount.
    public var keypad: AmountKeypadState
    /// The month of the due date; starts at today's month.
    public private(set) var dueMonth: YearMonth
    /// The day of ``dueMonth`` the payment is due on; starts at today.
    public private(set) var dueDay: Int
    /// The chip chosen on the date step, or `nil` before it is decided.
    public private(set) var dateChoice: OneTimeDateChoice?
    /// The chosen card, or `nil` for "No card".
    public private(set) var cardID: Card.ID?
    /// The title as typed or chosen; may be empty (``resolvedTitle`` then is ``defaultTitle``).
    public var title: String = ""
    /// The cards to choose from, in the repository's order, plus any card added with "New card".
    public private(set) var cards: [Card] = []
    /// The months "Pick a date" offers, in order; contains today's month.
    public let monthOptions: [YearMonth]
    /// A message for a load or save failure, or `nil`.
    public private(set) var failureMessage: String?

    @ObservationIgnored private let repository: any PaymentRepository
    @ObservationIgnored private let lastUsedCard: LastUsedCardStore
    @ObservationIgnored private let todayMonth: YearMonth
    @ObservationIgnored private let todayDay: Int

    /// Creates the flow at `start` and loads the cards.
    ///
    /// `lastUsedCardID` is preselected when it is one of the cards
    /// (``CardPicker/initialSelection(cards:lastUsedCardID:)``), otherwise "No card"; `lastUsedCard`
    /// remembers the card after a save. `todayMonth` and `todayDay` are "today" (the Today and Tomorrow
    /// chips, the first due date). `amount` starts the keypad with a value (UI check); `locale`
    /// decides the keypad's decimal separator.
    public init(
        repository: any PaymentRepository,
        todayMonth: YearMonth,
        todayDay: Int,
        lastUsedCardID: Card.ID?,
        lastUsedCard: LastUsedCardStore,
        start: OneTimeFlowStep = .amount,
        amount: Decimal? = nil,
        locale: Locale = .current
    ) {
        self.repository = repository
        self.lastUsedCard = lastUsedCard
        self.todayMonth = todayMonth
        // Ayda olmayan bir gün verilirse ayın son gününe kırpılır.
        let today = min(max(todayDay, 1), todayMonth.numberOfDays)
        self.todayDay = today
        self.dueMonth = todayMonth
        self.dueDay = today
        self.steps = FlowSteps(OneTimeFlowStep.allCases, startingAt: start)
        self.keypad = AmountKeypadState(amount: amount, locale: locale)
        self.monthOptions = MonthOptions.months(around: todayMonth, before: Self.monthsBefore, after: Self.monthsAfter)
        loadCards()
        cardID = CardPicker.initialSelection(cards: cards, lastUsedCardID: lastUsedCardID)
    }

    private func loadCards() {
        do {
            cards = try repository.cards()
        } catch {
            failureMessage = AddInstallmentViewModel.cardsLoadErrorMessage
        }
    }

    // MARK: Adımlar

    /// The step showing.
    public var step: OneTimeFlowStep { steps.current }

    /// The question shown as the header of `step`.
    public func title(of step: OneTimeFlowStep) -> String {
        switch step {
        case .amount: String(localized: "How much?", bundle: .module)
        case .date: String(localized: "When is it due?", bundle: .module)
        case .card: String(localized: "Which card?", bundle: .module)
        case .title: String(localized: "What is it for?", bundle: .module)
        case .summary: String(localized: "Check and save", bundle: .module)
        }
    }

    /// `true` when the current step shows a Continue button: the amount and title steps,
    /// and the date step while "Pick a date" is open.
    public var showsContinue: Bool {
        switch step {
        case .amount, .title: true
        case .date: dateChoice == .pick
        case .card, .summary: false
        }
    }

    /// `true` when Continue is enabled: an amount above zero on the amount step,
    /// a title of valid length (or empty) on the title step.
    public var canContinue: Bool {
        switch step {
        case .amount: keypad.isPositive
        case .title: !isTitleTooLong
        case .date, .card, .summary: true
        }
    }

    /// Advances from a step with a Continue button (see ``showsContinue``); ignored while
    /// ``canContinue`` is `false` or the step has no Continue button.
    public func continueFromCurrentStep() {
        guard showsContinue, canContinue else { return }
        steps.advance()
    }

    /// Moves to the previous step; returns `false` on the first step (the presenter leaves the flow).
    @discardableResult
    public func goBack() -> Bool {
        steps.goBack()
    }

    // MARK: Tarih

    /// Applies a date chip: Today and Tomorrow set the due date (from today) and advance;
    /// Pick a date shows the month and day steppers and stays.
    public func chooseDate(_ choice: OneTimeDateChoice) {
        dateChoice = choice
        switch choice {
        case .today:
            dueMonth = todayMonth
            dueDay = todayDay
            steps.advance()
        case .tomorrow:
            // Ayın son günüyse yarın sonraki ayın 1'idir.
            if todayDay < todayMonth.numberOfDays {
                dueMonth = todayMonth
                dueDay = todayDay + 1
            } else {
                dueMonth = todayMonth.adding(months: 1)
                dueDay = 1
            }
            steps.advance()
        case .pick:
            break
        }
    }

    /// The index of ``dueMonth`` in ``monthOptions`` (for the month stepper).
    public var dueMonthIndex: Int {
        monthOptions.firstIndex(of: dueMonth) ?? 0
    }

    /// Sets ``dueMonth`` to the option at `index`, clamped to ``monthOptions``; ``dueDay`` is
    /// clamped to the new month's days (e.g. 31 → 28 in February).
    public func setDueMonthIndex(_ index: Int) {
        guard !monthOptions.isEmpty else { return }
        dueMonth = monthOptions[min(max(index, 0), monthOptions.count - 1)]
        dueDay = min(dueDay, dueMonth.numberOfDays)
    }

    /// Sets ``dueDay``, clamped to the days of ``dueMonth``.
    public func setDueDay(_ day: Int) {
        dueDay = min(max(day, 1), dueMonth.numberOfDays)
    }

    /// The due date as `"12 October 2026"`-style text: the day and month title.
    public var dueDateText: String {
        "\(VademLocalization.dayTitle(day: dueDay, of: dueMonth)) \(dueMonth.year)"
    }

    /// The month as `"October 2026"`, like Home.
    public func title(of month: YearMonth) -> String {
        HomeViewModel.title(of: month)
    }

    // MARK: Kart

    /// Chooses `id` (`nil`: No card) and advances.
    public func chooseCard(_ id: Card.ID?) {
        cardID = id
        steps.advance()
    }

    /// A new add-card form on the same repository; pass its saved card to ``selectAddedCard(_:)``.
    public func makeAddCardModel() -> AddCardViewModel {
        AddCardViewModel(repository: repository)
    }

    /// Adds `card` (saved by the add-card form) to ``cards`` and chooses it (and advances).
    public func selectAddedCard(_ card: Card) {
        if !cards.contains(where: { $0.id == card.id }) { cards.append(card) }
        chooseCard(card.id)
    }

    /// The chosen card's name, or "No card".
    public var cardTitle: String {
        cards.first { $0.id == cardID }?.name ?? String(localized: "No card", bundle: .module)
    }

    // MARK: Başlık

    /// Uses `title` (a quick chip) and advances.
    public func chooseTitle(_ title: String) {
        self.title = title
        steps.advance()
    }

    /// Clears the title (``defaultTitle`` is saved) and advances.
    public func skipTitle() {
        title = ""
        steps.advance()
    }

    /// The title that is saved: the trimmed ``title``, or ``defaultTitle`` when it is empty.
    public var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTitle : trimmed
    }

    /// `true` when the typed title is longer than ``OneTimePaymentItem/maxTitleLength``.
    public var isTitleTooLong: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count > OneTimePaymentItem.maxTitleLength
    }

    // MARK: Kaydetme

    /// The draft built from the choices, with ``resolvedTitle`` as its title: what Save stores.
    public var draft: OneTimePaymentDraft {
        OneTimePaymentDraft(
            title: resolvedTitle, cardID: cardID, amount: keypad.amount, dueMonth: dueMonth, dueDay: dueDay
        )
    }

    /// `true` when ``draft`` is valid, so Save is enabled.
    public var canSave: Bool { draft.isValid }

    /// Saves the draft as a new one-time payment and remembers the chosen card.
    ///
    /// Returns `true` on success; an invalid draft returns `false`, a repository error sets
    /// ``failureMessage`` and returns `false`.
    @discardableResult
    public func save() -> Bool {
        guard let item = draft.makeItem() else { return false }
        do {
            try repository.save(item)
            failureMessage = nil
            lastUsedCard.cardID = cardID
            return true
        } catch {
            failureMessage = EditOneTimePaymentViewModel.saveErrorMessage
            return false
        }
    }
}
